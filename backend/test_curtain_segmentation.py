#!/usr/bin/env python3
"""
test_curtain_segmentation.py
============================
Isolated testing script for high-precision curtain segmentation.
Uses LangSAM for positive/negative text-based grounding and SAM masks,
refined with aspect-ratio, Y-coordinate, and vertical morphology filters.
"""

import os
import sys
import time
import cv2
import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFont

# Setup paths
BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(BACKEND_DIR)

OUT_DIR = os.path.join(BACKEND_DIR, "verify_outputs", "curtain_testing")
os.makedirs(OUT_DIR, exist_ok=True)

DEFAULT_IMAGE = os.path.join(BACKEND_DIR, "test_new_bedsheets.png")


def _font(sz=18):
    try:
        return ImageFont.truetype("arial.ttf", sz)
    except:
        return ImageFont.load_default()


def draw_label(draw, xy, text, fg=(255, 255, 255), bg=(20, 20, 20)):
    f = _font(16)
    x, y = xy
    bb = draw.textbbox((x, y), text, font=f)
    draw.rectangle([bb[0]-3, bb[1]-2, bb[2]+3, bb[3]+2], fill=bg)
    draw.text((x, y), text, fill=fg, font=f)


def overlay_mask(img_np, mask, color=(0, 255, 0), alpha=0.35):
    out = img_np.copy().astype(np.float32)
    mb = mask > 127
    for c, v in enumerate(color):
        out[:, :, c] = np.where(mb, out[:, :, c] * (1 - alpha) + v * alpha, out[:, :, c])
    res = np.clip(out, 0, 255).astype(np.uint8)
    # Draw contour outline
    cnts, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(res, cnts, -1, color, 2)
    return res


