#!/usr/bin/env python3
"""
InteractiveSAMEngine – Decoupled SAM2 Segmentation Engine
==========================================================

Paradigm shift: NO automatic bounding boxes, NO text queries, NO grid anchors.

Architecture:
  1. predict_encoder(image) → Run SAM2 Image Encoder ONCE per upload.
     Returns a feature embedding dict that is cached server-side.

  2. predict_decoder(embedding, points) → Run the lightweight SAM2 Mask Decoder
     with user-provided interactive point prompts (positive taps + negative
     refinement taps). Returns a high-fidelity binary mask.

The frontend sends normalized [0.0–1.0] coordinates. This engine maps them
to native pixel dimensions before feeding to the SAM2 decoder.
"""

import os
import numpy as np
import torch
import cv2
from PIL import Image
from typing import List, Dict, Tuple, Optional


class InteractiveSAMEngine:
    """
    Decoupled SAM2 segmentation engine for interactive, user-guided mask generation.

    Usage:
        engine = InteractiveSAMEngine(device="cuda")

        # Step 1 – Run once per image upload
        embedding = engine.predict_encoder(image_np)

        # Step 2 – Run per user interaction (fast)
        mask = engine.predict_decoder(
            embedding,
            points=[{"x": 0.5, "y": 0.3, "label": 1}],
            image_size=(1024, 768)
        )
    """

    def __init__(self, model_variant: str = "sam2_hiera_tiny", device: str = None):
        """
        Initialize the InteractiveSAMEngine.

        Args:
            model_variant: SAM2 model checkpoint variant. One of:
                           'sam2_hiera_tiny', 'sam2_hiera_small',
                           'sam2_hiera_base_plus', 'sam2_hiera_large'.
            device: Hardware device ('cuda', 'mps', or 'cpu'). Auto-detected if None.
        """
        if device is None:
            if torch.cuda.is_available():
                self.device = "cuda"
            elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                self.device = "mps"
            else:
                self.device = "cpu"
        else:
            self.device = device

        self.model_variant = model_variant
        self._predictor = None
        print(f"[InteractiveSAMEngine] Initialized | variant={model_variant} | device={self.device}")

    # ── Lazy Model Loader ─────────────────────────────────────────────────────

    def _get_predictor(self):
        """Lazy-load the SAM2 predictor to keep startup fast."""
        if self._predictor is None:
            print(f"[InteractiveSAMEngine] Loading SAM2 predictor ({self.model_variant})...")
            
            # 1. Configuration Mapping (supports 2.0 & 2.1)
            config_mapping = {
                # SAM2.0
                "sam2_hiera_tiny": "sam2/sam2_hiera_t.yaml",
                "sam2_hiera_small": "sam2/sam2_hiera_s.yaml",
                "sam2_hiera_base_plus": "sam2/sam2_hiera_b+.yaml",
                "sam2_hiera_large": "sam2/sam2_hiera_l.yaml",
                # SAM2.1
                "sam2.1_hiera_tiny": "sam2.1/sam2.1_hiera_t.yaml",
                "sam2.1_hiera_small": "sam2.1/sam2.1_hiera_s.yaml",
                "sam2.1_hiera_base_plus": "sam2.1/sam2.1_hiera_b+.yaml",
                "sam2.1_hiera_large": "sam2.1/sam2.1_hiera_l.yaml",
            }
            model_cfg = config_mapping.get(self.model_variant, "sam2/sam2_hiera_t.yaml")

            # 2. Checkpoint mapping & resolver
            checkpoint_mapping = {
                "sam2_hiera_tiny": "sam2_hiera_tiny.pt",
                "sam2_hiera_small": "sam2_hiera_small.pt",
                "sam2_hiera_base_plus": "sam2_hiera_base_plus.pt",
                "sam2_hiera_large": "sam2_hiera_large.pt",
                "sam2.1_hiera_tiny": "sam2.1_hiera_tiny.pt",
                "sam2.1_hiera_small": "sam2.1_hiera_small.pt",
                "sam2.1_hiera_base_plus": "sam2.1_hiera_base_plus.pt",
                "sam2.1_hiera_large": "sam2.1_hiera_large.pt",
            }
            ckpt_name = checkpoint_mapping.get(self.model_variant, "sam2_hiera_tiny.pt")
            
            # Resolve checkpoint file path
            cache_dir = os.path.join(os.path.expanduser("~"), ".cache", "torch", "hub", "checkpoints")
            os.makedirs(cache_dir, exist_ok=True)
            checkpoint_path = os.path.join(cache_dir, ckpt_name)
            
            # If checkpoint file doesn't exist, download it
            if not os.path.exists(checkpoint_path):
                urls = {
                    "sam2_hiera_tiny": "https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_tiny.pt",
                    "sam2_hiera_small": "https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_small.pt",
                    "sam2_hiera_base_plus": "https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_base_plus.pt",
                    "sam2_hiera_large": "https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_large.pt",
                    "sam2.1_hiera_tiny": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_tiny.pt",
                    "sam2.1_hiera_small": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_small.pt",
                    "sam2.1_hiera_base_plus": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_base_plus.pt",
                    "sam2.1_hiera_large": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt",
                }
                url = urls.get(self.model_variant, urls["sam2_hiera_tiny"])
                print(f"[InteractiveSAMEngine] Downloading checkpoint from {url} to {checkpoint_path}...")
                try:
                    import urllib.request
                    urllib.request.urlretrieve(url, checkpoint_path)
                    print("[InteractiveSAMEngine] Checkpoint download completed.")
                except Exception as e:
                    print(f"[InteractiveSAMEngine] Checkpoint download failed: {e}")
                    # Try local checkpoints directory fallback
                    local_dir = os.path.join(os.getcwd(), "checkpoints")
                    os.makedirs(local_dir, exist_ok=True)
                    checkpoint_path = os.path.join(local_dir, ckpt_name)
                    if not os.path.exists(checkpoint_path):
                        print(f"[InteractiveSAMEngine] Attempting download to local fallback: {checkpoint_path}...")
                        urllib.request.urlretrieve(url, checkpoint_path)
                        print("[InteractiveSAMEngine] Checkpoint local fallback download completed.")

            try:
                # 3. Setup Hydra config dir explicitly
                import sam2
                import hydra
                from hydra.core.global_hydra import GlobalHydra
                from sam2.build_sam import build_sam2
                from sam2.sam2_image_predictor import SAM2ImagePredictor

                GlobalHydra.instance().clear()
                sam2_config_dir = os.path.join(os.path.dirname(sam2.__file__), "configs")
                hydra.initialize_config_dir(config_dir=sam2_config_dir, version_base="1.2")

                # Build the SAM2 model using mapped config and checkpoint
                sam2_model = build_sam2(model_cfg, checkpoint_path, device=self.device)
                self._predictor = SAM2ImagePredictor(sam2_model)
                print("[InteractiveSAMEngine] SAM2 predictor loaded successfully.")
            except ImportError:
                print("[InteractiveSAMEngine] sam2 package not found. "
                      "Falling back to segment-anything-2 pip package...")
                try:
                    import segment_anything_2
                    import hydra
                    from hydra.core.global_hydra import GlobalHydra
                    from segment_anything_2.build_sam import build_sam2
                    from segment_anything_2.sam2_image_predictor import SAM2ImagePredictor

                    GlobalHydra.instance().clear()
                    sam2_config_dir = os.path.join(os.path.dirname(segment_anything_2.__file__), "configs")
                    hydra.initialize_config_dir(config_dir=sam2_config_dir, version_base="1.2")

                    sam2_model = build_sam2(model_cfg, checkpoint_path, device=self.device)
                    self._predictor = SAM2ImagePredictor(sam2_model)
                    print("[InteractiveSAMEngine] SAM2 predictor loaded (alt package).")
                except ImportError as e:
                    print(f"[InteractiveSAMEngine] FATAL: Cannot load SAM2: {e}")
                    raise RuntimeError(
                        "SAM2 is required. Install with: pip install sam2 "
                        "or pip install segment-anything-2"
                    ) from e
        return self._predictor

    # ── Encoder Pass (Run ONCE per image) ─────────────────────────────────────

    def predict_encoder(self, image_np: np.ndarray) -> dict:
        """
        Run the SAM2 Image Encoder on the input image.

        This is the expensive pass — run it ONCE per uploaded image and cache
        the returned embedding for subsequent fast decoder calls.

        Args:
            image_np: RGB image as numpy array, shape (H, W, 3), dtype uint8.

        Returns:
            dict with keys:
                - "image_embedding": The encoded feature tensor (on device).
                - "original_size": Tuple (H, W) of the input image.
                - "input_size": Tuple (H, W) after SAM2 internal transforms.
        """
        if image_np.ndim != 3 or image_np.shape[2] != 3:
            raise ValueError(
                f"Expected RGB image (H, W, 3), got shape {image_np.shape}"
            )

        h, w = image_np.shape[:2]
        print(f"[InteractiveSAMEngine] Running encoder on image {w}x{h}...")

        predictor = self._get_predictor()

        # set_image runs the full encoder and stores internal features
        predictor.set_image(image_np)

        # Extract the cached features from the predictor's internal state
        embedding_data = {
            "features": predictor._features,
            "orig_hw": predictor._orig_hw,
            "is_image_set": predictor._is_image_set,
        }

        print(f"[InteractiveSAMEngine] Encoder complete.")
        return embedding_data

    # ── Decoder Pass (Run per interaction — FAST) ─────────────────────────────

    def predict_decoder(
        self,
        image_embedding: dict,
        points: List[Dict],
        image_size: Tuple[int, int],
    ) -> np.ndarray:
        """
        Run the SAM2 Mask Decoder with interactive point prompts.

        This is the lightweight pass — it reuses the cached image embedding
        and only runs the small decoder head. Typical latency: 10–50ms.

        Args:
            image_embedding: The dict returned by predict_encoder().
            points: List of point dicts, each with:
                    - "x": float in [0.0, 1.0] (normalized horizontal position)
                    - "y": float in [0.0, 1.0] (normalized vertical position)
                    - "label": int, 1 = positive (foreground), 0 = negative (background)
            image_size: (H, W) tuple of the original image dimensions.

        Returns:
            np.ndarray: Binary mask (H, W), dtype uint8, where 255 = foreground.
        """
        if not points:
            raise ValueError("At least one point prompt is required.")

        h, w = image_size
        print(f"[InteractiveSAMEngine] Running decoder with {len(points)} point(s)...")

        predictor = self._get_predictor()

        # Restore the cached encoder state into the predictor
        predictor._features = image_embedding["features"]
        predictor._orig_hw = image_embedding["orig_hw"]
        predictor._is_image_set = image_embedding["is_image_set"]

        # ── Map normalized [0.0–1.0] coordinates to pixel space ──────────────
        point_coords = []
        point_labels = []

        for pt in points:
            px_x = pt["x"] * w
            px_y = pt["y"] * h
            label = int(pt["label"])

            # Clamp to valid pixel range
            px_x = max(0.0, min(float(w - 1), px_x))
            px_y = max(0.0, min(float(h - 1), px_y))

            point_coords.append([px_x, px_y])
            point_labels.append(label)

        point_coords_np = np.array(point_coords, dtype=np.float32)
        point_labels_np = np.array(point_labels, dtype=np.int32)

        print(f"[InteractiveSAMEngine] Mapped points (px): {point_coords_np.tolist()}")
        print(f"[InteractiveSAMEngine] Labels: {point_labels_np.tolist()}")

        # ── Run the decoder ──────────────────────────────────────────────────
        masks, scores, logits = predictor.predict(
            point_coords=point_coords_np,
            point_labels=point_labels_np,
            multimask_output=True,
        )

        # Select the mask with the highest confidence score
        best_idx = int(np.argmax(scores))
        best_mask = masks[best_idx]
        best_score = float(scores[best_idx])

        print(f"[InteractiveSAMEngine] Decoder complete. "
              f"Best mask idx={best_idx}, score={best_score:.4f}, "
              f"masks returned={len(masks)}")

        # Convert boolean mask to uint8 binary (0 or 255)
        mask_uint8 = (best_mask > 0).astype(np.uint8) * 255

        # Ensure output matches original image dimensions
        if mask_uint8.shape[0] != h or mask_uint8.shape[1] != w:
            mask_uint8 = cv2.resize(
                mask_uint8, (w, h), interpolation=cv2.INTER_NEAREST
            )

        coverage = np.count_nonzero(mask_uint8) / (h * w) * 100
        print(f"[InteractiveSAMEngine] Mask coverage: {coverage:.2f}%")

        return mask_uint8

    # ── Utility: Generate Preview Overlay ─────────────────────────────────────

    @staticmethod
    def generate_preview_overlay(
        image_np: np.ndarray,
        mask_np: np.ndarray,
        color: Tuple[int, int, int] = (0, 120, 255),
        alpha: float = 0.45,
        outline_thickness: int = 2,
    ) -> np.ndarray:
        """
        Composite a semi-transparent colored overlay onto the image at the mask region.

        Args:
            image_np: Original RGB image (H, W, 3), uint8.
            mask_np: Binary mask (H, W), uint8, 255 = foreground.
            color: RGB tuple for the overlay highlight color.
            alpha: Opacity of the overlay (0.0 = invisible, 1.0 = opaque).
            outline_thickness: Pixel width of the contour outline.

        Returns:
            np.ndarray: RGB image (H, W, 3) with overlay composited.
        """
        overlay = image_np.copy()
        mask_bool = mask_np > 127

        # Apply colored overlay on masked region
        for c in range(3):
            overlay[:, :, c] = np.where(
                mask_bool,
                np.clip(
                    image_np[:, :, c].astype(np.float32) * (1 - alpha)
                    + color[c] * alpha,
                    0, 255,
                ).astype(np.uint8),
                image_np[:, :, c],
            )

        # Draw contour outline for edge clarity
        contours, _ = cv2.findContours(
            mask_np, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        cv2.drawContours(overlay, contours, -1, color, outline_thickness)

        return overlay
