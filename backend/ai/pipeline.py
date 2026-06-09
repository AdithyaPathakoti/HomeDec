"""
TextureProjectionEngine – Photorealistic Fabric Texture Projection
=====================================================================

Rewritten from scratch using OpenCV and NumPy to map replacement fabrics
naturally onto segmented regions WITHOUT looking like flat stickers.

Pipeline Steps:
  1. Texture Tiling — tile the fabric pattern across mask bounding dimensions.
  2. Planar Perspective Mapping — spatial transform for flat categories
     (Rug, Bedsheet) so pattern lines shrink as they recede into the background.
  3. Luminance Displacement Warping — shift/warp pattern lines over wrinkles,
     curves, and organic folds using the original image's intensity gradients.
  4. Lighting Blend Layer — preserve shadows, folds, and highlights using a
     Soft Light blend mode with the original luminance.
"""

import cv2
import numpy as np
from PIL import Image
from typing import Optional, Tuple


# ── Categories that receive planar perspective correction ─────────────────────
FLAT_CATEGORIES = {"bedsheets", "carpets", "rugs", "rug"}


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

    def __init__(self):
        print("[TextureProjectionEngine] Initialized.")

    # ═════════════════════════════════════════════════════════════════════════
    #  PUBLIC API
    # ═════════════════════════════════════════════════════════════════════════

    def render(
        self,
        room_np: np.ndarray,
        mask_np: np.ndarray,
        fabric_np: np.ndarray,
        product_category: str,
    ) -> np.ndarray:
        """
        Full photorealistic texture projection pipeline.

        Args:
            room_np: Original room image (H, W, 3), dtype uint8, RGB.
            mask_np: Binary mask (H, W), dtype uint8, 255 = target region.
            fabric_np: Fabric texture swatch (Hf, Wf, 3), dtype uint8, RGB.
            product_category: Product type string (e.g. "bedsheets", "curtains").

        Returns:
            np.ndarray: Composited result image (H, W, 3), dtype uint8, RGB.
        """
        h, w = room_np.shape[:2]
        print(
            f"[TextureProjectionEngine] render() – "
            f"room={w}x{h}, category='{product_category}', "
            f"fabric={fabric_np.shape[1]}x{fabric_np.shape[0]}"
        )

        if mask_np.max() == 0:
            print("[TextureProjectionEngine] WARNING: Empty mask. Returning original.")
            return room_np.copy()

        # ── Step 1: Texture Tiling ───────────────────────────────────────────
        tiled = self._tile_texture(fabric_np, mask_np)
        print(f"[TextureProjectionEngine] Step 1 – Tiled texture: {tiled.shape}")

        # ── Step 2: Planar Perspective Mapping ───────────────────────────────
        if product_category.lower() in FLAT_CATEGORIES:
            tiled = self._perspective_map(tiled, mask_np)
            print("[TextureProjectionEngine] Step 2 – Perspective mapping applied.")
        else:
            print(
                f"[TextureProjectionEngine] Step 2 – Skipped perspective "
                f"(category '{product_category}' is not flat)."
            )

        # ── Step 3: Luminance Displacement Warping ───────────────────────────
        tiled = self._luminance_warp(tiled, room_np, mask_np)
        print("[TextureProjectionEngine] Step 3 – Luminance displacement warping applied.")

        # ── Step 4: Lighting Blend Layer ─────────────────────────────────────
        lit_fabric = self._lighting_blend(tiled, room_np, mask_np)
        print("[TextureProjectionEngine] Step 4 – Lighting blend applied.")

        # ── Final Composite ──────────────────────────────────────────────────
        result = self._composite(room_np, lit_fabric, mask_np)
        print("[TextureProjectionEngine] Render complete.")
        return result

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 1 — Texture Tiling
    # ═════════════════════════════════════════════════════════════════════════

    def _tile_texture(
        self, fabric_np: np.ndarray, mask_np: np.ndarray
    ) -> np.ndarray:
        """
        Tile the input fabric pattern dynamically across the bounding
        dimensions of the active mask.

        The tile size is set proportionally to the mask's bounding box width
        (roughly 1/3 of bbox width) to produce 2–3 natural repeats across
        the object.
        """
        h, w = mask_np.shape[:2]
        fh, fw = fabric_np.shape[:2]

        # Compute mask bounding box
        ys, xs = np.where(mask_np > 127)
        if len(xs) == 0:
            return np.zeros((h, w, 3), dtype=np.uint8)

        bbox_w = int(xs.max() - xs.min())
        bbox_h = int(ys.max() - ys.min())

        # Tile reference: ~1/3 of bbox width → 2-3 repeats across the object
        tile_w = max(64, bbox_w // 3)
        tile_h = max(64, int(tile_w * (fh / fw)))  # Preserve aspect ratio

        # Resize the fabric swatch to tile dimensions
        tile = cv2.resize(
            fabric_np, (tile_w, tile_h), interpolation=cv2.INTER_LANCZOS4
        )

        # Tile across the full image canvas
        reps_x = (w // tile_w) + 2
        reps_y = (h // tile_h) + 2
        tiled = np.tile(tile, (reps_y, reps_x, 1))

        # Crop to exact image dimensions
        tiled = tiled[:h, :w, :]
        return tiled

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 2 — Planar Perspective Mapping
    # ═════════════════════════════════════════════════════════════════════════

    def _perspective_map(
        self, tiled_np: np.ndarray, mask_np: np.ndarray
    ) -> np.ndarray:
        """
        For flat categories (Rug, Bedsheet), apply a spatial transformation
        so pattern lines shrink as they recede into the room's background
        perspective.

        Uses a homography transform: the top edge of the mask bounding box
        is compressed inward (simulating distance), while the bottom edge
        stays at full width.
        """
        h, w = mask_np.shape[:2]
        ys, xs = np.where(mask_np > 127)
        if len(xs) == 0:
            return tiled_np

        x_min, x_max = int(xs.min()), int(xs.max())
        y_min, y_max = int(ys.min()), int(ys.max())

        bbox_w = x_max - x_min
        bbox_h = y_max - y_min
        if bbox_w < 10 or bbox_h < 10:
            return tiled_np

        # Source corners: full rectangular tile region
        src_pts = np.float32([
            [x_min, y_min],             # top-left
            [x_max, y_min],             # top-right
            [x_max, y_max],             # bottom-right
            [x_min, y_max],             # bottom-left
        ])

        # Destination corners: top edge compressed inward by ~15%
        # to simulate perspective foreshortening
        inset = int(bbox_w * 0.15)
        dst_pts = np.float32([
            [x_min + inset, y_min],     # top-left (shifted right)
            [x_max - inset, y_min],     # top-right (shifted left)
            [x_max, y_max],             # bottom-right (unchanged)
            [x_min, y_max],             # bottom-left (unchanged)
        ])

        # Compute and apply the perspective transform
        M = cv2.getPerspectiveTransform(src_pts, dst_pts)
        warped = cv2.warpPerspective(
            tiled_np, M, (w, h),
            flags=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return warped

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 3 — Luminance Displacement Warping
    # ═════════════════════════════════════════════════════════════════════════

    def _luminance_warp(
        self,
        tiled_np: np.ndarray,
        room_np: np.ndarray,
        mask_np: np.ndarray,
        displacement_scale: float = 3.0,
    ) -> np.ndarray:
        """
        Compute local pixel intensity gradients from the original image
        under the mask area. Use this gradient map to shift and warp the
        pattern lines of the fabric over wrinkles, physical curves, and
        organic folds.

        The displacement magnitude is scaled to ~2-5 pixels for subtle
        realism — enough to follow surface topology without distortion.
        """
        h, w = room_np.shape[:2]

        # Extract grayscale luminance from the original room image
        gray = cv2.cvtColor(room_np, cv2.COLOR_RGB2GRAY).astype(np.float32)

        # Smooth slightly to avoid noise-driven displacements
        gray_smooth = cv2.GaussianBlur(gray, (5, 5), 1.0)

        # Compute intensity gradients (Sobel)
        grad_x = cv2.Sobel(gray_smooth, cv2.CV_32F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(gray_smooth, cv2.CV_32F, 0, 1, ksize=3)

        # Normalize gradients to [-1, 1] range
        grad_mag = np.sqrt(grad_x**2 + grad_y**2)
        max_mag = grad_mag.max()
        if max_mag > 0:
            grad_x = grad_x / max_mag
            grad_y = grad_y / max_mag

        # Build displacement maps for cv2.remap
        # Base identity map
        map_x = np.arange(w, dtype=np.float32)[np.newaxis, :].repeat(h, axis=0)
        map_y = np.arange(h, dtype=np.float32)[:, np.newaxis].repeat(w, axis=1)

        # Apply displacement only within the mask region
        mask_float = (mask_np > 127).astype(np.float32)
        map_x = map_x + grad_x * displacement_scale * mask_float
        map_y = map_y + grad_y * displacement_scale * mask_float

        # Remap the tiled texture using the displacement field
        warped = cv2.remap(
            tiled_np, map_x, map_y,
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return warped

    # ═════════════════════════════════════════════════════════════════════════
    #  STEP 4 — Lighting Blend Layer (Soft Light)
    # ═════════════════════════════════════════════════════════════════════════

    def _lighting_blend(
        self,
        fabric_np: np.ndarray,
        room_np: np.ndarray,
        mask_np: np.ndarray,
    ) -> np.ndarray:
        """
        Preserve shadows, folds, and highlights by mapping the luminance
        details of the original image back over the newly textured surface
        using a Soft Light blend mode.

        Soft Light formula:
          if overlay < 0.5:
            result = 2 * base * overlay
          else:
            result = 1 - 2 * (1 - base) * (1 - overlay)

        Where:
          base = textured fabric (normalized to [0, 1])
          overlay = original room luminance (normalized to [0, 1])
        """
        h, w = room_np.shape[:2]

        # Extract luminance from original room image (under mask)
        room_gray = cv2.cvtColor(room_np, cv2.COLOR_RGB2GRAY).astype(np.float32)

        # Apply guided blur to remove the original pattern's high-frequency
        # detail while preserving fold/shadow edges
        room_smooth = cv2.GaussianBlur(room_gray, (31, 31), 0)

        # Compute relative luminance (normalized to region inside mask)
        mask_bool = mask_np > 127
        masked_luma = room_smooth[mask_bool]
        if len(masked_luma) > 0:
            ref_brightness = float(np.percentile(masked_luma, 75))
            ref_brightness = np.clip(ref_brightness, 50.0, 230.0)
        else:
            ref_brightness = 180.0

        # Normalize overlay to [0, 1]
        overlay = room_smooth / (ref_brightness * 2.0)
        overlay = np.clip(overlay, 0.0, 1.0)

        # Normalize fabric base to [0, 1]
        base = fabric_np.astype(np.float32) / 255.0

        # Expand overlay to 3 channels
        overlay_3ch = overlay[:, :, np.newaxis]

        # Soft Light blend
        result = np.where(
            overlay_3ch < 0.5,
            2.0 * base * overlay_3ch,
            1.0 - 2.0 * (1.0 - base) * (1.0 - overlay_3ch),
        )

        # Scale back to [0, 255]
        result = np.clip(result * 255.0, 0, 255).astype(np.uint8)

        return result

    # ═════════════════════════════════════════════════════════════════════════
    #  Final Composite
    # ═════════════════════════════════════════════════════════════════════════

    def _composite(
        self,
        room_np: np.ndarray,
        fabric_np: np.ndarray,
        mask_np: np.ndarray,
    ) -> np.ndarray:
        """
        Composite the textured fabric onto the room image using the mask.

        Uses a feathered alpha blend at the mask boundary for smooth edges,
        then hard-copies the interior for full opacity.
        """
        h, w = room_np.shape[:2]

        # Create a feathered alpha channel from the mask
        mask_float = mask_np.astype(np.float32) / 255.0

        # Gentle Gaussian feather at the boundary (3px radius)
        alpha = cv2.GaussianBlur(mask_float, (7, 7), 1.5)
        alpha_3ch = alpha[:, :, np.newaxis]

        # Alpha blend: fabric where mask is white, room where mask is black
        result = (
            fabric_np.astype(np.float32) * alpha_3ch
            + room_np.astype(np.float32) * (1.0 - alpha_3ch)
        )
        return np.clip(result, 0, 255).astype(np.uint8)
