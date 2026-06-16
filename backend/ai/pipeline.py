"""
TextureProjectionEngine - Photorealistic Fabric Texture Projection
=====================================================================

9-Stage Photorealism Pipeline (v4 - Maximum Realism)
------------------------------------------------------
  Stage 1  Seam-free Tiling        — mirror-flip + random offset tiling, zero seam artifacts
  Stage 2  Perspective Warp        — row-wise compression for flat surfaces (bedsheets, rugs)
  Stage 3  Macro Shading Map       — HEAVILY blurred luminance → pure macro fold/shadow map
  Stage 4  Specular Extraction     — isolate highlight spikes for natural "sheen"
  Stage 5  Ambient Occlusion       — fold-valley darkening for depth
  Stage 6  Fold-following Warp     — subtle geometry bend along surface wrinkles
  Stage 7  LAB Relight             — L from shading; A/B from fabric + room color tint
  Stage 8  Poisson Seamless Clone  — use OpenCV seamless clone at mask boundary
  Stage 9  Thin-edge Composite     — 5 px alpha feather at boundary (no colour bleeding)

Design Goals:
  - ZERO visible tiling grid — seam-free using offset + mirror tiling
  - Fabric design at 100% fidelity (H+S fully preserved)
  - Only the L channel of LAB is modulated by real scene shading
  - Shading map uses macro blur only (no pattern bleed-through)
  - Poisson blending at boundary for natural color integration
  - Category-specific parameter profiles
"""

import cv2
import numpy as np
from PIL import Image
from typing import Optional
import hashlib


# ── Category-specific parameter profiles ─────────────────────────────────────
FLAT_CATEGORIES = {"bedsheets", "carpets", "rugs", "rug"}

CATEGORY_PARAMS = {
    "bedsheets": dict(
        wrinkle_weight=0.06,
        displacement_scale=4.0,
        ao_strength=0.20,
        color_temp_blend=0.10,
        shadow_clamp_lo=0.42,
        shadow_clamp_hi=1.28,
        edge_feather_px=5,
        tile_fraction=0.85,   # Increased from 0.30 to 0.85 to make fabric patterns look large and premium on the bed
        macro_blur_frac=0.14, # blur radius = 14% of bbox width for fold extraction
        specular_strength=0.07,
    ),
    "curtains": dict(
        wrinkle_weight=0.10,
        displacement_scale=6.0,
        ao_strength=0.15,
        color_temp_blend=0.12,
        shadow_clamp_lo=0.35,
        shadow_clamp_hi=1.35,
        edge_feather_px=5,
        tile_fraction=0.65,   # Increased from 0.40 to 0.65
        macro_blur_frac=0.10,
        specular_strength=0.12,
    ),
    "sofa_covers": dict(
        wrinkle_weight=0.05,
        displacement_scale=3.5,
        ao_strength=0.18,
        color_temp_blend=0.08,
        shadow_clamp_lo=0.45,
        shadow_clamp_hi=1.25,
        edge_feather_px=5,
        tile_fraction=0.70,   # Increased from 0.25 to 0.70
        macro_blur_frac=0.12,
        specular_strength=0.05,
    ),
    "pillows": dict(
        wrinkle_weight=0.04,
        displacement_scale=2.5,
        ao_strength=0.12,
        color_temp_blend=0.06,
        shadow_clamp_lo=0.50,
        shadow_clamp_hi=1.20,
        edge_feather_px=4,
        tile_fraction=0.85,   # Increased from 0.50 to 0.85
        macro_blur_frac=0.18,
        specular_strength=0.06,
    ),
    "carpets": dict(
        wrinkle_weight=0.03,
        displacement_scale=2.0,
        ao_strength=0.22,
        color_temp_blend=0.08,
        shadow_clamp_lo=0.50,
        shadow_clamp_hi=1.18,
        edge_feather_px=5,
        tile_fraction=0.75,   # Increased from 0.20 to 0.75
        macro_blur_frac=0.16,
        specular_strength=0.02,
    ),
    "rugs": dict(
        wrinkle_weight=0.03,
        displacement_scale=2.0,
        ao_strength=0.22,
        color_temp_blend=0.08,
        shadow_clamp_lo=0.50,
        shadow_clamp_hi=1.18,
        edge_feather_px=5,
        tile_fraction=0.75,   # Increased from 0.20 to 0.75
        macro_blur_frac=0.16,
        specular_strength=0.02,
    ),
    # default fallback
    "_default": dict(
        wrinkle_weight=0.05,
        displacement_scale=3.5,
        ao_strength=0.17,
        color_temp_blend=0.09,
        shadow_clamp_lo=0.42,
        shadow_clamp_hi=1.28,
        edge_feather_px=5,
        tile_fraction=0.70,   # Increased from 0.30 to 0.70
        macro_blur_frac=0.13,
        specular_strength=0.06,
    ),
}


