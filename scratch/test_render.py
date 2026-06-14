import sys
import os
import numpy as np
from PIL import Image
import cv2
import hashlib

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))
from ai.pipeline import TextureProjectionEngine, CATEGORY_PARAMS, FLAT_CATEGORIES

class FixedTextureProjectionEngine(TextureProjectionEngine):
    def _tile_texture(
        self,
        fabric_np: np.ndarray,
        mask_roi: np.ndarray,
        full_bbox_w: int,
        p: dict,
        session_id: str = None,
    ) -> np.ndarray:
        h_roi, w_roi = mask_roi.shape[:2]
        fh, fw = fabric_np.shape[:2]

        # Use a more realistic tile size (e.g. 40% of bbox width instead of 30%)
        tile_w = max(120, int(full_bbox_w * max(p["tile_fraction"], 0.40)))
        tile_h = max(120, int(tile_w * fh / fw))  # preserve aspect ratio

        base = cv2.resize(fabric_np, (tile_w, tile_h), interpolation=cv2.INTER_LANCZOS4)

        tile_a = base
        tile_b = tile_a
        tile_c = tile_a
        tile_d = tile_a

        if session_id:
            h_int = int(hashlib.md5(session_id.encode()).hexdigest()[:8], 16)
            off_x = (h_int % tile_w)
            off_y = ((h_int >> 8) % tile_h)
        else:
            off_x = tile_w // 3
            off_y = tile_h // 4

        # Build padded canvas to allow coordinates to stay in bounds
        extra_x = off_x + tile_w * 2
        extra_y = off_y + tile_h * 2
        reps_x = (w_roi + extra_x) // tile_w + 2
        reps_y = (h_roi + extra_y) // tile_h + 2

        canvas = np.zeros((reps_y * tile_h, reps_x * tile_w, 3), dtype=np.float32)
        for r in range(reps_y):
            for c in range(reps_x):
                y0, x0 = r * tile_h, c * tile_w
                canvas[y0:y0 + tile_h, x0:x0 + tile_w] = tile_a.astype(np.float32)

        canvas_crop = canvas[off_y:off_y + h_roi, off_x:off_x + w_roi]
        if canvas_crop.shape[0] < h_roi or canvas_crop.shape[1] < w_roi:
            pad = np.zeros((h_roi, w_roi, 3), dtype=np.float32)
            ch = min(canvas_crop.shape[0], h_roi)
            cw = min(canvas_crop.shape[1], w_roi)
            pad[:ch, :cw] = canvas_crop[:ch, :cw]
            canvas_crop = pad

        # Reduce seam blur to a very thin strip (2px) to prevent blurring the pattern details
        seam_blur_px = 2
        seam_mask = np.ones((h_roi, w_roi), dtype=np.float32)
        for c in range(reps_x + 1):
            sx = c * tile_w - off_x
            if 0 <= sx < w_roi:
                x_lo = max(0, sx - seam_blur_px)
                x_hi = min(w_roi, sx + seam_blur_px)
                seam_mask[:, x_lo:x_hi] = 0.0
        for r in range(reps_y + 1):
            sy = r * tile_h - off_y
            if 0 <= sy < h_roi:
                y_lo = max(0, sy - seam_blur_px)
                y_hi = min(h_roi, sy + seam_blur_px)
                seam_mask[y_lo:y_hi, :] = 0.0

        blur_r = 5
        blurred_canvas = cv2.GaussianBlur(canvas_crop, (blur_r, blur_r), 1.0)
        seam_mask_3 = seam_mask[:, :, np.newaxis]
        canvas_crop = canvas_crop * seam_mask_3 + blurred_canvas * (1.0 - seam_mask_3)

        return np.clip(canvas_crop, 0, 255).astype(np.uint8)

    def _perspective_map(
        self,
        tiled_roi: np.ndarray,
        mask_roi: np.ndarray,
        product_category: str,
    ) -> np.ndarray:
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

        # Create padded tiled_roi
        # Since tiled_roi is built dynamically, we can just pad it using border replication of the pattern
        tiled_padded = cv2.copyMakeBorder(tiled_roi, pad_h, pad_h, pad_w, pad_w, cv2.BORDER_WRAP)

        y_indices = np.arange(H_roi, dtype=np.float32)
        v = np.clip(
            (y_indices - y_min_mask) / (y_max_mask - y_min_mask + 1e-5),
            0.0, 1.0
        )
        s = (1.0 - f) + f * v  # scale factor per row

        grid_x, _ = np.meshgrid(np.arange(W_roi, dtype=np.float32), y_indices)
        
        # Shift coordinate mapping to account for padding
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

    def _luminance_warp(
        self,
        fabric_roi: np.ndarray,
        wrinkles_map: np.ndarray,
        mask_roi: np.ndarray,
        warp_strength: float = 4.0,
    ) -> np.ndarray:
        h_roi, w_roi = wrinkles_map.shape[:2]

        grad_x = cv2.Sobel(wrinkles_map, cv2.CV_32F, 1, 0, ksize=5)
        grad_y = cv2.Sobel(wrinkles_map, cv2.CV_32F, 0, 1, ksize=5)

        mask_norm = (mask_roi > 127).astype(np.float32)
        grad_x *= mask_norm
        grad_y *= mask_norm

        grad_mag = np.sqrt(grad_x ** 2 + grad_y ** 2)
        
        # Normalization to prevent shredding/tearing
        max_mag = grad_mag.max()
        if max_mag > 0.01:
            grad_x_norm = grad_x / max_mag
            grad_y_norm = grad_y / max_mag
        else:
            grad_x_norm = grad_x
            grad_y_norm = grad_y

        masked_px = mask_norm > 0
        mean_grad = np.mean(grad_mag[masked_px]) if np.count_nonzero(masked_px) > 0 else 0.0

        if mean_grad < 0.01:  # perfectly flat surface
            return fabric_roi

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

