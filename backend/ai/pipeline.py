"""
TextureProjectionEngine - Photorealistic Fabric Texture Projection
=====================================================================

Rewritten from scratch using OpenCV and NumPy to map replacement fabrics
naturally onto segmented regions WITHOUT looking like flat stickers.

Pipeline Steps:
  1. Texture Tiling — tile the fabric pattern across mask bounding dimensions.
  2. Planar Perspective Mapping — spatial transform for flat categories
     (Rug, Bedsheet) so pattern lines shrink as they recede into the background.
  3. Depth/Luminance Displacement Warping — shift/warp pattern lines over wrinkles,
     curves, and organic folds using depth maps or intensity gradients.
  4. Lighting Blend Layer — preserve shadows, folds, and highlights using a
     relative lightness shading map.
"""

import cv2
import numpy as np
from PIL import Image
from typing import Optional, Tuple
import hashlib

try:
    from .depth import DepthEstimator
except ImportError:
    DepthEstimator = None


# ── Categories that receive planar perspective correction ─────────────────────
FLAT_CATEGORIES = {"bedsheets", "carpets", "rugs", "rug"}


def order_points(pts: np.ndarray) -> np.ndarray:
    """
    Order points in: top-left, top-right, bottom-right, bottom-left order.
    """
    xSorted = pts[np.argsort(pts[:, 0]), :]
    leftMost = xSorted[:2, :]
    rightMost = xSorted[2:, :]

    leftMost = leftMost[np.argsort(leftMost[:, 1]), :]
    (tl, bl) = leftMost

    rightMost = rightMost[np.argsort(rightMost[:, 1]), :]
    (tr, br) = rightMost

    return np.array([tl, tr, br, bl], dtype="float32")


