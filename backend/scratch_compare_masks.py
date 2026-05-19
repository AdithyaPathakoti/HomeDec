import os
from PIL import Image
import numpy as np
from ultralytics import FastSAM

def main():
    model = FastSAM("FastSAM-s.pt")
    img_path = "../bedroom_sample.png"
    if not os.path.exists(img_path):
        print("bedroom_sample.png not found.")
        return
        
    pil_image = Image.open(img_path).convert("RGB")
    w, h = pil_image.size
    
    # Tap point on the bed
    cx, cy = int(0.5 * w), int(0.7 * h)
    print(f"Tap point: ({cx}, {cy})")
    
    # Let's run the point prompt
    results = model.predict(pil_image, points=[[cx, cy]], labels=[1], conf=0.15, device="cpu")
    if results and len(results) > 0 and hasattr(results[0], "masks") and results[0].masks is not None:
        masks = results[0].masks.data
        print(f"Found {len(masks)} masks for point prompt.")
        for idx, mask in enumerate(masks):
            mask_np = mask.cpu().numpy()
            area = int(np.sum(mask_np))
            print(f"Mask {idx}: Area (pixels) = {area}, Shape = {mask_np.shape}")
            mask_img = Image.fromarray((mask_np * 255).astype(np.uint8))
            mask_img.save(f"test_fastsam_point_mask_{idx}_area_{area}.png")
    else:
        print("No masks found for point prompt.")

    # Let's see what happens if we construct a box based on the tolerance.
    # Original SAM2 code box: half_size = max(20, tolerance * 3)
    # Let's test half_size for tolerance=40 (half_size = 120) and tolerance=80 (half_size = 240)
    for tol in [40, 80]:
        half_size = max(20, tol * 4)
        x1, y1 = max(0, cx - half_size), max(0, cy - half_size)
        x2, y2 = min(w, cx + half_size), min(h, cy + half_size)
        print(f"\nTesting Box prompt for tolerance {tol} (box size {2*half_size}x{2*half_size}): [{x1}, {y1}, {x2}, {y2}]")
        
        results_box = model.predict(pil_image, bboxes=[[x1, y1, x2, y2]], conf=0.15, device="cpu")
        if results_box and len(results_box) > 0 and hasattr(results_box[0], "masks") and results_box[0].masks is not None:
            box_masks = results_box[0].masks.data
            print(f"Found {len(box_masks)} masks for box prompt.")
            for idx, mask in enumerate(box_masks):
                mask_np = mask.cpu().numpy()
                area = int(np.sum(mask_np))
                print(f"  Box Mask {idx}: Area = {area}")
                mask_img = Image.fromarray((mask_np * 255).astype(np.uint8))
                mask_img.save(f"test_fastsam_box_tol_{tol}_mask_{idx}_area_{area}.png")
        else:
            print("  No masks found for box prompt.")

if __name__ == "__main__":
    main()