def main():
    room_path = "../backend/uploads/e1324d7aa4aa.png"
    fabric_path = "../backend/assets/fabrics/floral.jpg"
    
    room_np = np.array(Image.open(room_path).convert("RGB"))
    fabric_np = np.array(Image.open(fabric_path).convert("RGB"))
    
    h, w = room_np.shape[:2]
    mask_np = np.zeros((h, w), dtype=np.uint8)
    mask_np[h//3:2*h//3, w//3:2*w//3] = 255
    
    ys, xs = np.where(mask_np > 127)
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
    
    p = CATEGORY_PARAMS["bedsheets"]
    engine = FixedTextureProjectionEngine()
    
    tiled_roi = engine._tile_texture(fabric_np, mask_roi, full_bbox_w, p, "test_session")
    Image.fromarray(tiled_roi).save("fixed_tiled.png")
    
    perspective_roi = engine._perspective_map(tiled_roi, mask_roi, "bedsheets")
    Image.fromarray(perspective_roi).save("fixed_perspective.png")
    
    gray = cv2.cvtColor(room_roi, cv2.COLOR_RGB2GRAY).astype(np.float32)
    wrinkle_r = max(5, int(max(full_bbox_w, full_bbox_h) * 0.025) | 1)
    low_pass = cv2.GaussianBlur(gray, (wrinkle_r, wrinkle_r), 0)
    wrinkles_map = gray - low_pass
    smooth_r = max(3, (wrinkle_r // 2) | 1)
    wrinkles_map = cv2.GaussianBlur(wrinkles_map, (smooth_r, smooth_r), 0)
    
    warped_roi = engine._luminance_warp(perspective_roi, wrinkles_map, mask_roi, warp_strength=p["displacement_scale"])
    Image.fromarray(warped_roi).save("fixed_warped.png")
    
    # Run rest of the engine to get final composite
    # Note: engine.render calls internal self._tile_texture, etc. Since we subclassed, it will use our fixed methods!
    result = engine.render(room_np, mask_np, fabric_np, "bedsheets", "test_session")
    Image.fromarray(result).save("fixed_result.png")
    print("Saved all fixed images!")

if __name__ == "__main__":
    main()
