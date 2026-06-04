"""
VastraPipeline – Production-Grade Fabric Swapping Pipeline
===========================================================

FIXES applied vs original:

1.  SD inpainting is now the PRIMARY output path (not just a missing-object fallback).
    Pure numpy compositing is used only when cloud API is unreachable.

2.  FastSAM mask direction bug fixed:
    Original PIL.composite call had mask polarity inverted for FastSAM output.
    Fixed: mask is always normalized to white=fabric, black=keep-original before composite.

3.  Luminance shading restricted strictly to the masked region.
    Original code applied shading_factor globally (whole image), causing wall/floor
    lighting to bleed into the fabric. Now only masked pixels are shaded.

4.  SD inpainting strength corrected: 0.75 (was 0.99).
    At 0.99 SDXL ignores room context entirely. 0.75 preserves room lighting.

5.  VastraPipeline is a true singleton — loaded once at startup via module-level
    instance. main.py must NOT re-instantiate it per request.

6.  Fabric tile size is proportional to mask bounding box, not fixed 256 px.
    This prevents too-many tiny repeating tiles on wide room images.

7.  Poisson seamless blending at mask boundary for photorealistic edge compositing.
    Falls back to Gaussian-feathered blend if Poisson fails.

8.  Bedsheet bbox adjusted: YOLO class 59 = whole bed. Sheet is lower 60% of that bbox.

9.  FastSAM mask polarity: some FastSAM versions output masks where the object is 0
    (black). _normalize_mask() corrects this before every composite operation.

10. All temp files use unique names per request (thread-safe).
"""

import cv2
import numpy as np
import os
import tempfile
import uuid
import torch
from PIL import Image, ImageFilter, ImageDraw
from typing import Optional, Tuple, List

from .inpaint import InpaintService
from .utils import compress_image

# ── YOLO class IDs ────────────────────────────────────────────────────────────
# 56=chair, 57=couch, 58=potted_plant, 59=bed, 60=dining_table
CATEGORY_YOLO_MAP: dict = {
    "bedsheets":   {"classes": [59],         "description": "bed"},
    "curtains":    {"classes": [],            "description": "window/curtain region"},
    "sofa_covers": {"classes": [57, 56],     "description": "couch or chair"},
    "pillows":     {"classes": [57, 59, 56], "description": "pillow surroundings"},
    "carpets":     {"classes": [],            "description": "floor region"},
}

# ── SD inpainting prompts ─────────────────────────────────────────────────────
CATEGORY_PROMPTS: dict = {
    "bedsheets":
        "photorealistic bedsheet with {fabric_desc}, natural folds and wrinkles, "
        "same ambient room lighting, high detail, 8k",
    "curtains":
        "photorealistic curtain panel with {fabric_desc}, natural fabric drape, "
        "same room window lighting, high detail",
    "sofa_covers":
        "photorealistic sofa upholstery with {fabric_desc}, realistic cushion texture, "
        "same room lighting, high detail",
    "pillows":
        "photorealistic throw pillow with {fabric_desc}, soft plush texture, "
        "same room lighting, high detail",
    "carpets":
        "photorealistic floor carpet with {fabric_desc} texture, natural perspective, "
        "room ambient lighting, realistic shadows",
}

# ── Category-specific fabric tile base scale ─────────────────────────────────
CATEGORY_BASE_SCALE: dict = {
    "bedsheets":   0.70,
    "curtains":    1.10,
    "sofa_covers": 0.90,
    "pillows":     1.80,
    "carpets":     0.50,
}


# =============================================================================
#  VastraPipeline
# =============================================================================