def run_segmentation_on_image(img_path, model):
    if not os.path.exists(img_path):
        print(f"[ERROR] Image not found: {img_path}")
        return False

    img_basename = os.path.splitext(os.path.basename(img_path))[0]
    print(f"\nProcessing image: {img_path} ({img_basename})")
    
    room_pil = Image.open(img_path).convert("RGB")
    w, h = room_pil.size
    img_np = np.array(room_pil)

    # 1. Define positive and negative prompts
    # Separate positive and negative labels for open-vocabulary grounding
    pos_words = ["long window curtains", "hanging fabric drapes", "window drapery", "vertical fabric panels"]
    neg_words = ["painting", "picture frame", "bed headboard", "pillows", "nightstand", "table lamp", "cabinet", "chest of drawers"]
    
    # Grounding DINO parses a dot-separated prompt
    combined_prompt = " . ".join(pos_words + neg_words)
    print(f"Combined Prompt: '{combined_prompt}'")

    # Run LangSAM prediction
    print("Running LangSAM model prediction...")
    t0 = time.time()
    try:
        results = model.predict(
            [room_pil],
            [combined_prompt],
            box_threshold=0.45,  # Raise threshold to 0.45 to eliminate weak noise
            text_threshold=0.25
        )
        print(f"Prediction finished in {time.time()-t0:.2f} seconds.")
    except Exception as e:
        print(f"LangSAM prediction failed: {e}")
        return False

    result = results[0]
    masks = result["masks"]
    boxes = result["boxes"]
    phrases = result["labels"]
    logits = result["scores"]

    if masks is None or len(masks) == 0:
        print("Warning: No objects detected by LangSAM.")
        return False

    print(f"Model returned {len(masks)} candidate detections (conf >= 0.45):")

    pos_mask = np.zeros((h, w), dtype=np.uint8)
    neg_mask = np.zeros((h, w), dtype=np.uint8)
    
    pos_boxes_to_draw = []
    neg_boxes_to_draw = []

    # Map phrases to positive and negative categories
    for idx, (phrase, box, score) in enumerate(zip(phrases, boxes, logits)):
        phrase_clean = phrase.lower().strip()
        score_val = float(score)
        box_coords = [int(v) for v in box.cpu().numpy()] if hasattr(box, "cpu") else [int(v) for v in box]
        
        # Check if phrase matches positive or negative keywords
        is_pos = any(kw in phrase_clean for kw in ["curtain", "drape", "drapery", "panel"])
        is_neg = any(kw in phrase_clean for kw in ["painting", "picture", "frame", "headboard", "pillow", "nightstand", "lamp", "cabinet", "drawer"])
        
        print(f"  [{idx+1}] Label: '{phrase_clean}' | Conf: {score_val:.2f} | BBox: {box_coords}")

        # Get binary mask
        mask_single = masks[idx].cpu().numpy().astype(np.uint8) if hasattr(masks[idx], "cpu") else np.array(masks[idx], dtype=np.uint8)
        if mask_single.max() <= 1:
            mask_single = (mask_single * 255).astype(np.uint8)

        if is_neg:
            print("    -> Categorized as NEGATIVE EXCLUSION")
            neg_mask = cv2.bitwise_or(neg_mask, mask_single)
            neg_boxes_to_draw.append((box_coords, phrase_clean))
        elif is_pos:
            # Calculate properties
            y_indices, x_indices = np.where(mask_single > 0)
            if len(x_indices) > 0:
                x_min, x_max = np.min(x_indices), np.max(x_indices)
                y_min, y_max = np.min(y_indices), np.max(y_indices)
                box_w = max(1, x_max - x_min)
                box_h = max(1, y_max - y_min)
                aspect = box_h / box_w
                cy = np.mean(y_indices)
                cx = np.mean(x_indices)
                
                print(f"    -> Candidate check: Aspect Ratio (H/W) = {aspect:.2f} | Centroid = ({cx:.1f}, {cy:.1f})")

                # Aspect Ratio Filter: Height / Width > 1.5
                if aspect <= 1.5:
                    print(f"       [REJECTED] Failed aspect ratio constraint ({aspect:.2f} <= 1.5)")
                    continue

                # Y-Coordinate Filter: Reject if centroid is exclusively in center of bed or on floor
                # Rejects if centroid is on the floor (bottom 15% of frame)
                if cy > 0.85 * h:
                    print(f"       [REJECTED] Centroid is on the floor level (cy={cy:.1f} > {0.85 * h:.0f})")
                    continue
                # Rejects if centroid is in the center of the bed
                if 0.40 * h < cy < 0.78 * h and 0.28 * w < cx < 0.72 * w:
                    print(f"       [REJECTED] Centroid falls inside the center bed region")
                    continue
                
                print("       [ACCEPTED] Passed structural filters")
                pos_mask = cv2.bitwise_or(pos_mask, mask_single)
                pos_boxes_to_draw.append((box_coords, phrase_clean))
        else:
            print("    -> Unclassified category (skipped)")

    # 2. Subtract negative exclusions from the positive curtain mask
    curtain_mask = cv2.bitwise_and(pos_mask, cv2.bitwise_not(neg_mask))
    
    # 3. Clip the mask strictly at the ceiling line and floor pooled area
    # Real curtains hang from upper third, not touching ceiling margins
    curtain_mask[:int(h * 0.05), :] = 0
    # Strictly clip at bottom pool line to avoid bleeding into carpets/mats
    curtain_mask[int(h * 0.88):, :] = 0

    # 4. Edge Refining & Light Bleed Mitigation
    # Apply morphological closing with vertical kernel to bridge light bleed glare
    # followed by morphological opening to smooth vertical pleats
    kernel_close = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 25))
    kernel_open = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 15))
    
    refined_mask = cv2.morphologyEx(curtain_mask, cv2.MORPH_CLOSE, kernel_close)
    refined_mask = cv2.morphologyEx(refined_mask, cv2.MORPH_OPEN, kernel_open)

    # 5. Output Debugging Frames
    # Bbox visualization image
    bbox_vis = room_pil.copy()
    draw = ImageDraw.Draw(bbox_vis)
    
    # Draw negatives in red
    for box, text in neg_boxes_to_draw:
        draw.rectangle(box, outline=(255, 50, 50), width=3)
        draw_label(draw, (box[0]+4, box[1]+4), f"EXCLUDED: {text}", fg=(255, 50, 50))
    # Draw positives in green
    for box, text in pos_boxes_to_draw:
        draw.rectangle(box, outline=(50, 255, 50), width=3)
        draw_label(draw, (box[0]+4, box[1]+4), f"CURTAIN: {text}", fg=(50, 255, 50))

    # Save 01_curtain_bbox.png
    bbox_path_default = os.path.join(OUT_DIR, "01_curtain_bbox.png")
    bbox_path_scoped = os.path.join(OUT_DIR, f"01_curtain_bbox_{img_basename}.png")
    bbox_vis.save(bbox_path_scoped)
    # Also save as default if it is the primary test image
    if img_basename == "test_new_bedsheets" or img_basename == "image_5aa5c3":
        bbox_vis.save(bbox_path_default)
    print(f"Saved bbox frame to: {bbox_path_scoped}")

    # Save 02_curtain_raw_mask.png
    raw_mask_path_default = os.path.join(OUT_DIR, "02_curtain_raw_mask.png")
    raw_mask_path_scoped = os.path.join(OUT_DIR, f"02_curtain_raw_mask_{img_basename}.png")
    Image.fromarray(refined_mask).save(raw_mask_path_scoped)
    if img_basename == "test_new_bedsheets" or img_basename == "image_5aa5c3":
        Image.fromarray(refined_mask).save(raw_mask_path_default)
    print(f"Saved raw mask to: {raw_mask_path_scoped}")

    # Save 03_curtain_overlay.png
    overlay_vis = overlay_mask(img_np, refined_mask, color=(0, 255, 0), alpha=0.35)
    overlay_path_default = os.path.join(OUT_DIR, "03_curtain_overlay.png")
    overlay_path_scoped = os.path.join(OUT_DIR, f"03_curtain_overlay_{img_basename}.png")
    Image.fromarray(overlay_vis).save(overlay_path_scoped)
    if img_basename == "test_new_bedsheets" or img_basename == "image_5aa5c3":
        Image.fromarray(overlay_vis).save(overlay_path_default)
    print(f"Saved overlay frame to: {overlay_path_scoped}")

    return True