class TextureProjectionEngine:
    """
    Photorealistic fabric texture projection engine (v4 — Maximum Realism).

    Preserves the exact fabric design (Hue + Saturation are 100% from the
    fabric). Only the L channel of LAB is modulated by the room's real
    macro-fold shading map. A subtle room color-temperature tint is applied
    to A/B channels for natural white-balance integration.
    """

    def __init__(self, device: Optional[str] = None):
        print("[TextureProjectionEngine] Initialized (v4 - Maximum Realism mode).")

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
        tile_scale: float = 1.0,
        rotation: float = 0.0,
        offset_x: float = 0.0,
        offset_y: float = 0.0,
        depth_map: Optional[np.ndarray] = None,
    ) -> np.ndarray:
        """
        Full photorealistic texture projection pipeline.

        Args:
            room_np:          Original room image (H, W, 3), dtype uint8, RGB.
            mask_np:          Binary mask (H, W), dtype uint8, 255 = target region.
            fabric_np:        Fabric texture swatch (Hf, Wf, 3), dtype uint8, RGB.
            product_category: Product type string (e.g. "bedsheets", "curtains").
            session_id:       Optional string for deterministic transforms.

        Returns:
            np.ndarray: Composited result image (H, W, 3), dtype uint8, RGB.
        """
        import time
        h, w = room_np.shape[:2]
        cat = product_category.lower().strip()
        p = CATEGORY_PARAMS.get(cat, CATEGORY_PARAMS["_default"])

        print(
            f"[TextureProjectionEngine v4] render() — "
            f"room={w}x{h}, category='{cat}', "
            f"fabric={fabric_np.shape[1]}x{fabric_np.shape[0]}"
        )

        # Guard: empty mask
        if mask_np.max() == 0:
            print("[TextureProjectionEngine] WARNING: Empty mask. Returning original.")
            return room_np.copy()

        t_start = time.perf_counter()

        # ── ROI bounding box ──────────────────────────────────────────────────
        ys, xs = np.where(mask_np > 127)
        if len(xs) == 0:
            return room_np.copy()

        y_min, y_max = int(ys.min()), int(ys.max())
        x_min, x_max = int(xs.min()), int(xs.max())
        full_bbox_h = y_max - y_min
        full_bbox_w = x_max - x_min

        margin = 32
        y_min_m = max(0, y_min - margin)
        y_max_m = min(h, y_max + margin)
        x_min_m = max(0, x_min - margin)
        x_max_m = min(w, x_max + margin)

        room_roi = room_np[y_min_m:y_max_m, x_min_m:x_max_m]
        mask_roi = mask_np[y_min_m:y_max_m, x_min_m:x_max_m]
        depth_roi = depth_map[y_min_m:y_max_m, x_min_m:x_max_m] if depth_map is not None else None
        h_roi, w_roi = room_roi.shape[:2]
        mask_bool = mask_roi > 127

        # Degenerate fallback
        if h_roi < 8 or w_roi < 8 or full_bbox_w < 8:
            alpha = (mask_np > 127).astype(np.float32)[:, :, np.newaxis]
            tiled = self._tile_texture(
                fabric_np, mask_np, full_bbox_w, p, session_id,
                tile_scale=tile_scale, rotation=rotation, offset_x=offset_x, offset_y=offset_y,
                depth_roi=depth_map
            )
            return np.clip(
                tiled.astype(np.float32) * alpha + room_np.astype(np.float32) * (1 - alpha),
                0, 255
            ).astype(np.uint8)

        # ── STAGE 1: Seam-free fabric tiling ─────────────────────────────────
        tiled_roi = self._tile_texture(
            fabric_np=fabric_np,
            mask_roi=mask_roi,
            full_bbox_w=full_bbox_w,
            p=p,
            session_id=session_id,
            tile_scale=tile_scale,
            rotation=rotation,
            offset_x=offset_x,
            offset_y=offset_y,
            depth_roi=depth_roi,
        )

        # ── STAGE 2: Perspective warp (flat categories only) ──────────────────
        if cat in FLAT_CATEGORIES:
            perspective_roi = self._perspective_map(tiled_roi, mask_roi, cat)
        else:
            perspective_roi = tiled_roi

        # ── STAGE 3: Macro Shading Map (HEAVILY blurred — no pattern bleed) ──
        gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY).astype(np.float32)

        # Macro (room-wide): very large blur — eliminates ALL pattern detail
        # Only the large-scale gradient (real folds, shadows, highlights) remains.
        macro_r = max(21, int(max(full_bbox_w, full_bbox_h) * p["macro_blur_frac"]) | 1)
        macro_map = cv2.GaussianBlur(gray, (macro_r, macro_r), macro_r / 3.0)

        # Meso (fold-level): medium blur for fold structure detail
        meso_r = max(11, int(max(full_bbox_w, full_bbox_h) * 0.04) | 1)
        meso_map = cv2.GaussianBlur(gray, (meso_r, meso_r), meso_r / 3.0)

        # Combined: 70% macro + 30% meso (bias toward clean macro to prevent bleed)
        combined_map = 0.70 * macro_map + 0.30 * meso_map

        # Wrinkle high-frequency: edge-aware structure for fold warp
        wrinkle_r = max(5, int(max(full_bbox_w, full_bbox_h) * 0.025) | 1)
        low_pass = cv2.GaussianBlur(gray, (wrinkle_r, wrinkle_r), 0)
        wrinkles_map = gray - low_pass
        smooth_r = max(3, (wrinkle_r // 2) | 1)
        wrinkles_map = cv2.GaussianBlur(wrinkles_map, (smooth_r, smooth_r), 0)

        # ── STAGE 4: Specular Highlight Extraction ───────────────────────────
        # Identify bright specular highlights from the original scene
        mean_g = float(np.mean(gray[mask_bool])) if np.any(mask_bool) else 128.0
        std_g  = float(np.std(gray[mask_bool]))  if np.any(mask_bool) else 30.0
        # Specular = pixels brighter than mean + 1.5*std
        specular_thresh = min(240.0, mean_g + 1.5 * std_g)
        specular_map = np.clip((gray - specular_thresh) / (255.0 - specular_thresh + 1e-5), 0.0, 1.0)
        specular_map = np.where(mask_bool, specular_map, 0.0)
        # Smooth specular map slightly
        spec_r = max(3, (meso_r // 3) | 1)
        specular_map = cv2.GaussianBlur(specular_map.astype(np.float32), (spec_r, spec_r), 0)

        # ── STAGE 5: Ambient Occlusion ────────────────────────────────────────
        ao_r = max(9, int(max(full_bbox_w, full_bbox_h) * 0.07) | 1)
        local_mean = cv2.GaussianBlur(macro_map, (ao_r, ao_r), 0)
        mean_local = float(np.mean(local_mean[mask_bool])) if np.any(mask_bool) else 128.0
        mean_local = max(mean_local, 20.0)
        ao_map = np.clip(1.0 - (local_mean / mean_local), 0.0, 1.0)
        ao_map = np.where(mask_bool, ao_map, 0.0)

        # ── STAGE 6: Fold-following Warp ──────────────────────────────────────
        # Removed simple gradient-based displacement (Sobel-based fold warp Stage 6)
        # and replaced with depth-aware UV warp in Stage 1.
        warped_roi = perspective_roi

        # ── STAGE 7: LAB Relight ──────────────────────────────────────────────
        mean_light = float(np.mean(combined_map[mask_bool])) if np.any(mask_bool) else 128.0
        mean_light = max(mean_light, 1.0)

        # Relative lighting ratio normalized around 1.0
        rel_light = combined_map / mean_light
        rel_light = np.clip(rel_light, p["shadow_clamp_lo"], p["shadow_clamp_hi"])

        # Wrinkle modulation on L (subtle bump)
        wrinkles_norm = np.clip(wrinkles_map / 25.0, -1.0, 1.0)
        mask_norm = mask_bool.astype(np.float32)
        wrinkle_factor = 1.0 + p["wrinkle_weight"] * wrinkles_norm * mask_norm

        # Convert warped fabric to LAB
        fabric_lab = cv2.cvtColor(warped_roi, cv2.COLOR_RGB2LAB).astype(np.float32)
        L_fabric = fabric_lab[:, :, 0]  # [0, 255]

        # Apply combined shading + wrinkle bump to L channel only
        L_relit = L_fabric * rel_light * wrinkle_factor

        # Apply ambient occlusion: darken fold valleys
        L_relit = L_relit * (1.0 - p["ao_strength"] * ao_map)

        # Apply specular highlights: brighten specular peaks
        # Scale by fabric's own L to keep relative brightness
        L_relit = L_relit + p["specular_strength"] * specular_map * (255.0 - L_relit)

        fabric_lab[:, :, 0] = np.clip(L_relit, 0.0, 255.0)

        # ── Color Temperature Matching (A/B channels — very subtle) ──────────
        # Sample room mean A/B from OUTSIDE the mask to match lighting white balance
        if p["color_temp_blend"] > 0.0:
            room_lab = cv2.cvtColor(room_roi, cv2.COLOR_RGB2LAB).astype(np.float32)
            outside = ~mask_bool
            if np.any(outside):
                mean_A_room = float(np.mean(room_lab[:, :, 1][outside]))
                mean_B_room = float(np.mean(room_lab[:, :, 2][outside]))
                shift_A = (mean_A_room - 128.0) * p["color_temp_blend"]
                shift_B = (mean_B_room - 128.0) * p["color_temp_blend"]
                fabric_lab[:, :, 1] = np.clip(fabric_lab[:, :, 1] + shift_A, 0, 255)
                fabric_lab[:, :, 2] = np.clip(fabric_lab[:, :, 2] + shift_B, 0, 255)

        # Convert back to RGB
        relit_roi = cv2.cvtColor(fabric_lab.astype(np.uint8), cv2.COLOR_LAB2RGB)

        # ── STAGE 8: Poisson Seamless Clone at boundary ───────────────────────
        # Note: Poisson blending shifts colors significantly, which alters the exact design colors.
        # We bypass it by default to keep 100% design fidelity, relying on the thin-edge composite for seamless boundary.
        if p.get("use_poisson", False):
            blended_roi = self._poisson_blend(room_roi, relit_roi, mask_roi)
        else:
            blended_roi = relit_roi

        # ── STAGE 8.5: Detail Sharpening ──────────────────────────────────────
        # Enhance print clarity and texture definition of the fabric pattern
        # using an unsharp mask filter on the RGB relit fabric
        gaussian_blur = cv2.GaussianBlur(blended_roi, (0, 0), 1.5)
        sharpened = cv2.addWeighted(blended_roi, 1.25, gaussian_blur, -0.25, 0)
        blended_roi = np.clip(sharpened, 0, 255).astype(np.uint8)

        # ── STAGE 9: Thin-edge Composite ─────────────────────────────────────
        composite_roi = self._composite(room_roi, blended_roi, mask_roi, p["edge_feather_px"])

        # ── Paste ROI back into full canvas ──────────────────────────────────
        result = room_np.copy()
        result[y_min_m:y_max_m, x_min_m:x_max_m] = composite_roi

        t_total = time.perf_counter() - t_start
        print(f"[TextureProjectionEngine v4] Done in {t_total*1000:.1f}ms")
        return result

    # ═════════════════════════════════════════════════════════════════════════
    #  STAGE 1 — Seam-free Texture Tiling
    # ═════════════════════════════════════════════════════════════════════════

    def _tile_texture(
        self,
        fabric_np: np.ndarray,
        mask_roi: np.ndarray,
        full_bbox_w: int,
        p: dict,
        session_id: Optional[str] = None,
        tile_scale: float = 1.0,
        rotation: float = 0.0,
        offset_x: float = 0.0,
        offset_y: float = 0.0,
        depth_roi: Optional[np.ndarray] = None,
    ) -> np.ndarray:
        """
        Tile the fabric pattern across the ROI with customizable scale, rotation, and offset.
        Uses OpenCV remap with BORDER_WRAP for seamless, high-performance tiling.
        Additionally performs depth-aware local scaling and geometry-aware UV warp.
        """
        h_roi, w_roi = mask_roi.shape[:2]
        fh, fw = fabric_np.shape[:2]

        # Base tile size (proportional to bounding box width)
        base_tile_w = max(150.0, float(full_bbox_w * max(p["tile_fraction"], 0.60)))

        # Output coordinate grids
        grid_y, grid_x = np.meshgrid(np.arange(h_roi, dtype=np.float32), np.arange(w_roi, dtype=np.float32), indexing='ij')

        # Center coordinates to rotate around the center of the ROI
        x_ctr = w_roi / 2.0
        y_ctr = h_roi / 2.0
        dx = grid_x - x_ctr
        dy = grid_y - y_ctr

        if depth_roi is not None:
            depth_roi_f = depth_roi.astype(np.float32)
            # 1. Adaptive Scale: farther areas (lower depth) have smaller pattern sizes (denser tiling);
            # closer areas (larger depth) have larger pattern sizes.
            scale_local = tile_scale * (0.5 + 0.8 * depth_roi_f)

            # 2. Depth-Aware UV Warp: compute gradients of the depth map to warp the mapping coordinates before rotation/scaling.
            grad_depth_x = cv2.Sobel(depth_roi_f, cv2.CV_32F, 1, 0, ksize=5)
            grad_depth_y = cv2.Sobel(depth_roi_f, cv2.CV_32F, 0, 1, ksize=5)

            grad_mag = np.sqrt(grad_depth_x ** 2 + grad_depth_y ** 2)
            max_mag = grad_mag.max()
            if max_mag > 1e-4:
                grad_dx_norm = grad_depth_x / max_mag
                grad_dy_norm = grad_depth_y / max_mag
            else:
                grad_dx_norm = grad_depth_x
                grad_dy_norm = grad_depth_y

            warp_strength = float(p.get("displacement_scale", 4.0))
            max_disp = 15.0
            disp_x = np.clip(grad_dx_norm * warp_strength * 3.0, -max_disp, max_disp)
            disp_y = np.clip(grad_dy_norm * warp_strength * 3.0, -max_disp, max_disp)

            dx = dx + disp_x
            dy = dy + disp_y
        else:
            scale_local = float(tile_scale)

        # Compute local tile width and height per pixel!
        tile_w_local = np.maximum(50.0, base_tile_w * scale_local)
        tile_h_local = np.maximum(50.0, tile_w_local * (fh / fw))

        # Scale mapping
        scale_x = fw / tile_w_local
        scale_y = fh / tile_h_local

        # Apply deterministic session offset if present
        sess_off_x = 0.0
        sess_off_y = 0.0
        if session_id:
            h_int = int(hashlib.md5(session_id.encode()).hexdigest()[:8], 16)
            sess_off_x = (h_int % 100) / 100.0
            sess_off_y = ((h_int >> 8) % 100) / 100.0

        # Total translation in normalized fabric coordinates
        total_off_x = offset_x + sess_off_x
        total_off_y = offset_y + sess_off_y

        # Convert rotation from degrees to radians
        theta = np.radians(rotation)
        cos_t = np.cos(theta)
        sin_t = np.sin(theta)

        map_xf = (dx * cos_t + dy * sin_t) * scale_x + (total_off_x * fw)
        map_yf = (-dx * sin_t + dy * cos_t) * scale_y + (total_off_y * fh)

        # Remap using Lanczos interpolation and WRAP border mode
        tiled = cv2.remap(
            fabric_np, map_xf.astype(np.float32), map_yf.astype(np.float32),
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_WRAP,
        )
        return tiled

    # ═════════════════════════════════════════════════════════════════════════
    #  STAGE 2 — Planar Perspective Mapping (flat categories)
    # ═════════════════════════════════════════════════════════════════════════

    def _perspective_map(
        self,
        tiled_roi: np.ndarray,
        mask_roi: np.ndarray,
        product_category: str,
    ) -> np.ndarray:
        """
        Row-wise horizontal compression for flat objects (rugs, bedsheets).
        Upper rows appear narrower to simulate receding perspective.
        Factor 0.18 gives a gentle, realistic recede without distortion.
        """
        if product_category.lower() not in FLAT_CATEGORIES:
            return tiled_roi

        H_roi, W_roi = mask_roi.shape[:2]
        ys, xs = np.where(mask_roi > 127)
        if len(xs) == 0:
            return tiled_roi

        y_min_mask, y_max_mask = int(ys.min()), int(ys.max())
        x_min_mask, x_max_mask = int(xs.min()), int(xs.max())

        if (y_max_mask - y_min_mask) < 2 or (x_max_mask - x_min_mask) < 2:
            return tiled_roi

        x_center = float(xs.mean())
        f = 0.18  # perspective strength

        # Pad canvas to prevent replication/smearing at borders
        pad_w = int(W_roi * f / (1.0 - f)) + 32
        pad_h = int(H_roi * f / (1.0 - f)) + 32

        # Create padded tiled_roi using BORDER_WRAP to dynamically wrap pattern
        tiled_padded = cv2.copyMakeBorder(tiled_roi, pad_h, pad_h, pad_w, pad_w, cv2.BORDER_WRAP)

        y_indices = np.arange(H_roi, dtype=np.float32)
        v = np.clip(
            (y_indices - y_min_mask) / (y_max_mask - y_min_mask + 1e-5),
            0.0, 1.0
        )
        s = (1.0 - f) + f * v  # scale factor per row: 0.82→1.0 top→bottom

        grid_x, _ = np.meshgrid(np.arange(W_roi, dtype=np.float32), y_indices)
        
        # Shift coordinate mapping by pad_w and pad_h to map into the padded tiled region
        map_x = (x_center + (grid_x - x_center) / s[:, np.newaxis] + pad_w).astype(np.float32)

        y_ref = float(y_max_mask)
        step_y = 1.0 / (s + 1e-5)
        cum_step = np.cumsum(step_y)
        y_ref_idx = min(int(y_ref), H_roi - 1)
        map_y_1d = y_ref + cum_step - cum_step[y_ref_idx] + pad_h
        map_y = np.broadcast_to(
            map_y_1d[:, np.newaxis], (H_roi, W_roi)
        ).copy().astype(np.float32)

        return cv2.remap(
            tiled_padded, map_x, map_y,
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )

    # ═════════════════════════════════════════════════════════════════════════
    #  STAGE 6 — Fold-following Luminance Warp
    # ═════════════════════════════════════════════════════════════════════════

    def _luminance_warp(
        self,
        fabric_roi: np.ndarray,
        wrinkles_map: np.ndarray,
        mask_roi: np.ndarray,
        warp_strength: float = 4.0,
    ) -> np.ndarray:
        """
        Geometrically bend the fabric pattern to follow surface fold lines.
        Uses gradient of the high-frequency wrinkle map as a displacement field.
        Displacement is clamped to ±8 px to avoid tearing artifacts.
        Applied only inside the mask — outside pixels are not displaced.
        """
        h_roi, w_roi = wrinkles_map.shape[:2]

        grad_x = cv2.Sobel(wrinkles_map, cv2.CV_32F, 1, 0, ksize=5)
        grad_y = cv2.Sobel(wrinkles_map, cv2.CV_32F, 0, 1, ksize=5)

        mask_norm = (mask_roi > 127).astype(np.float32)
        grad_x *= mask_norm
        grad_y *= mask_norm

        grad_mag = np.sqrt(grad_x ** 2 + grad_y ** 2)
        
        # Normalize the displacement gradients by maximum magnitude to prevent pixel tearing/noise
        max_mag = grad_mag.max()
        if max_mag > 0.01:
            grad_x_norm = grad_x / max_mag
            grad_y_norm = grad_y / max_mag
        else:
            grad_x_norm = grad_x
            grad_y_norm = grad_y

        masked_px = mask_norm > 0
        mean_grad = np.mean(grad_mag[masked_px]) if np.count_nonzero(masked_px) > 0 else 0.0

        if mean_grad < 0.01:  # perfectly flat surface — skip warp
            return fabric_roi

        # Identity remap grids
        map_x = np.arange(w_roi, dtype=np.float32)[np.newaxis, :].repeat(h_roi, axis=0)
        map_y = np.arange(h_roi, dtype=np.float32)[:, np.newaxis].repeat(w_roi, axis=1)

        max_disp = 8.0
        disp_x = np.clip(grad_x_norm * warp_strength, -max_disp, max_disp)
        disp_y = np.clip(grad_y_norm * warp_strength, -max_disp, max_disp)

        map_x = (map_x + disp_x).astype(np.float32)
        map_y = (map_y + disp_y).astype(np.float32)

        return cv2.remap(
            fabric_roi, map_x, map_y,
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )

    # ═════════════════════════════════════════════════════════════════════════
    #  STAGE 8 — Poisson Seamless Clone (boundary integration)
    # ═════════════════════════════════════════════════════════════════════════

    def _poisson_blend(
        self,
        room_roi: np.ndarray,
        fabric_roi: np.ndarray,
        mask_roi: np.ndarray,
    ) -> np.ndarray:
        """
        Use OpenCV seamlessClone (MIXED_CLONE) to naturally integrate the
        relit fabric into the room at the mask boundary.

        This eliminates hard color-temperature jumps at the edge, making the
        fabric appear to be physically present in the scene rather than pasted.

        Falls back gracefully if OpenCV seamless clone fails (e.g. degenerate mask).
        """
        try:
            # seamlessClone requires BGR
            room_bgr = cv2.cvtColor(room_roi, cv2.COLOR_RGB2BGR)
            fabric_bgr = cv2.cvtColor(fabric_roi, cv2.COLOR_RGB2BGR)

            # Mask for seamlessClone: must be 8-bit single channel, white = src
            mask_255 = (mask_roi > 127).astype(np.uint8) * 255

            # Center of the mask bounding box for seamlessClone center param
            ys, xs = np.where(mask_255 > 0)
            if len(xs) == 0:
                return fabric_roi

            cx = int(xs.mean())
            cy = int(ys.mean())
            center = (cx, cy)

            # MIXED_CLONE: preserves fabric texture gradient + adapts color to room
            result_bgr = cv2.seamlessClone(
                fabric_bgr, room_bgr, mask_255, center,
                cv2.MIXED_CLONE
            )
            result_rgb = cv2.cvtColor(result_bgr, cv2.COLOR_BGR2RGB)

            # Only use Poisson result INSIDE the mask; rest stays as room
            mask_f = (mask_roi > 127).astype(np.float32)[:, :, np.newaxis]
            blended = result_rgb.astype(np.float32) * mask_f + \
                      room_roi.astype(np.float32) * (1.0 - mask_f)
            return np.clip(blended, 0, 255).astype(np.uint8)

        except Exception as e:
            print(f"[TextureProjectionEngine] Poisson blend failed ({e}), using direct composite.")
            return fabric_roi

    # ═════════════════════════════════════════════════════════════════════════
    #  STAGE 9 — Thin-edge Composite
    # ═════════════════════════════════════════════════════════════════════════

    def _composite(
        self,
        room_roi: np.ndarray,
        fabric_roi: np.ndarray,
        mask_roi: np.ndarray,
        edge_feather_px: int = 5,
    ) -> np.ndarray:
        """
        Composites the relit fabric onto the room ROI.

        Strategy:
          - Core mask area (strictly inside): 100% fabric — exact design, no bleed.
          - Boundary (±edge_feather_px): Very thin alpha-only Gaussian fade.
            This is applied to the MASK alpha only, NOT to the RGB channels,
            so no room colour bleeds into the fabric interior.
          - Outside: 100% original room, completely untouched.
        """
        mask_float = (mask_roi > 127).astype(np.float32)

        if edge_feather_px > 0:
            ksize = max(3, (edge_feather_px * 2 + 1) | 1)
            alpha = cv2.GaussianBlur(mask_float, (ksize, ksize), edge_feather_px / 2.0)
            alpha = np.clip(alpha, 0.0, 1.0)
        else:
            alpha = mask_float

        alpha_3ch = alpha[:, :, np.newaxis]
        result = (
            fabric_roi.astype(np.float32) * alpha_3ch
            + room_roi.astype(np.float32) * (1.0 - alpha_3ch)
        )
        return np.clip(result, 0, 255).astype(np.uint8)