class TextureProjectionEngine:
    """
    Photorealistic texture projection engine.

    Given a room image, a binary segmentation mask, and a fabric texture,
    this engine maps the fabric onto the masked region with perspective,
    wrinkle warping, and lighting preservation for a natural result.

    Usage:
        engine = TextureProjectionEngine()
        result = engine.render(room_np, mask_np, fabric_np, "bedsheets")
    """

    def __init__(
        self,
        device: Optional[str] = None,
        feather_ksize: int = 15,
        feather_sigma: float = 4.0,
        wrinkle_weight: float = 0.15,
        displacement_scale: float = 5.0,
        enable_guided_feather: bool = True,
    ):
        """
        Initialize the TextureProjectionEngine.

        Args:
            device: Hardware device ('cuda' or 'cpu'). Auto-detected if None.
            feather_ksize: Gaussian blur kernel size for mask feathering.
            feather_sigma: Gaussian blur standard deviation for mask feathering.
            wrinkle_weight: Blending factor for reintroducing fine wrinkles.
            displacement_scale: Scaling factor for displacement warping.
            enable_guided_feather: Whether to use guided filter for edge-preserving feathering.
        """
        self.feather_ksize = feather_ksize
        self.feather_sigma = feather_sigma
        self.wrinkle_weight = wrinkle_weight
        self.displacement_scale = displacement_scale
        self.enable_guided_feather = enable_guided_feather

        self.depth_estimator = None
        self.use_depth = False
        if DepthEstimator is not None:
            self.depth_estimator = DepthEstimator(device=device)
            # Try loading the model; if it succeeds, set use_depth=True
            self.use_depth = self.depth_estimator.load_model()
            
        print(f"[TextureProjectionEngine] Initialized. use_depth={self.use_depth} | feather_ksize={feather_ksize} | wrinkle_weight={wrinkle_weight}")

    # ═════════════════════════════════════════════════════════════════════════
    #  PUBLIC API
    # ═════════════════════════════════════════════════════════════════════════

    def render(
        self,
        room_np: np.ndarray,
        mask_np: np.ndarray,
        fabric_np: np.ndarray,
        product_category: str,
        session_id: Optional[str] = None,
    ) -> np.ndarray:
        """
        Full photorealistic texture projection pipeline.

        Args:
            room_np: Original room image (H, W, 3), dtype uint8, RGB.
            mask_np: Binary mask (H, W), dtype uint8, 255 = target region.
            fabric_np: Fabric texture swatch (Hf, Wf, 3), dtype uint8, RGB.
            product_category: Product type string (e.g. "bedsheets", "curtains").
            session_id: Optional string for deterministic random transformations.

        Returns:
            np.ndarray: Composited result image (H, W, 3), dtype uint8, RGB.
        """
        import time
        h, w = room_np.shape[:2]
        print(
            f"[TextureProjectionEngine] render() - "
            f"room={w}x{h}, category='{product_category}', "
            f"fabric={fabric_np.shape[1]}x{fabric_np.shape[0]}, "
            f"session_id={session_id}"
        )

        # Guard: empty mask check
        if mask_np.max() == 0:
            print("[TextureProjectionEngine] WARNING: Empty mask. Returning original room.")
            return room_np.copy()

        t_start = time.perf_counter()

        # ROI Extraction & Bounding Box Optimization
        ys, xs = np.where(mask_np > 127)
        if len(xs) == 0:
            return room_np.copy()

        y_min, y_max = int(ys.min()), int(ys.max())
        x_min, x_max = int(xs.min()), int(xs.max())
        full_bbox_w = x_max - x_min

        # Add a 20px margin and clamp to image dimensions to prevent IndexError
        margin = 20
        y_min_m = max(0, y_min - margin)
        y_max_m = min(h, y_max + margin)
        x_min_m = max(0, x_min - margin)
        x_max_m = min(w, x_max + margin)

        # Crop inputs to local ROI coordinate space
        room_roi = room_np[y_min_m:y_max_m, x_min_m:x_max_m]
        mask_roi = mask_np[y_min_m:y_max_m, x_min_m:x_max_m]

        h_roi, w_roi = room_roi.shape[:2]

        # Degenerate Fallback: If ROI dimensions are too small, fallback to standard linear blend
        if h_roi < 8 or w_roi < 8:
            print("[TextureProjectionEngine] WARNING: Tiny ROI. Returning standard linear blend.")
            mask_float = mask_np.astype(np.float32) / 255.0
            alpha_3ch = mask_float[:, :, np.newaxis]
            tiled = self._tile_texture(fabric_np, mask_np, full_bbox_w)
            result = tiled.astype(np.float32) * alpha_3ch + room_np.astype(np.float32) * (1.0 - alpha_3ch)
            return np.clip(result, 0, 255).astype(np.uint8)

        # ── Step 1: Texture Tiling (ROI Local) ───────────────────────────────
        t0 = time.perf_counter()
        tiled_roi = self._tile_texture(fabric_np, mask_roi, full_bbox_w)
        t_tiling = time.perf_counter() - t0

        # ── Step 2: Planar Perspective Mapping (ROI Local) ───────────────────
        t0 = time.perf_counter()
        if product_category.lower() in FLAT_CATEGORIES:
            perspective_roi = self._perspective_map(tiled_roi, mask_roi, product_category)
            has_persp = True
        else:
            perspective_roi = tiled_roi
            has_persp = False
        t_persp = time.perf_counter() - t0

        # ── Step 3: Physical Geometry Warping (ROI Local) ────────────────────
        t0 = time.perf_counter()
        warped_roi = self._luminance_warp(perspective_roi, room_roi, mask_roi)
        t_warp = time.perf_counter() - t0

        # ── Step 4 & 5: Lighting Blend Layer (ROI Local) ─────────────────────
        t0 = time.perf_counter()
        blended_roi = self._lighting_blend(warped_roi, room_roi, mask_roi)
        
        # ── Step 4.2: Pillow Shadows Preservation (ROI Local) ────────────────
        blended_roi = self._preserve_pillow_shadows(blended_roi, room_roi, mask_roi)
        
        # ── Step 4.5: Wrinkle Preservation (ROI Local) ───────────────────────
        blended_roi = self._preserve_wrinkles(blended_roi, room_roi, mask_roi)
        
        # ── Step 4.7: Local Variation (ROI Local) ────────────────────────────
        blended_roi = self._add_local_variation(blended_roi, mask_roi)
        t_blend = time.perf_counter() - t0

        # ── Step 6: ROI feathered compositing ────────────────────────────────
        t0 = time.perf_counter()
        composite_roi = self._composite(room_roi, blended_roi, mask_roi)
        t_comp = time.perf_counter() - t0

        # ── Step 7: Paste composited ROI back into the full canvas ───────────
        result = room_np.copy()
        result[y_min_m:y_max_m, x_min_m:x_max_m] = composite_roi

        t_total = time.perf_counter() - t_start
        print(
            f"[TextureProjectionEngine] ROI Bounding Box: [{y_min_m}:{y_max_m}, {x_min_m}:{x_max_m}] ({w_roi}x{h_roi})\n"
            f"[TextureProjectionEngine] Profiling Summary:\n"
            f"  - Tiling:       {t_tiling*1000:.2f} ms\n"
            f"  - Perspective:  {t_persp*1000:.2f} ms (applied: {has_persp})\n"
            f"  - Sobel Warp:   {t_warp*1000:.2f} ms\n"
            f"  - Light Blend:  {t_blend*1000:.2f} ms\n"
            f"  - Composite:    {t_comp*1000:.2f} ms\n"
            f"  - Total Budget: {t_total*1000:.2f} ms / 1000.00 ms"
        )
        return result

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 1 — Texture Tiling
    # ═════════════════════════════════════════════════════════════════════════

    def _tile_texture(
        self, fabric_np: np.ndarray, mask_roi: np.ndarray, full_bbox_w: int
    ) -> np.ndarray:
        """
        Tile the input fabric pattern dynamically across the bounding
        dimensions of the active local mask.
        """
        h_roi, w_roi = mask_roi.shape[:2]
        fh, fw = fabric_np.shape[:2]

        # Compute tile width based on the original full bounding box width
        # to ensure pattern scale is consistent across zoom levels.
        tile_w = max(64, full_bbox_w // 3)
        tile_h = max(64, int(tile_w * (fh / fw)))  # Preserve aspect ratio

        # Resize fabric swatch to tile dimensions
        tile = cv2.resize(
            fabric_np, (tile_w, tile_h), interpolation=cv2.INTER_LANCZOS4
        )

        # Tile across the local ROI canvas dimensions
        reps_x = (w_roi // tile_w) + 2
        reps_y = (h_roi // tile_h) + 2
        tiled = np.tile(tile, (reps_y, reps_x, 1))

        # Crop to exact local ROI dimensions
        tiled = tiled[:h_roi, :w_roi, :]
        return tiled

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 2 — Planar Perspective Mapping (Vectorized Row-Wise Compression)
    # ═════════════════════════════════════════════════════════════════════════

    def _perspective_map(
        self, tiled_roi: np.ndarray, mask_roi: np.ndarray, product_category: str
    ) -> np.ndarray:
        """
        For flat categories (Rug, Bedsheet), apply a continuous, row-wise
        vertical perspective compression inside the ROI.
        """
        if product_category.lower() not in FLAT_CATEGORIES:
            return tiled_roi

        H_roi, W_roi = mask_roi.shape[:2]
        ys, xs = np.where(mask_roi > 127)
        if len(xs) == 0:
            return tiled_roi

        y_min_mask, y_max_mask = int(ys.min()), int(ys.max())
        x_min_mask, x_max_mask = int(xs.min()), int(xs.max())

        # Guard against degenerate thin masks
        if (y_max_mask - y_min_mask) < 2 or (x_max_mask - x_min_mask) < 2:
            return tiled_roi

        x_center = float(xs.mean())
        f = 0.18  # configurable perspective scaling factor (~15% to 20%)

        # 1. Compute scaling factor s(y) for each row index y in the ROI
        y_indices = np.arange(H_roi, dtype=np.float32)
        v = np.clip((y_indices - y_min_mask) / (y_max_mask - y_min_mask + 1e-5), 0.0, 1.0)
        s = (1.0 - f) + f * v  # s ranges from (1-f) at the top of the mask to 1.0 at the bottom

        # 2. Build local coordinate meshgrids
        grid_x, grid_y = np.meshgrid(np.arange(W_roi, dtype=np.float32), np.arange(H_roi, dtype=np.float32))

        # 3. Horizontal map_x: scales coordinate spacing outward from x_center
        # map_x(x, y) = x_center + (x - x_center) / s(y)
        map_x = x_center + (grid_x - x_center) / s[:, np.newaxis]

        # 4. Vertical map_y: integrated from the bottom reference row (y_ref) to prevent vertical drift
        y_ref = float(y_max_mask)
        step_y = 1.0 / (s + 1e-5)
        cum_step = np.cumsum(step_y)
        map_y_1d = y_ref + cum_step - cum_step[int(y_ref)]

        # Broadcast map_y_1d across width
        map_y = np.broadcast_to(map_y_1d[:, np.newaxis], (H_roi, W_roi)).copy()

        # Explicitly cast to float32 for OpenCV's C++ remap execution loop
        map_x = map_x.astype(np.float32)
        map_y = map_y.astype(np.float32)

        # Apply transformation with Lanczos4 filter for visual quality preservation
        warped = cv2.remap(
            tiled_roi, map_x, map_y,
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return warped

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 3 — Luminance Displacement Warping (Mask-Isolated Gradients)
    # ═════════════════════════════════════════════════════════════════════════

    def _luminance_warp(
        self,
        fabric_roi: np.ndarray,
        room_roi: np.ndarray,
        mask_roi: np.ndarray,
        warp_strength: float = 8.0,
    ) -> np.ndarray:
        """
        Apply physical geometry warping over folds and wrinkles using spatial
        derivatives of the original room luminance, constrained to the mask area.
        """
        h_roi, w_roi = room_roi.shape[:2]

        # Extract grayscale luminance
        gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY)

        # Bilateral + Gaussian smoothing to strip existing patterns while preserving shadow borders
        gray_bilateral = cv2.bilateralFilter(gray, d=9, sigmaColor=75, sigmaSpace=75).astype(np.float32)
        gray_smooth = cv2.GaussianBlur(gray_bilateral, (5, 5), 1.0)

        # Compute raw spatial Sobel gradients
        grad_x = cv2.Sobel(gray_smooth, cv2.CV_32F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(gray_smooth, cv2.CV_32F, 0, 1, ksize=3)

        # Strict Mask Masking: zero out spatial gradients outside segmentation boundary
        mask_norm = (mask_roi > 127).astype(np.float32)
        grad_x = grad_x * mask_norm
        grad_y = grad_y * mask_norm

        # Compute gradient magnitude
        grad_mag = np.sqrt(grad_x**2 + grad_y**2)

        # Bypass displacement warping if the mean gradient magnitude inside the mask drops below threshold (0.02)
        masked_pixels = mask_norm > 0
        if np.count_nonzero(masked_pixels) > 0:
            mean_grad_mag = np.mean(grad_mag[masked_pixels])
        else:
            mean_grad_mag = 0.0

        GRADIENT_MAGNITUDE_THRESHOLD = 0.02
        if mean_grad_mag < GRADIENT_MAGNITUDE_THRESHOLD:
            print(f"[TextureProjectionEngine] Mean gradient magnitude ({mean_grad_mag:.4f}) below threshold. Bypassing displacement warp.")
            return fabric_roi

        # Globally normalize gradients to [0, 1] for stable warp scaling
        max_mag = grad_mag.max()
        if max_mag > 0:
            grad_x_norm = grad_x / (max_mag + 1e-5)
            grad_y_norm = grad_y / (max_mag + 1e-5)
        else:
            grad_x_norm = grad_x
            grad_y_norm = grad_y

        # Build identity maps
        map_x = np.arange(w_roi, dtype=np.float32)[np.newaxis, :].repeat(h_roi, axis=0)
        map_y = np.arange(h_roi, dtype=np.float32)[:, np.newaxis].repeat(w_roi, axis=1)

        # Clip shift maps strictly to maximum movement radius of +-8.0 pixels to prevent pixel tearing
        disp_x = np.clip(grad_x_norm * warp_strength, -8.0, 8.0)
        disp_y = np.clip(grad_y_norm * warp_strength, -8.0, 8.0)

        map_x = (map_x + disp_x).astype(np.float32)
        map_y = (map_y + disp_y).astype(np.float32)

        # Remap using Lanczos4 interpolation
        warped = cv2.remap(
            fabric_roi, map_x, map_y,
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return warped

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 4 & 5 — Lighting Blend Layer (Soft-Light + Specular Guard + Laplacian)
    # ═════════════════════════════════════════════════════════════════════════

    def _lighting_blend(
        self,
        warped_roi: np.ndarray,
        room_roi: np.ndarray,
        mask_roi: np.ndarray,
    ) -> np.ndarray:
        """
        Blend original luminance back over the fabric using W3C Soft-Light
        blending, applying CLAHE, Specular Glare Guard, and Laplacian Fold Enhancement.
        """
        h_roi, w_roi = room_roi.shape[:2]

        # Extract original grayscale luma
        room_gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY).astype(np.float32)

        # Extract pattern-stripped luminance layer
        room_smooth = cv2.bilateralFilter(room_gray.astype(np.uint8), d=9, sigmaColor=75, sigmaSpace=75)
        room_smooth = cv2.GaussianBlur(room_smooth, (31, 31), 0).astype(np.float32)

        # Process the pattern-stripped luma using CLAHE
        room_smooth_uint8 = np.clip(room_smooth, 0, 255).astype(np.uint8)
        if room_smooth_uint8.shape[0] >= 8 and room_smooth_uint8.shape[1] >= 8:
            clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
            clahe_luma = clahe.apply(room_smooth_uint8).astype(np.float32)
        else:
            clahe_luma = room_smooth_uint8.astype(np.float32)

        # Specular Glare Guard: soft clamp intensities exceeding 240 on 0-255 scale
        clahe_luma_clamped = np.where(
            clahe_luma > 240.0,
            240.0 + 15.0 * np.tanh((clahe_luma - 240.0) / 15.0),
            clahe_luma
        )

        # Ambient normalization using 75th percentile of mask luma
        mask_bool = mask_roi > 127
        masked_luma = clahe_luma_clamped[mask_bool]
        if len(masked_luma) > 0:
            ref_brightness = float(np.percentile(masked_luma, 75))
            ref_brightness = np.clip(ref_brightness, 50.0, 230.0)
        else:
            ref_brightness = 180.0

        # Normalize blend overlay (B) to [0.0, 1.0] domain
        overlay = clahe_luma_clamped / (2.0 * ref_brightness + 1e-5)
        overlay = np.clip(overlay, 0.0, 1.0)

        # Expand overlay to [H_roi, W_roi, 1] to prevent shape mismatch with fabric float [H_roi, W_roi, 3]
        overlay_3ch = overlay[:, :, np.newaxis]

        # Normalize fabric base (A) to [0.0, 1.0] domain
        base = warped_roi.astype(np.float32) / 255.0

        # Vectorized W3C CSS Compositing Soft-Light Formulation
        g_base = np.where(
            base <= 0.25,
            ((16.0 * base - 12.0) * base + 4.0) * base,
            np.sqrt(np.maximum(base, 0.0))
        )

        blended = np.where(
            overlay_3ch <= 0.5,
            base - (1.0 - 2.0 * overlay_3ch) * base * (1.0 - base),
            base + (2.0 * overlay_3ch - 1.0) * (g_base - base)
        )
        blended = np.clip(blended * 255.0, 0.0, 255.0)

        # ── Step 5: Laplacian-Based Fold Enhancement Overlay ─────────────────
        # Extract crease detail from pattern-stripped luma
        smoothed_lum = cv2.bilateralFilter(room_gray.astype(np.uint8), d=9, sigmaColor=75, sigmaSpace=75)
        smoothed_lum = cv2.GaussianBlur(smoothed_lum, (5, 5), 1.0).astype(np.float32)

        # Laplacian calculation
        laplacian = cv2.Laplacian(smoothed_lum, cv2.CV_32F, ksize=3)

        # Normalize crease details to [0.8, 1.2] range
        contrast_layer = np.clip(1.0 - (laplacian * 0.005), 0.8, 1.2)
        contrast_layer_3ch = contrast_layer[:, :, np.newaxis]

        # Multiply back onto the final blended fabric texture profile
        final_fabric = blended * contrast_layer_3ch
        return np.clip(final_fabric, 0, 255).astype(np.uint8)

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 4.2 — Pillow Shadows Preservation
    # ═════════════════════════════════════════════════════════════════════════

    def _preserve_pillow_shadows(
        self,
        fabric_roi: np.ndarray,
        room_roi: np.ndarray,
        mask_roi: np.ndarray,
    ) -> np.ndarray:
        """
        Extract low-frequency shadows from the original image (e.g. pillow shadows)
        and apply them to the fabric texture.
        """
        mask_bool = mask_roi > 127
        if not np.any(mask_bool):
            return fabric_roi

        # Convert to grayscale and normalize
        gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
        
        # Extract low-frequency shadows using a very large blur kernel
        h_roi, w_roi = room_roi.shape[:2]
        kernel_size = max(51, (min(h_roi, w_roi) // 10) | 1)
        shadow_blur = cv2.GaussianBlur(gray, (kernel_size, kernel_size), 0)
        
        # Find the reference bright area inside the mask
        ref_bright = float(np.percentile(shadow_blur[mask_bool], 90))
        ref_bright = max(ref_bright, 0.1)
        
        # Calculate shadow map (relative to reference bright level)
        shadow_map = shadow_blur / ref_bright
        
        # Clamp to reasonable values so we don't completely black out or brighten
        # Allow shadows to go down to 0.55 (to preserve deep pillow shadows)
        shadow_map = np.clip(shadow_map, 0.55, 1.0)
        
        # Apply only within the mask
        mask_float = mask_bool.astype(np.float32)
        blend_shadow = shadow_map * mask_float + (1.0 - mask_float)
        
        result = fabric_roi.astype(np.float32) * blend_shadow[:, :, np.newaxis]
        return np.clip(result, 0, 255).astype(np.uint8)

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 4.5 — Wrinkle Preservation
    # ═════════════════════════════════════════════════════════════════════════

    def _preserve_wrinkles(
        self,
        lit_fabric_roi: np.ndarray,
        room_roi: np.ndarray,
        mask_roi: np.ndarray,
    ) -> np.ndarray:
        """
        Extract high-frequency wrinkles from the original room image region
        and reintroduce them into the projected fabric texture.
        """
        if self.wrinkle_weight <= 0.0:
            return lit_fabric_roi

        # 1. Convert room image to grayscale
        gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY).astype(np.float32)

        # 2. Gaussian blur to extract low frequencies using a large (31, 31) kernel
        low_freq = cv2.GaussianBlur(gray, (31, 31), 0)

        # 3. High-pass filter to extract fine wrinkles and normalize
        wrinkles = (gray - low_freq) / 255.0

        # 4. Reintroduce wrinkles inside the mask region
        mask_float = (mask_roi > 127).astype(np.float32)
        
        # Apply: fabric *= (1 + 0.12 * wrinkles)
        factor = 1.0 + 0.12 * wrinkles * mask_float

        # Multiply onto the fabric pattern and clamp limits
        result = lit_fabric_roi.astype(np.float32) * factor[:, :, np.newaxis]
        return np.clip(result, 0, 255).astype(np.uint8)

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 4.7 — Local Variation
    # ═════════════════════════════════════════════════════════════════════════

    def _add_local_variation(self, fabric_roi: np.ndarray, mask_roi: np.ndarray) -> np.ndarray:
        """
        Add subtle local texture variation (noise) to make the fabric look less
        computer-generated.
        """
        h_roi, w_roi = fabric_roi.shape[:2]
        
        # Generate random normal noise
        noise = np.random.randn(h_roi, w_roi).astype(np.float32)
        
        # Smooth the noise to get low-frequency variations
        noise_smooth = cv2.GaussianBlur(noise, (15, 15), 0)
        
        # Normalize the noise to range [-1.0, 1.0] roughly
        max_val = np.max(np.abs(noise_smooth))
        if max_val > 0:
            noise_smooth /= max_val
            
        # Apply: fabric *= (0.98 + 0.04 * noise) inside the mask
        mask_float = (mask_roi > 127).astype(np.float32)
        factor = 0.98 + 0.04 * noise_smooth * mask_float
        
        result = fabric_roi.astype(np.float32) * factor[:, :, np.newaxis]
        return np.clip(result, 0, 255).astype(np.uint8)

    # ═════════════════════════════════════════════════════════════════════════
    #  Guided Filter Helper
    # ═════════════════════════════════════════════════════════════════════════

    def _guided_filter(self, I: np.ndarray, p: np.ndarray, r: int, eps: float) -> np.ndarray:
        """
        Guided Filter implementation.
        I: guidance image (grayscale original room image), normalized to [0.0, 1.0]
        p: filtering input image (binary mask), normalized to [0.0, 1.0]
        r: local window radius
        eps: regularization parameter
        """
        mean_I = cv2.boxFilter(I, cv2.CV_32F, (r, r))
        mean_p = cv2.boxFilter(p, cv2.CV_32F, (r, r))
        mean_Ip = cv2.boxFilter(I * p, cv2.CV_32F, (r, r))
        cov_Ip = mean_Ip - mean_I * mean_p

        mean_II = cv2.boxFilter(I * I, cv2.CV_32F, (r, r))
        var_I = mean_II - mean_I * mean_I

        a = cov_Ip / (var_I + eps)
        b = mean_p - a * mean_I

        mean_a = cv2.boxFilter(a, cv2.CV_32F, (r, r))
        mean_b = cv2.boxFilter(b, cv2.CV_32F, (r, r))

        q = mean_a * I + mean_b
        return q

    # ═════════════════════════════════════════════════════════════════════════
    #  Final Composite (ROI Local)
    # ═════════════════════════════════════════════════════════════════════════

    def _composite(
        self,
        room_roi: np.ndarray,
        fabric_roi: np.ndarray,
        mask_roi: np.ndarray,
    ) -> np.ndarray:
        """
        Composite the textured fabric onto the room image using the mask.
        Uses a guided edge-preserving filter combined with configurable Gaussian feathering
        to reduce cut-and-paste artifacts while keeping sharp boundaries where appropriate.
        """
        h_roi, w_roi = room_roi.shape[:2]
        mask_float = mask_roi.astype(np.float32) / 255.0

        if self.enable_guided_feather:
            # Grayscale guidance image normalized to [0.0, 1.0]
            gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255.0
            
            # Local window radius = 8, regularization = 0.02
            alpha = self._guided_filter(gray, mask_float, r=8, eps=0.02)
            alpha = np.clip(alpha, 0.0, 1.0)
            
            # Apply configurable Gaussian blur to the guided mask
            if self.feather_ksize > 0:
                ksize = self.feather_ksize | 1 # Ensure odd
                alpha = cv2.GaussianBlur(alpha, (ksize, ksize), self.feather_sigma)
        else:
            if self.feather_ksize > 0:
                ksize = self.feather_ksize | 1
                alpha = cv2.GaussianBlur(mask_float, (ksize, ksize), self.feather_sigma)
            else:
                alpha = mask_float

        alpha_3ch = alpha[:, :, np.newaxis]
        result = (
            fabric_roi.astype(np.float32) * alpha_3ch
            + room_roi.astype(np.float32) * (1.0 - alpha_3ch)
        )
        return np.clip(result, 0, 255).astype(np.uint8)