def main():
    print("=== STARTING ADVANCED CURTAIN SEGMENTATION OVERHAUL ===")
    
    # Identify images to test
    # If passed as command argument, test that image.
    # Otherwise, run on the original bedroom image and any available test images.
    images_to_test = []
    if len(sys.argv) > 1:
        images_to_test = sys.argv[1:]
    else:
        # Search for available test images in backend/ and parent workspace folders
        possible_paths = [
            DEFAULT_IMAGE,
            os.path.join(BACKEND_DIR, "image_5aa5c3.jpg"),
            os.path.join(os.path.dirname(BACKEND_DIR), "image_5aa5c3.jpg"),
            "backend/image_5aa5c3.jpg",
            "image_5aa5c3.jpg"
        ]
        images_to_test = [p for p in possible_paths if os.path.exists(p)]
        
    if not images_to_test:
        print("[ERROR] No valid test images found.")
        sys.exit(1)

    # Initialize LangSAM model once
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Initializing LangSAM model on device: {device}...")
    from lang_sam import LangSAM
    model = LangSAM(device=device)
    print("LangSAM loaded successfully.")

    success_count = 0
    for img_path in images_to_test:
        if run_segmentation_on_image(img_path, model):
            success_count += 1

    print(f"\nProcessed {success_count}/{len(images_to_test)} images successfully.")
    print(f"Outputs written to directory: {OUT_DIR}")
    print("=== CURTAIN SEGMENTATION OVERHAUL COMPLETE ===")


if __name__ == "__main__":
    main()