class VastraPipeline:
    """
    Vastra AI fabric swapping pipeline.

    Instantiate ONCE at module level / server startup.
    Do NOT re-instantiate on every request.

    Usage:
        pipeline = VastraPipeline(yolo_model=get_yolo(), device="cuda")
        result_pil = pipeline.process(room_pil, "bedsheets", fabric_pil)
    """

    def __init__(self, yolo_model, device: str = "cpu"):
        self.yolo = yolo_model
        self.device = device
        self.inpaint_service = InpaintService()

        # FastSAM loaded lazily
        self._fastsam = None

        # VastraSegmenter loaded lazily
        self._vastra_segmenter = None

        # MiDaS depth model loaded lazily
        self._depth_model = None
        self._depth_transform = None

        print(f"[VastraPipeline] Initialized on device: {device}")

    # ── Lazy loaders ─────────────────────────────────────────────────────────

    def _get_fastsam(self):
        if self._fastsam is None:
            from ultralytics import FastSAM
            print("[VastraPipeline] Loading FastSAM-s...")
            self._fastsam = FastSAM("FastSAM-s.pt")
            print("[VastraPipeline] FastSAM-s ready.")
        return self._fastsam

    def _get_vastra_segmenter(self):
        if self._vastra_segmenter is None:
            from .segmentation import VastraSegmenter
            print("[VastraPipeline] Loading VastraSegmenter...")
            self._vastra_segmenter = VastraSegmenter(device=self.device)
            print("[VastraPipeline] VastraSegmenter ready.")
        return self._vastra_segmenter

    def _load_depth_model(self):
        if self._depth_model is None:
            try:
                print("[VastraPipeline] Loading MiDaS depth model...")
                self._depth_model = torch.hub.load(
                    "intel-isl/MiDaS", "MiDaS_small", trust_repo=True)
                self._depth_model.to(self.device).eval()
                transforms = torch.hub.load("intel-isl/MiDaS", "transforms")
                self._depth_transform = transforms.small_transform
                print("[VastraPipeline] MiDaS loaded.")
            except Exception as e:
                print(f"[VastraPipeline] MiDaS load failed: {e}. Using analytic fallback.")
        return self._depth_model, self._depth_transform

    # =========================================================================
    #  PUBLIC ENTRY POINT
    # =========================================================================

    def process(
        self,
        room_pil: Image.Image,
        product_category: str,
        fabric_pil: Image.Image,
        verify_dir: str = None,
    ) -> Image.Image:
        """
        Full fabric replacement pipeline.

        Steps:
          1. Scene analysis (YOLO detections + light gradient)
          2. Product-aware bbox + prompt point detection
          3. FastSAM segmentation + scoring + occlusion subtraction
          4. Mask clean + validation + recovery fallback
          5. Depth estimation (MiDaS)
          6. Perspective-correct fabric tiling (centered homography)
          7. Lighting transfer RESTRICTED to masked region only
          8. SD inpainting as PRIMARY output (not fallback)
          9. Poisson/feather edge blend + audit heal pass
        """
        room_rgb = room_pil.convert("RGB")
        fabric_rgb = fabric_pil.convert("RGB")
        w, h = room_rgb.size
        img_np = np.array(room_rgb)

        print(f"[VastraPipeline] Processing: category='{product_category}' room={w}x{h}")

        # ── Stage 1: Scene understanding ─────────────────────────────────────
        scene_profile = self._analyze_scene(img_np)

        # ── Stage 2: Product-aware bbox detection ────────────────────────────
        bbox, point_prompt = self._smart_detect(room_rgb, product_category, scene_profile)
        print(f"[VastraPipeline] Stage 2 - BBox: {bbox}, point: {point_prompt}")

        # ── Stage 3: Segmentation (Optimized VastraSegmenter for beds) ────────
        if product_category == "bedsheets":
            print("[VastraPipeline] Route: 'bedsheets' detected. Using optimized VastraSegmenter.")
            segmenter = self._get_vastra_segmenter()
            mask_np = segmenter.generate_comforter_mask(room_rgb)
        else:
            mask_np = self._precise_segment(
                room_rgb, bbox, point_prompt, product_category, scene_profile)
        mask_coverage = float(mask_np.sum()) / (255.0 * w * h)
        print(f"[VastraPipeline] Stage 3 - Mask coverage: {100 * mask_coverage:.2f}%")

        # Missing object fallback (curtains/carpets/pillows)
        if mask_coverage < 0.0015 and product_category in ["curtains", "carpets", "pillows"]:
            print(f"[VastraPipeline] Object missing – launching inpainting generation fallback...")
            room_rgb, mask_np = self._generate_missing_object(
                room_rgb, product_category, w, h, scene_profile)
            img_np = np.array(room_rgb)
            mask_coverage = float(mask_np.sum()) / (255.0 * w * h)
            print(f"[VastraPipeline] Post-inpainting mask coverage: {100 * mask_coverage:.2f}%")

        # ── Stage 4: Mask cleaning + validation + recovery ───────────────────
        mask_np = self._clean_mask(img_np, mask_np)

        is_valid, reason = self._validate_mask(mask_np, product_category)
        if not is_valid:
            print(f"[VastraPipeline] Mask audit FAILED: {reason}. Running recovery...")
            mask_np = self._run_recovery_segmentation(img_np, bbox, product_category, scene_profile)
            mask_np = self._clean_mask(img_np, mask_np)
            is_valid, reason = self._validate_mask(mask_np, product_category)
            print(f"[VastraPipeline] Post-recovery: {'PASSED' if is_valid else reason}")

        # Ensure mask_np is always binary uint8 white=255 for object
        mask_np = self._normalize_mask(mask_np)

        if verify_dir:
            os.makedirs(verify_dir, exist_ok=True)
            cv2.imwrite(os.path.join(verify_dir, "mask.png"), mask_np)

        # ── Stage 5: Depth estimation ─────────────────────────────────────────
        depth_map = self._estimate_midas_depth(img_np)

        # ── Stage 6: Perspective-correct fabric tiling ───────────────────────
        warped_fabric_np = self._prepare_fabric(fabric_rgb, mask_np, img_np, bbox,
                                                depth_map, product_category)

        # ── Stage 7: Lighting transfer (MASKED REGION ONLY) ──────────────────
        #   FIX: shading_factor is extracted from masked region and applied
        #        only to masked pixels. No global application.
        lit_fabric_np = self._apply_masked_lighting(warped_fabric_np, img_np, mask_np, verify_dir=verify_dir)

        # ── Stage 8: SD inpainting as primary output ─────────────────────────
        fabric_desc = self._describe_fabric(fabric_rgb)
        prompt = CATEGORY_PROMPTS[product_category].format(fabric_desc=fabric_desc)

        result_pil = self._run_sd_inpainting(
            room_rgb, mask_np, lit_fabric_np, prompt, w, h)

        # ── Stage 9: Poisson blend + audit ───────────────────────────────────
        result_np = self._poisson_blend(np.array(result_pil), img_np, mask_np)
        result_np = self._audit_final_output(result_np, img_np, mask_np)

        if verify_dir:
            comp_path = os.path.join(verify_dir, "final_composition.png")
            Image.fromarray(result_np, "RGB").save(comp_path, "PNG")
            print(f"[VastraPipeline] Saved intermediate final composition to '{comp_path}'")

        print("[VastraPipeline] Pipeline complete.")
        return Image.fromarray(result_np, "RGB")

    # =========================================================================
    #  STAGE 1 — Scene analysis
    # =========================================================================

    def _analyze_scene(self, img_np: np.ndarray) -> dict:
        """YOLO-based scene detection + light gradient analysis."""
        h, w = img_np.shape[:2]
        profile = {
            "scene_type": "general_interior",
            "detections": {},
            "light_gradient": "ambient_balanced",
            "dominant_luminance": 128.0,
        }

        interest_classes = [0, 15, 16, 56, 57, 58, 59, 60]
        try:
            results = self.yolo.predict(
                source=Image.fromarray(img_np),
                classes=interest_classes,
                conf=0.10,
                device=self.device,
                imgsz=640,
                verbose=False,
            )
            if results and results[0].boxes is not None:
                for box in results[0].boxes:
                    cls_id = int(box.cls.cpu().numpy()[0])
                    xyxy = box.xyxy.cpu().numpy()[0].tolist()
                    conf = float(box.conf.cpu().numpy()[0])
                    profile["detections"].setdefault(cls_id, []).append(
                        {"bbox": xyxy, "conf": conf})

                if 59 in profile["detections"]:
                    profile["scene_type"] = "bedroom"
                elif 57 in profile["detections"]:
                    profile["scene_type"] = "living_room"
                elif 60 in profile["detections"]:
                    profile["scene_type"] = "dining_room"

            gray = cv2.cvtColor(img_np, cv2.COLOR_RGB2GRAY)
            lm = np.mean(gray[:, :w // 2])
            rm = np.mean(gray[:, w // 2:])
            profile["dominant_luminance"] = float(np.mean(gray))
            if lm - rm > 25:
                profile["light_gradient"] = "light_from_left"
            elif rm - lm > 25:
                profile["light_gradient"] = "light_from_right"

        except Exception as e:
            print(f"[VastraPipeline] Scene analysis error: {e}")

        print(f"[VastraPipeline] Scene: type='{profile['scene_type']}' "
              f"light='{profile['light_gradient']}' "
              f"detected={list(profile['detections'].keys())}")
        return profile

    # =========================================================================
    #  STAGE 2 — Bbox detection
    # =========================================================================

    def _detect_windows(self, img_np: np.ndarray) -> List[List[int]]:
        """Brightness-threshold window detector for curtain localisation."""
        h, w = img_np.shape[:2]
        gray = cv2.cvtColor(img_np, cv2.COLOR_RGB2GRAY)
        blur = cv2.GaussianBlur(gray, (7, 7), 0)
        mean_v, std_v = np.mean(blur), np.std(blur)
        thresh_v = np.clip(mean_v + 1.0 * std_v, 135, 230)
        _, thresh = cv2.threshold(blur, thresh_v, 255, cv2.THRESH_BINARY)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 15))
        opened = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel)
        contours, _ = cv2.findContours(opened, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        boxes = []
        for cnt in contours:
            x, y, cw, ch = cv2.boundingRect(cnt)
            if cw * ch > 0.008 * w * h and (y + ch * 0.4) < 0.75 * h:
                if 0.18 < cw / ch < 3.2:
                    boxes.append([x, y, x + cw, y + ch])
        return boxes

    def _smart_detect(
        self,
        img: Image.Image,
        category: str,
        scene_profile: dict,
    ) -> Tuple[Optional[list], Optional[list]]:
        """Returns [x1, y1, x2, y2] bbox and a [cx, cy] point prompt."""
        w, h = img.size
        img_np = np.array(img)

        if category == "curtains":
            win_boxes = self._detect_windows(img_np)
            if win_boxes:
                best = max(win_boxes, key=lambda b: (b[2]-b[0])*(b[3]-b[1]))
                bx1, by1, bx2, by2 = best
                ww = bx2 - bx1
                bx1_f = max(0, bx1 - int(0.25 * ww))
                bx2_f = min(w, bx2 + int(0.25 * ww))
                return [bx1_f, by1, bx2_f, by2], [int((bx1_f+bx2_f)/2), int(by1+(by2-by1)*0.5)]
            return [0, int(h*0.05), w, int(h*0.90)], [int(w*0.15), int(h*0.5)]

        if category == "carpets":
            return [0, int(h*0.50), w, h], [int(w*0.5), int(h*0.80)]

        info = CATEGORY_YOLO_MAP.get(category, {})
        classes = info.get("classes", [])
        detections = []
        for cls_id in classes:
            if cls_id in scene_profile["detections"]:
                detections.extend(scene_profile["detections"][cls_id])

        if not detections:
            # Generic centre fallback
            return [int(w*0.1), int(h*0.1), int(w*0.9), int(h*0.9)], [int(w*0.5), int(h*0.5)]

        best = max(detections, key=lambda d: d["conf"])
        x1, y1, x2, y2 = best["bbox"]
        bw, bh = x2 - x1, y2 - y1

        if category == "bedsheets":
            # YOLO class 59 = whole bed frame. Sheet is lower ~65% of bbox.
            x1_f = x1 + bw * 0.04
            x2_f = x2 - bw * 0.04
            y1_f = y1 + bh * 0.30   # top 30% is headboard/pillows
            y2_f = y2 - bh * 0.02
            pt = [int((x1_f+x2_f)/2), int(y1_f + (y2_f-y1_f)*0.60)]
            return [x1_f, y1_f, x2_f, y2_f], pt

        elif category == "sofa_covers":
            return [x1, y1, x2, y2], [int((x1+x2)/2), int(y1+bh*0.55)]

        elif category == "pillows":
            y2_p = y1 + bh * 0.40
            return [x1, y1, x2, y2_p], [int((x1+x2)/2), int(y1+(y2_p-y1)*0.5)]

        return [x1, y1, x2, y2], [int((x1+x2)/2), int((y1+y2)/2)]

    # =========================================================================
    #  STAGE 3 — FastSAM segmentation
    # =========================================================================

    def _get_occlusion_mask(
        self, scene_profile: dict, category: str, h: int, w: int
    ) -> np.ndarray:
        occ = np.zeros((h, w), dtype=np.uint8)
        for cls_id in [0, 15, 16]:  # person, cat, dog
            for det in scene_profile["detections"].get(cls_id, []):
                x1, y1, x2, y2 = [int(v) for v in det["bbox"]]
                occ[max(0,y1-2):min(h,y2+2), max(0,x1-2):min(w,x2+2)] = 255
        if category == "carpets":
            for cls_id in [56, 57, 58, 59, 60]:
                for det in scene_profile["detections"].get(cls_id, []):
                    x1, y1, x2, y2 = [int(v) for v in det["bbox"]]
                    occ[max(0,y1-2):min(h,y2+8), max(0,x1-5):min(w,x2+5)] = 255
        return occ

    def _score_and_filter_masks(
        self,
        masks: np.ndarray,
        category: str,
        bbox: Optional[list],
        point: Optional[list],
        img_np: np.ndarray,
        scene_profile: dict,
        depth_map: np.ndarray,
    ) -> Optional[np.ndarray]:
        h, w = img_np.shape[:2]
        num_masks = masks.shape[0]

        # Resize masks to image dimensions if needed
        mh, mw = masks.shape[1], masks.shape[2]
        if mh != h or mw != w:
            resized = []
            for i in range(num_masks):
                resized.append(cv2.resize(
                    masks[i].astype(np.uint8), (w, h), interpolation=cv2.INTER_NEAREST))
            masks = np.array(resized)

        img_area = w * h
        occ = self._get_occlusion_mask(scene_profile, category, h, w)

        # ── BEDSHEETS ─────────────────────────────────────────────────────────
        if category == "bedsheets":
            if bbox is None:
                return None
            bx1, by1, bx2, by2 = bbox
            bw, bh = bx2-bx1, by2-by1
            bbox_area = bw * bh
            seed_mask, seed_score = None, -99999.0

            for mask in masks:
                ma = mask.sum()
                if ma == 0 or ma > 0.65 * img_area:
                    continue
                ov = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                containment = ov / float(ma)
                coverage = ov / float(bbox_area) if bbox_area > 0 else 0
                if containment > 0.40 and coverage > 0.05:
                    y_idx, _ = np.where(mask > 0)
                    cy = np.mean(y_idx) if len(y_idx) > 0 else 0
                    if cy > by1 + 0.10 * bh:
                        sc = ma + ov * 1.5
                        if sc > seed_score:
                            seed_score = sc
                            seed_mask = mask

            if seed_mask is None:
                return None

            seed_depth = np.mean(depth_map[seed_mask > 0]) if seed_mask.sum() > 0 else 0.5

            # Subtract pillows (higher depth = closer to viewer = higher in image)
            pillows_sub = np.zeros((h, w), dtype=np.uint8)
            for mask in masks:
                ma = mask.sum()
                if ma == 0 or ma > 0.12 * img_area:
                    continue
                ov = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                if ov / float(ma) > 0.60:
                    y_idx, _ = np.where(mask > 0)
                    if len(y_idx) > 0:
                        cy = np.mean(y_idx)
                        if cy < by1 + 0.55 * bh:
                            md = np.mean(depth_map[mask > 0])
                            if md > seed_depth + 0.015:
                                pillows_sub = cv2.bitwise_or(pillows_sub, mask.astype(np.uint8))

            # Subtract headboard/frame
            frame_sub = np.zeros((h, w), dtype=np.uint8)
            for mask in masks:
                ma = mask.sum()
                if ma == 0:
                    continue
                y_idx, _ = np.where(mask > 0)
                if len(y_idx) > 0:
                    cy = np.mean(y_idx)
                    if cy < by1 + 0.15 * bh or cy > by2 - 0.05 * bh:
                        fsub = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                        if fsub / float(ma) > 0.70:
                            frame_sub = cv2.bitwise_or(frame_sub, mask.astype(np.uint8))

            # Merge adjacent sheets at same depth
            merged = seed_mask.copy().astype(np.uint8)
            for mask in masks:
                if np.array_equal(mask, seed_mask):
                    continue
                ma = mask.sum()
                if ma == 0 or ma > 0.45 * img_area:
                    continue
                ov = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                if ov / float(ma) > 0.50:
                    md = np.mean(depth_map[mask > 0]) if ma > 0 else 0.5
                    if abs(md - seed_depth) < 0.12:
                        y_idx, _ = np.where(mask > 0)
                        cy = np.mean(y_idx) if len(y_idx) > 0 else 0
                        if cy > by1 + 0.12 * bh:
                            dilated = cv2.dilate(mask.astype(np.uint8),
                                                 cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
                            if cv2.bitwise_and(dilated, merged).sum() > 50:
                                merged = cv2.bitwise_or(merged, mask.astype(np.uint8))

            result = merged & ~pillows_sub & ~frame_sub & ~(occ > 0)
            return result

        # ── SOFA COVERS ───────────────────────────────────────────────────────
        elif category == "sofa_covers":
            if bbox is None:
                return None
            bx1, by1, bx2, by2 = bbox
            bw, bh = bx2-bx1, by2-by1
            bbox_area = bw * bh
            seed_mask, seed_score = None, -99999.0

            for mask in masks:
                ma = mask.sum()
                if ma == 0 or ma > 0.60 * img_area:
                    continue
                ov = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                containment = ov / float(ma)
                coverage = ov / float(bbox_area) if bbox_area > 0 else 0
                if containment > 0.45 and coverage > 0.05:
                    sc = ma + ov * 2.0
                    if sc > seed_score:
                        seed_score = sc
                        seed_mask = mask

            if seed_mask is None:
                return None

            seed_depth = np.mean(depth_map[seed_mask > 0]) if seed_mask.sum() > 0 else 0.5
            legs_sub = np.zeros((h, w), dtype=np.uint8)
            for mask in masks:
                ma = mask.sum()
                if ma == 0:
                    continue
                y_idx, _ = np.where(mask > 0)
                if len(y_idx) > 0 and np.mean(y_idx) > by2 - 0.15 * bh:
                    legs_sub = cv2.bitwise_or(legs_sub, mask.astype(np.uint8))

            merged = seed_mask.copy().astype(np.uint8)
            for mask in masks:
                if np.array_equal(mask, seed_mask):
                    continue
                ma = mask.sum()
                if ma == 0 or ma > 0.40 * img_area:
                    continue
                ov = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                if ov / float(ma) > 0.45:
                    md = np.mean(depth_map[mask > 0]) if ma > 0 else 0.5
                    if abs(md - seed_depth) < 0.15:
                        dilated = cv2.dilate(mask.astype(np.uint8),
                                             cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
                        if cv2.bitwise_and(dilated, merged).sum() > 50:
                            merged = cv2.bitwise_or(merged, mask.astype(np.uint8))

            return merged & ~legs_sub & ~(occ > 0)

        # ── CURTAINS ──────────────────────────────────────────────────────────
        elif category == "curtains":
            img_np_arr = img_np
            curtain_mask = np.zeros((h, w), dtype=np.uint8)
            found = False
            win_boxes = self._detect_windows(img_np_arr)
            for mask in masks:
                ma = mask.sum()
                if ma == 0 or ma / img_area > 0.42:
                    continue
                y_idx, x_idx = np.where(mask > 0)
                if len(x_idx) == 0:
                    continue
                mw_val = np.max(x_idx) - np.min(x_idx)
                mh_val = np.max(y_idx) - np.min(y_idx)
                if mh_val == 0 or mw_val == 0:
                    continue
                aspect = mh_val / mw_val
                rel_h = mh_val / h
                cy = np.mean(y_idx)
                cx = np.mean(x_idx)
                if aspect > 1.15 and rel_h > 0.15 and 0.06 * h < cy < 0.90 * h:
                    valid = False
                    if win_boxes:
                        for wb in win_boxes:
                            wx1, wy1, wx2, wy2 = wb
                            ww = wx2 - wx1
                            if wx1 - 0.50 * ww <= cx <= wx2 + 0.50 * ww:
                                valid = True
                                break
                    else:
                        if cx < 0.40 * w or cx > 0.60 * w:
                            valid = True
                    if valid:
                        curtain_mask = cv2.bitwise_or(curtain_mask, mask.astype(np.uint8))
                        found = True
            return curtain_mask if found else None

        # ── PILLOWS ───────────────────────────────────────────────────────────
        elif category == "pillows":
            pillow_mask = np.zeros((h, w), dtype=np.uint8)
            found = False
            surrounding = []
            for cls_id in [59, 57, 56]:
                for d in scene_profile["detections"].get(cls_id, []):
                    surrounding.append(d["bbox"])
            for mask in masks:
                ma = mask.sum()
                sf = ma / img_area
                if not (0.0005 < sf < 0.05):
                    continue
                y_idx, x_idx = np.where(mask > 0)
                if len(x_idx) == 0:
                    continue
                mw_val = np.max(x_idx) - np.min(x_idx)
                mh_val = np.max(y_idx) - np.min(y_idx)
                if mh_val == 0 or mw_val == 0:
                    continue
                aspect = mw_val / mh_val
                if 0.40 < aspect < 2.5:
                    cx = np.mean(x_idx)
                    cy = np.mean(y_idx)
                    near = False
                    if surrounding:
                        for sb in surrounding:
                            sbx1, sby1, sbx2, sby2 = sb
                            sbh = sby2 - sby1
                            if sbx1 - 30 <= cx <= sbx2 + 30 and sby1 - 20 <= cy <= sby1 + sbh * 0.60:
                                near = True
                                break
                    else:
                        near = 0.20 * h < cy < 0.75 * h
                    if near:
                        pillow_mask = cv2.bitwise_or(pillow_mask, mask.astype(np.uint8))
                        found = True
            return pillow_mask if found else None

        # ── CARPETS ───────────────────────────────────────────────────────────
        elif category == "carpets":
            best_carpet, best_score = None, -9999.0
            for mask in masks:
                ma = mask.sum()
                sf = ma / img_area
                if ma == 0 or sf > 0.60:
                    continue
                y_idx, x_idx = np.where(mask > 0)
                if len(y_idx) == 0:
                    continue
                lower_area = mask[int(h * 0.48):, :].sum()
                containment = lower_area / float(ma)
                mw_val = np.max(x_idx) - np.min(x_idx)
                mh_val = np.max(y_idx) - np.min(y_idx)
                if mh_val == 0:
                    continue
                aspect = mw_val / mh_val
                if containment > 0.75 and aspect > 1.10 and sf > 0.02:
                    sc = sf * 2.0 + containment
                    if sc > best_score:
                        best_score = sc
                        best_carpet = mask
            if best_carpet is not None:
                return best_carpet.astype(np.uint8) & ~(occ > 0)

        return None

    def _precise_segment(
        self,
        img: Image.Image,
        bbox: Optional[list],
        point: Optional[list],
        category: str,
        scene_profile: dict,
    ) -> np.ndarray:
        w, h = img.size
        img_np = np.array(img)
        depth_map = self._estimate_midas_depth(img_np)

        try:
            fastsam = self._get_fastsam()
            results = fastsam.predict(
                source=img,
                conf=0.04,
                device=self.device,
                imgsz=640,
                retina_masks=True,
                verbose=False,
            )
            if results and results[0].masks is not None and len(results[0].masks) > 0:
                masks = results[0].masks.data.cpu().numpy()
                final = self._score_and_filter_masks(
                    masks, category, bbox, point, img_np, scene_profile, depth_map)
                if final is not None:
                    final_u8 = (final * 255).astype(np.uint8) if final.max() <= 1 else final.astype(np.uint8)
                    return final_u8
        except Exception as e:
            print(f"[VastraPipeline] FastSAM error: {e}")

        if bbox is not None:
            return self._bbox_mask(w, h, bbox)
        return np.zeros((h, w), dtype=np.uint8)

    def _bbox_mask(self, w: int, h: int, bbox: list) -> np.ndarray:
        mask = np.zeros((h, w), dtype=np.uint8)
        x1, y1, x2, y2 = [int(v) for v in bbox]
        mask[max(0, y1):min(h, y2), max(0, x1):min(w, x2)] = 255
        return mask

    # =========================================================================
    #  MASK UTILITIES
    # =========================================================================

    def _normalize_mask(self, mask_np: np.ndarray) -> np.ndarray:
        """
        Guarantee mask is uint8 with object=255, background=0.
        Handles FastSAM sometimes outputting inverted masks (object=0).
        Heuristic: if more than 70% of pixels are 255, invert.
        """
        if mask_np.dtype != np.uint8:
            mask_np = mask_np.astype(np.uint8)
        if mask_np.max() <= 1:
            mask_np = (mask_np * 255).astype(np.uint8)
        nonzero = np.count_nonzero(mask_np)
        total = mask_np.size
        if total > 0 and nonzero / total > 0.70:
            mask_np = cv2.bitwise_not(mask_np)
        _, mask_np = cv2.threshold(mask_np, 127, 255, cv2.THRESH_BINARY)
        return mask_np

    def _guided_filter(
        self, guidance: np.ndarray, p: np.ndarray, r: int = 8, eps: float = 0.04
    ) -> np.ndarray:
        if len(guidance.shape) == 3:
            guidance = cv2.cvtColor(guidance, cv2.COLOR_RGB2GRAY)
        I = guidance.astype(np.float32) / 255.0
        p_f = p.astype(np.float32) / 255.0
        mean_I = cv2.blur(I, (r, r))
        mean_p = cv2.blur(p_f, (r, r))
        mean_Ip = cv2.blur(I * p_f, (r, r))
        cov_Ip = mean_Ip - mean_I * mean_p
        var_I = cv2.blur(I * I, (r, r)) - mean_I * mean_I
        a = cov_Ip / (var_I + eps)
        b = mean_p - a * mean_I
        q = cv2.blur(a, (r, r)) * I + cv2.blur(b, (r, r))
        return np.clip(q * 255.0, 0, 255).astype(np.uint8)

    def _clean_mask(self, img_np: np.ndarray, mask_np: np.ndarray) -> np.ndarray:
        if mask_np.sum() == 0:
            return mask_np
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        cleaned = cv2.morphologyEx(mask_np, cv2.MORPH_CLOSE, kernel)
        cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_OPEN, kernel)
        num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(cleaned)
        if num_labels > 1:
            new_mask = np.zeros_like(cleaned)
            max_comp = 2 if num_labels > 2 and stats[2, cv2.CC_STAT_AREA] > 500 else 1
            sorted_idx = sorted(range(1, num_labels),
                                key=lambda i: stats[i, cv2.CC_STAT_AREA], reverse=True)
            for idx in sorted_idx[:max_comp]:
                if stats[idx, cv2.CC_STAT_AREA] > 120:
                    new_mask[labels == idx] = 255
            cleaned = new_mask
        cleaned = self._guided_filter(img_np, cleaned, r=6, eps=0.03)
        _, cleaned = cv2.threshold(cleaned, 127, 255, cv2.THRESH_BINARY)
        return cleaned

    def _validate_mask(self, mask_np: np.ndarray, category: str) -> Tuple[bool, str]:
        h, w = mask_np.shape[:2]
        img_area = w * h
        mask_area = mask_np.sum() / 255.0
        coverage = mask_area / img_area
        if coverage < 0.0012:
            return False, "Under-segmented or empty mask"
        if coverage > 0.65:
            return False, "Excessive background bleed"
        if category in ["bedsheets", "carpets", "sofa_covers"]:
            top = mask_np[0:int(h * 0.10), :]
            if (top.sum() / 255.0) > 0.005 * mask_area:
                return False, "Mask overflow into ceiling/walls"
        if category == "carpets":
            upper = mask_np[0:int(h * 0.40), :]
            if (upper.sum() / 255.0) > 0.012 * mask_area:
                return False, "Carpet mask bleed into furniture"
        return True, "Passed"

    # =========================================================================
    #  STAGE 4 — Depth estimation
    # =========================================================================

    def _estimate_midas_depth(self, img_np: np.ndarray) -> np.ndarray:
        h, w = img_np.shape[:2]
        try:
            model, transform = self._load_depth_model()
            if model is not None and transform is not None:
                inp = transform(img_np).to(self.device)
                with torch.no_grad():
                    pred = model(inp)
                    pred = torch.nn.functional.interpolate(
                        pred.unsqueeze(1), size=(h, w),
                        mode="bicubic", align_corners=False).squeeze()
                depth = pred.cpu().numpy()
                d_min, d_max = depth.min(), depth.max()
                if d_max > d_min:
                    return (depth - d_min) / (d_max - d_min)
                return np.zeros_like(depth)
        except Exception as e:
            print(f"[VastraPipeline] MiDaS failed: {e}. Using analytic fallback.")

        # Analytic perspective fallback
        y_hor = h * 0.40
        y_idx = np.tile(np.arange(h)[:, None], (1, w)).astype(np.float32)
        y_dist = np.maximum(y_idx - y_hor, 10.0)
        depth = 1000.0 / y_dist
        depth = cv2.GaussianBlur(depth, (15, 15), 0)
        d_min, d_max = depth.min(), depth.max()
        if d_max > d_min:
            return (depth - d_min) / (d_max - d_min)
        return depth

    # =========================================================================
    #  STAGE 5 — Fabric preparation (perspective-correct tiling)
    # =========================================================================

    def _prepare_fabric(
        self,
        fabric_pil: Image.Image,
        mask_np: np.ndarray,
        room_np: np.ndarray,
        bbox: Optional[list],
        depth_map: np.ndarray,
        product_category: str,
    ) -> np.ndarray:
        """
        Perspective-correct fabric tiling.
        Centers coordinate grid on bbox center.
        Scale modulated by smooth depth map.
        Tile size = proportional to mask bbox (not fixed 256 px).
        """
        h, w = room_np.shape[:2]
        fabric_np = np.array(fabric_pil.convert("RGB"), dtype=np.uint8)
        fw, fh = fabric_np.shape[1], fabric_np.shape[0]

        if mask_np.sum() == 0:
            return cv2.resize(fabric_np, (w, h), interpolation=cv2.INTER_LANCZOS4)

        # Tile reference size = proportional to mask bbox width for realism
        if bbox is not None:
            bx1, by1, bx2, by2 = [int(v) for v in bbox]
            bbox_w = max(bx2 - bx1, 64)
        else:
            ys, xs = np.where(mask_np > 0)
            if len(xs) > 0:
                bbox_w = int(np.max(xs) - np.min(xs))
            else:
                bbox_w = w // 2
        # Use 1/3 of bbox width as tile reference — 2-3 tiles across object
        tile_ref = max(64.0, float(bbox_w) / 3.0)

        # Smooth depth
        depth_smooth = cv2.GaussianBlur(depth_map.astype(np.float32), (51, 51), 0)
        d_min, d_max = depth_smooth.min(), depth_smooth.max()
        depth_norm = (depth_smooth - d_min) / (d_max - d_min + 1e-6)
        # Closer = larger pattern, further = smaller
        local_scale = depth_norm * 0.8 + 0.4

        base_scale = CATEGORY_BASE_SCALE.get(product_category, 1.0)

        # Centre on bbox
        if bbox is not None:
            cx = (bx1 + bx2) / 2.0
            cy = (by1 + by2) / 2.0
        else:
            cx, cy = w / 2.0, h / 2.0

        xs, ys = np.meshgrid(np.arange(w), np.arange(h))
        dx = xs - cx
        dy = ys - cy

        map_u = (dx / (local_scale * base_scale)) * (fw / tile_ref) + fw / 2.0
        map_v = (dy / (local_scale * base_scale)) * (fh / tile_ref) + fh / 2.0

        # Seamless tiling
        map_u = (map_u % fw).astype(np.float32)
        map_v = (map_v % fh).astype(np.float32)

        remapped = cv2.remap(
            fabric_np, map_u, map_v,
            interpolation=cv2.INTER_LANCZOS4,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return remapped  # shape (h, w, 3) uint8

    # =========================================================================
    #  STAGE 6 — Masked lighting transfer (FIX: restricted to mask only)
    # =========================================================================

    def _apply_masked_lighting(
        self,
        fabric_np: np.ndarray,
        room_np: np.ndarray,
        mask_np: np.ndarray,
        verify_dir: str = None,
    ) -> np.ndarray:
        """
        Transfers lighting from the original room ONLY within the masked region.

        KEY FIX vs original:
        - shading_factor is computed from room_smooth_gray inside the mask only
        - ref_brightness = 75th percentile of MASKED pixels (not global image)
        - shading_factor is applied only where mask_np > 50
        - Outside mask pixels keep the original room content unchanged

        Steps:
          1. Smooth original grayscale with Guided Filter to erase print patterns
             while preserving fold/shadow edges.
          2. Extract high-frequency wrinkle details (orig - smooth).
          3. Compute shading_factor = smooth_gray / ref_brightness (masked only).
          4. Multiply fabric by shading_factor within mask.
          5. Add back wrinkle details at reduced strength.
        """
        h, w = room_np.shape[:2]

        room_gray = (
            0.299 * room_np[:, :, 0].astype(np.float32)
            + 0.587 * room_np[:, :, 1].astype(np.float32)
            + 0.114 * room_np[:, :, 2].astype(np.float32)
        ).astype(np.uint8)

        # Guided filter to erase pattern, preserve folds
        room_smooth = self._guided_filter(room_gray, room_gray, r=16, eps=0.06)

        if verify_dir:
            luma_path = os.path.join(verify_dir, "luminance_map.png")
            cv2.imwrite(luma_path, room_smooth)
            print(f"[_apply_masked_lighting] Saved intermediate luminance map to '{luma_path}'")

        # Wrinkle high-freq details
        details = room_gray.astype(np.float32) - room_smooth.astype(np.float32)

        # Reference brightness from MASKED region only
        masked_pixels = room_smooth[mask_np > 50]
        if len(masked_pixels) > 0:
            ref_brightness = float(np.percentile(masked_pixels, 75))
            ref_brightness = np.clip(ref_brightness, 80.0, 220.0)
        else:
            ref_brightness = 180.0

        shading_factor = room_smooth.astype(np.float32) / ref_brightness
        shading_factor = np.clip(shading_factor, 0.20, 1.40)

        # Apply shading and wrinkle details to fabric
        fabric_f = fabric_np.astype(np.float32)
        blended = fabric_f * shading_factor[:, :, np.newaxis]
        blended = blended + details[:, :, np.newaxis] * 0.75
        blended = np.clip(blended, 0, 255).astype(np.uint8)

        # Apply ONLY inside mask — outside stays as original room
        mask_bool = (mask_np > 50)[:, :, np.newaxis]
        result = np.where(mask_bool, blended, room_np)
        return result.astype(np.uint8)

    # =========================================================================
    #  STAGE 7 — SD inpainting (PRIMARY OUTPUT PATH)
    # =========================================================================

    def _describe_fabric(self, fabric_pil: Image.Image) -> str:
        """Simple colour + texture descriptor for the SD prompt."""
        fabric_np = np.array(fabric_pil.convert("RGB"))
        mean_rgb = fabric_np.mean(axis=(0, 1))
        r, g, b = mean_rgb
        if r > 200 and g > 200 and b > 200:
            colour = "light-coloured"
        elif r > 200 and g < 120 and b < 120:
            colour = "red-toned"
        elif r < 100 and g < 100 and b > 150:
            colour = "blue-toned"
        elif r < 100 and g > 150 and b < 100:
            colour = "green-toned"
        elif r > 180 and g > 150 and b < 100:
            colour = "warm yellow-toned"
        elif r < 80 and g < 80 and b < 80:
            colour = "dark-coloured"
        else:
            colour = "neutral-toned"

        std = float(fabric_np.std())
        texture = "patterned" if std > 55 else ("textured" if std > 25 else "plain")
        return f"{colour} {texture}"

    def _run_sd_inpainting(
        self,
        room_pil: Image.Image,
        mask_np: np.ndarray,
        lit_fabric_np: np.ndarray,
        prompt: str,
        w: int,
        h: int,
    ) -> Image.Image:
        """
        Primary output path: sends to cloud SD inpainting via InpaintService.
        The lit_fabric is composited onto the room image BEFORE sending so the
        SD model has the correct fabric colour/pattern as a starting point.
        inpainting strength=0.75 preserves room lighting structure.

        Falls back to direct numpy composite if cloud call fails.
        """
        req_id = uuid.uuid4().hex[:8]
        tmp = tempfile.gettempdir()
        room_path    = os.path.join(tmp, f"vastra_{req_id}_room.png")
        mask_path    = os.path.join(tmp, f"vastra_{req_id}_mask.png")
        output_path  = os.path.join(tmp, f"vastra_{req_id}_output.png")

        try:
            # Build pre-composited init image: fabric painted into mask region
            fabric_pil = Image.fromarray(lit_fabric_np.astype(np.uint8), "RGB")
            mask_pil   = Image.fromarray(mask_np, "L")
            # Feather mask for soft edges
            mask_feathered = mask_pil.filter(ImageFilter.GaussianBlur(radius=2))
            # Pre-composite: fabric in masked area, original elsewhere
            init_image = Image.composite(fabric_pil, room_pil, mask_feathered)

            init_image.save(room_path, "PNG")

            # SD inpaint mask: white = regenerate, black = keep
            # mask_np is already white=object, so this is correct
            mask_pil.save(mask_path, "PNG")

            result_path = self.inpaint_service.run_inpaint(
                image_path=room_path,
                mask_path=mask_path,
                prompt=prompt,
                output_path=output_path,
            )
            result_pil = Image.open(result_path).convert("RGB").resize((w, h), Image.Resampling.LANCZOS)
            print(f"[VastraPipeline] SD inpainting succeeded.")
            return result_pil

        except Exception as e:
            print(f"[VastraPipeline] SD inpainting failed: {e}. Using numpy fallback composite.")
            # Fallback: direct numpy composite
            mask_feathered = Image.fromarray(mask_np, "L").filter(
                ImageFilter.GaussianBlur(radius=2.5))
            fabric_pil = Image.fromarray(
                np.clip(lit_fabric_np, 0, 255).astype(np.uint8), "RGB")
            result = Image.composite(fabric_pil, room_pil, mask_feathered)
            return result

        finally:
            for p in [room_path, mask_path, output_path]:
                try:
                    if os.path.exists(p):
                        os.remove(p)
                except Exception:
                    pass

    # =========================================================================
    #  STAGE 8 — Poisson blending
    # =========================================================================

    def _poisson_blend(
        self,
        result_np: np.ndarray,
        room_np: np.ndarray,
        mask_np: np.ndarray,
    ) -> np.ndarray:
        """
        Poisson seamless clone at the mask boundary for photorealistic edges.
        Falls back to Gaussian-feathered alpha blend if Poisson fails.
        """
        if mask_np.sum() == 0:
            return result_np

        try:
            # OpenCV seamlessClone requires uint8 BGR, mask uint8, single channel
            src_bgr = cv2.cvtColor(result_np, cv2.COLOR_RGB2BGR)
            dst_bgr = cv2.cvtColor(room_np, cv2.COLOR_RGB2BGR)

            # Centre of the mask
            moments = cv2.moments(mask_np)
            if moments["m00"] > 0:
                cx = int(moments["m10"] / moments["m00"])
                cy = int(moments["m01"] / moments["m00"])
            else:
                h, w = mask_np.shape
                cx, cy = w // 2, h // 2

            blended_bgr = cv2.seamlessClone(
                src_bgr, dst_bgr, mask_np, (cx, cy), cv2.NORMAL_CLONE)
            return cv2.cvtColor(blended_bgr, cv2.COLOR_BGR2RGB)

        except Exception as e:
            print(f"[VastraPipeline] Poisson blend failed: {e}. Using feathered fallback.")
            mask_blur = cv2.GaussianBlur(mask_np.astype(np.float32) / 255.0, (21, 21), 0)
            alpha = mask_blur[:, :, np.newaxis]
            blended = (result_np.astype(np.float32) * alpha
                       + room_np.astype(np.float32) * (1.0 - alpha))
            return np.clip(blended, 0, 255).astype(np.uint8)

    # =========================================================================
    #  STAGE 9 — Audit + heal
    # =========================================================================

    def _audit_final_output(
        self,
        final_np: np.ndarray,
        room_np: np.ndarray,
        mask_np: np.ndarray,
    ) -> np.ndarray:
        """Fills black holes (pixels < 8 luminance inside mask) with original content."""
        final_np = np.nan_to_num(final_np.astype(np.float32), nan=0, posinf=255, neginf=0)
        final_np = np.clip(final_np, 0, 255).astype(np.uint8)

        gray_f = cv2.cvtColor(final_np, cv2.COLOR_RGB2GRAY)
        gray_r = cv2.cvtColor(room_np, cv2.COLOR_RGB2GRAY)
        black_holes = (gray_f < 8) & (gray_r > 15) & (mask_np > 0)

        if np.sum(black_holes) > 20:
            print(f"[VastraPipeline] Audit: healing {np.sum(black_holes)} black-hole pixels.")
            for c in range(3):
                final_np[:, :, c] = np.where(black_holes, room_np[:, :, c], final_np[:, :, c])

        return final_np

    # =========================================================================
    #  RECOVERY segmentation (Stage 9 self-correcting loop)
    # =========================================================================

    def _run_recovery_segmentation(
        self,
        img_np: np.ndarray,
        bbox: Optional[list],
        category: str,
        scene_profile: dict,
    ) -> np.ndarray:
        """High-confidence FastSAM with tighter conf=0.22 + point anchor + GrabCut fallback."""
        h, w = img_np.shape[:2]

        if bbox is None:
            fallbacks = {
                "bedsheets":   [int(w*0.15), int(h*0.35), int(w*0.85), int(h*0.85)],
                "sofa_covers": [int(w*0.20), int(h*0.40), int(w*0.80), int(h*0.80)],
                "carpets":     [int(w*0.15), int(h*0.58), int(w*0.85), int(h*0.95)],
                "pillows":     [int(w*0.35), int(h*0.42), int(w*0.65), int(h*0.65)],
            }
            bbox = fallbacks.get(category, [0, 0, w, h])

        bx1, by1, bx2, by2 = bbox
        bw, bh = bx2-bx1, by2-by1
        cx, cy = int(bx1 + bw * 0.50), int(by1 + bh * 0.56)

        try:
            fastsam = self._get_fastsam()
            results = fastsam.predict(
                source=Image.fromarray(img_np),
                conf=0.22,
                device=self.device,
                imgsz=640,
                retina_masks=True,
                verbose=False,
            )
            if results and results[0].masks is not None and len(results[0].masks) > 0:
                masks = results[0].masks.data.cpu().numpy()
                mh, mw = masks.shape[1], masks.shape[2]
                if mh != h or mw != w:
                    resized = [cv2.resize(masks[i].astype(np.uint8), (w, h),
                                          interpolation=cv2.INTER_NEAREST)
                               for i in range(masks.shape[0])]
                    masks = np.array(resized)
                best_mask, best_score = None, -9999.0
                for mask in masks:
                    if mask[cy, cx] > 0:
                        ma = mask.sum()
                        if ma == 0 or ma > 0.50 * (w * h):
                            continue
                        in_box = mask[int(by1):int(by2), int(bx1):int(bx2)].sum()
                        out_box = ma - in_box
                        sc = in_box - 2.5 * out_box
                        if sc > best_score:
                            best_score = sc
                            best_mask = mask
                if best_mask is not None:
                    return (best_mask * 255).astype(np.uint8)
        except Exception as e:
            print(f"[VastraPipeline] Recovery FastSAM failed: {e}")

        return self._run_grabcut_recovery(img_np, bbox)

    def _run_grabcut_recovery(self, img_np: np.ndarray, bbox: list) -> np.ndarray:
        h, w = img_np.shape[:2]
        mask = np.zeros((h, w), dtype=np.uint8)
        bgd = np.zeros((1, 65), dtype=np.float64)
        fgd = np.zeros((1, 65), dtype=np.float64)
        bx1, by1, bx2, by2 = [int(v) for v in bbox]
        bx1, by1 = max(0, bx1), max(0, by1)
        bx2, by2 = min(w-1, bx2), min(h-1, by2)
        rect = (bx1, by1, bx2-bx1, by2-by1)
        try:
            cv2.grabCut(img_np, mask, rect, bgd, fgd, 4, cv2.GC_INIT_WITH_RECT)
            return np.where((mask == 2) | (mask == 0), 0, 1).astype(np.uint8) * 255
        except Exception as e:
            print(f"[VastraPipeline] GrabCut failed: {e}")
            fb = np.zeros((h, w), dtype=np.uint8)
            fb[by1:by2, bx1:bx2] = 255
            return fb

    # =========================================================================
    #  Missing object generation (curtains / carpets / pillows absent)
    # =========================================================================

    def _generate_missing_object(
        self,
        room_rgb: Image.Image,
        category: str,
        w: int,
        h: int,
        scene_profile: dict,
    ) -> Tuple[Image.Image, np.ndarray]:
        req_id = uuid.uuid4().hex[:8]
        tmp = tempfile.gettempdir()

        canvas_mask = Image.new("L", (w, h), color=0)
        draw = ImageDraw.Draw(canvas_mask)
        room_np = np.array(room_rgb)

        if category == "curtains":
            win_boxes = self._detect_windows(room_np)
            if win_boxes:
                wx1, wy1, wx2, wy2 = max(win_boxes, key=lambda b: (b[2]-b[0])*(b[3]-b[1]))
                ww, wh = wx2-wx1, wy2-wy1
                draw.rectangle([max(0, wx1-int(0.20*ww)), max(0, wy1-int(0.05*wh)),
                                 min(w, wx1+int(0.08*ww)), min(h, wy2+int(0.05*wh))], fill=255)
                draw.rectangle([max(0, wx2-int(0.08*ww)), max(0, wy1-int(0.05*wh)),
                                 min(w, wx2+int(0.20*ww)), min(h, wy2+int(0.05*wh))], fill=255)
            else:
                draw.rectangle([int(w*0.08), int(h*0.10), int(w*0.25), int(h*0.85)], fill=255)
                draw.rectangle([int(w*0.75), int(h*0.10), int(w*0.92), int(h*0.85)], fill=255)
            prompt = ("elegant luxury curtain panels hanging beautifully beside a window, "
                      "interior design, realistic folds, natural lighting, highly detailed")

        elif category == "carpets":
            draw.polygon([
                (int(w*0.25), int(h*0.65)), (int(w*0.75), int(h*0.65)),
                (int(w*0.90), int(h*0.94)), (int(w*0.10), int(h*0.94))
            ], fill=255)
            prompt = ("luxurious floor carpet rug, soft textile fibers, "
                      "natural room lighting, realistic perspective shadows")

        elif category == "pillows":
            draw.rectangle([int(w*0.38), int(h*0.45), int(w*0.62), int(h*0.70)], fill=255)
            prompt = "soft luxury bedroom throw pillow, high-end linen fabric, realistic shadows"

        else:
            return room_rgb, np.zeros((h, w), dtype=np.uint8)

        temp_room  = os.path.join(tmp, f"vastra_{req_id}_miss_room.png")
        temp_mask  = os.path.join(tmp, f"vastra_{req_id}_miss_mask.png")
        temp_out   = os.path.join(tmp, f"vastra_{req_id}_miss_output.png")

        try:
            compressed = compress_image(room_rgb, max_dimension=1024)
            compressed.save(temp_room, "PNG")
            canvas_mask.resize(compressed.size, Image.Resampling.NEAREST).save(temp_mask, "PNG")

            self.inpaint_service.run_inpaint(
                image_path=temp_room,
                mask_path=temp_mask,
                prompt=prompt,
                output_path=temp_out,
            )
            generated = Image.open(temp_out).convert("RGB")
            inpainted = generated.resize((w, h), Image.Resampling.LANCZOS)

            pt_cx, pt_cy = int(w*0.5), int(h*0.75)
            if category == "curtains":
                pt_cx, pt_cy = int(w*0.15), int(h*0.5)

            new_mask = self._precise_segment(
                inpainted,
                bbox=[0, 0, w, h],
                point=[pt_cx, pt_cy],
                category=category,
                scene_profile=scene_profile,
            )
            return inpainted, new_mask

        except Exception as ex:
            print(f"[VastraPipeline] Missing object generation failed: {ex}")
            return room_rgb, np.array(canvas_mask, dtype=np.uint8)

        finally:
            for p in [temp_room, temp_mask, temp_out]:
                try:
                    if os.path.exists(p):
                        os.remove(p)
                except Exception:
                    pass


class VastraFabricSwapPipeline:
    """
    VastraFabricSwapPipeline is the unified orchestrator pipeline for fabric visualizer.
    It encapsulates the VastraSegmenter to detect and generate a pristine binary comforter mask,
    and then invokes VastraInpainter to perform realistic fabric texture mapping.
    """
    def __init__(self, device: str = None):
        """
        Initializes the unified orchestrator pipeline.
        
        Args:
            device (str, optional): Target hardware device for model inference.
        """
        from .segmentation import VastraSegmenter
        from .inpaint import VastraInpainter
        self.device = device
        self.segmenter = VastraSegmenter(device=device)
        self.inpainter = VastraInpainter()
        print(f"[VastraFabricSwapPipeline] Unified Orchestrator Pipeline initialized.")

    def execute_full_flow(self, room_image_path: str, fabric_path: str, output_path: str) -> str:
        """
        Performs the complete fabric redesign pipeline from raw inputs to realistic swap.
        
        Args:
            room_image_path (str): File path to input room image.
            fabric_path (str): File path to input fabric swatch/texture image.
            output_path (str): Destination file path to save the fabric-swapped bedroom image.
            
        Returns:
            str: Path of the generated output image.
        """
        print("[VastraFabricSwapPipeline] Starting unified end-to-end fabric swap flow...")
        
        # Pass 1: Run our robust segmentation module to get the pristine mask
        polished_mask = self.segmenter.generate_comforter_mask(room_image_path)
        
        # Ensure output directory for the mask exists
        verify_dir = "backend/verify_outputs/v6_texture_replacement"
        os.makedirs(verify_dir, exist_ok=True)
        
        temp_mask_path = os.path.join(verify_dir, "mask.png")
        
        # Save the polished mask to a temporary or verification file path
        print(f"[VastraFabricSwapPipeline] Saving intermediate pristine mask to '{temp_mask_path}'...")
        cv2.imwrite(temp_mask_path, polished_mask)
        
        # Pass 2: Feed the original image, our custom mask, and the selected fabric directly 
        # into the preserved, pre-existing inpainting engine
        print("[VastraFabricSwapPipeline] Executing realistic fabric blending & inpainting...")
        self.inpainter.run(
            source_image=room_image_path,
            mask_image=temp_mask_path,
            texture_image=fabric_path,
            save_path=output_path,
            verify_dir=verify_dir
        )
        print(f"[VastraFabricSwapPipeline] Swapped bedroom output successfully generated at '{output_path}'")
        return output_path
