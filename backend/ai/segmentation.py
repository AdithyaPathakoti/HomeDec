#!/usr/bin/env python3
"""
VastraSegmenter – Production-Grade Comforter Segmentation Module
===============================================================
Exposes the VastraSegmenter class wrapping the verified LangSAM models
and comforter-isolation computer vision pipeline.
"""

import os
import cv2
import torch
import numpy as np
from PIL import Image

class VastraSegmenter:
    """
    VastraSegmenter isolates the target comforter/bedsheet blanket from a room image
    using LangSAM (Grounding DINO + SAM) and applies robust morphological operations
    to produce a high-fidelity, hole-free binary mask.
    """
    def __init__(self, device: str = None):
        """
        Initializes the VastraSegmenter.
        If device is not specified, it will automatically detect CUDA/CPU.
        """
        if device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        else:
            self.device = device
            
        self._model = None
        print(f"[VastraSegmenter] Initialized on device: {self.device}")

    def _get_model(self):
        """Lazy load the LangSAM model to keep startup fast."""
        if self._model is None:
            print(f"[VastraSegmenter] Lazy-loading LangSAM on {self.device}...")
            try:
                from lang_sam import LangSAM
                self._model = LangSAM(device=self.device)
                print("[VastraSegmenter] LangSAM model loaded successfully.")
            except Exception as e:
                print(f"[VastraSegmenter] Error loading LangSAM: {e}")
                raise e
        return self._model

    def generate_comforter_mask(
        self, 
        room_image,
        box_threshold: float = 0.20,
        text_threshold: float = 0.23
    ) -> np.ndarray:
        """
        Accepts a room image (either path string or PIL Image object), runs LangSAM 
        to detect 'the comforter blanket', isolates it, and performs morphological 
        melting and contour filling.
        
        Returns:
            np.ndarray: Grayscale binary mask (uint8) where 255 represents the comforter, 
                        and 0 represents everything else.
        """
        if isinstance(room_image, str):
            if not os.path.exists(room_image):
                raise FileNotFoundError(f"Room image not found at: {room_image}")
            print(f"[VastraSegmenter] Opening room image from: {room_image}")
            image_pil = Image.open(room_image).convert("RGB")
        else:
            image_pil = room_image.convert("RGB")
            
        w, h = image_pil.size
        
        model = self._get_model()
        
        # 1. Natural language prompt for precise multi-label separation
        prompt = "the comforter blanket . the pillows . the floor rug"
        print(f"[VastraSegmenter] Running LangSAM inference (prompt='{prompt}')")
        
        results = model.predict(
            [image_pil],
            [prompt],
            box_threshold=box_threshold,
            text_threshold=text_threshold
        )
        
        result = results[0]
        masks = result["masks"]
        phrases = result["labels"]
        logits = result["scores"]
        
        if masks is None or len(masks) == 0:
            print(f"[VastraSegmenter] Warning: No objects matching the prompt were detected.")
            return np.zeros((h, w), dtype=np.uint8)

        # Convert PyTorch tensor to NumPy array
        if hasattr(masks, "cpu"):
            masks_np = masks.cpu().numpy()
        else:
            masks_np = np.array(masks)
            
        print(f"[VastraSegmenter] Detected {len(masks_np)} instance(s) matching prompt.")
        
        # 2. Extract ONLY the binary mask corresponding to "the comforter blanket"
        selected_indices = []
        for idx, (phrase, logit) in enumerate(zip(phrases, logits)):
            phrase_lower = phrase.lower()
            print(f"  - Instance #{idx+1}: '{phrase}' (Confidence: {logit:.3f})")
            if "comforter" in phrase_lower or "blanket" in phrase_lower:
                selected_indices.append(idx)
                
        if len(selected_indices) == 0:
            print("[VastraSegmenter] Warning: 'the comforter blanket' was not found in predictions.")
            return np.zeros((h, w), dtype=np.uint8)
            
        print(f"[VastraSegmenter] Isolating {len(selected_indices)} comforter instance(s)...")
        if len(masks_np.shape) == 3:
            masks_np_filtered = masks_np[selected_indices]
        else:
            masks_np_filtered = masks_np

        # Combine selected comforter masks via logical OR
        if len(masks_np_filtered.shape) == 3:
            combined_mask_bool = np.any(masks_np_filtered, axis=0)
            mask_np = combined_mask_bool.astype(np.uint8) * 255
        else:
            mask_np = (masks_np_filtered > 0).astype(np.uint8) * 255

        # 3. Apply morphological closing with a 45x45 rectangular kernel to melt textures/gaps
        print("[VastraSegmenter] Melting fabric textures and shadow canyons via 45x45 Close...")
        melt_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (45, 45))
        fused_mask = cv2.morphologyEx(mask_np, cv2.MORPH_CLOSE, melt_kernel)

        # 4. Extract outer boundary contours
        print("[VastraSegmenter] Tracing outer boundary envelope via cv2.RETR_EXTERNAL...")
        contours, _ = cv2.findContours(fused_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # 5. Draw filled contours on clean canvas to guarantee 100% solid, hole-free mask
        filled_mask = np.zeros_like(mask_np)
        cv2.drawContours(filled_mask, contours, -1, 255, cv2.FILLED)

        # 6. Apply standard 5x5 Gaussian Blur to smoothly polish edges
        print("[VastraSegmenter] Smoothing edges with 5x5 Gaussian blur...")
        smoothed_mask = cv2.GaussianBlur(filled_mask, (5, 5), 0)

        # Re-threshold to get clean binary output after blur
        _, final_mask = cv2.threshold(smoothed_mask, 127, 255, cv2.THRESH_BINARY)

        return final_mask
