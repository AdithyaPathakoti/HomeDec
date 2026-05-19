import os
from PIL import Image
import numpy as np
from ultralytics import FastSAM

def main():
    print("Loading local FastSAM model...")
    model = FastSAM("FastSAM-s.pt")
    
    img_path = "uploads/ca2f7ecf-d4a4-4c40-a43b-097c91209b13_orig.png"
    if not os.path.exists(img_path):
        print(f"Error: {img_path} not found.")
        return
        
    pil_image = Image.open(img_path).convert("RGB")
    w, h = pil_image.size
    
    # 1. Point prompt test (middle of the image)
    print("\n--- Testing Point Prompt ---")
    cx, cy = w // 2, h // 2
    try:
        # Pass a lower conf for FastSAM to capture objects easily
        results = model.predict(pil_image, points=[[cx, cy]], labels=[1], conf=0.15, device="cpu")
        print(f"Point prompt results count: {len(results)}")
        if results and len(results) > 0:
            result = results[0]
            if hasattr(result, "masks") and result.masks is not None:
                print(f"Masks found! Count: {len(result.masks)}")
                mask_data = result.masks.data[0].numpy()
                print(f"Mask data shape: {mask_data.shape}, dtype: {mask_data.dtype}")
                # Save mask
                mask_img = Image.fromarray((mask_data * 255).astype(np.uint8))
                mask_img.save("test_fastsam_point_mask.png")
                print("Saved test_fastsam_point_mask.png successfully!")
            else:
                print("No masks found in point prompt result.")
    except Exception as e:
        print(f"Point prompt failed: {e}")
        
    # 2. Box prompt test
    print("\n--- Testing Box Prompt ---")
    x1, y1, x2, y2 = w // 4, h // 4, 3 * w // 4, 3 * h // 4
    try:
        results = model.predict(pil_image, bboxes=[[x1, y1, x2, y2]], conf=0.15, device="cpu")
        print(f"Box prompt results count: {len(results)}")
        if results and len(results) > 0:
            result = results[0]
            if hasattr(result, "masks") and result.masks is not None:
                print(f"Masks found! Count: {len(result.masks)}")
                mask_data = result.masks.data[0].numpy()
                print(f"Mask data shape: {mask_data.shape}, dtype: {mask_data.dtype}")
                mask_img = Image.fromarray((mask_data * 255).astype(np.uint8))
                mask_img.save("test_fastsam_box_mask.png")
                print("Saved test_fastsam_box_mask.png successfully!")
            else:
                print("No masks found in box prompt result.")
    except Exception as e:
        print(f"Box prompt failed: {e}")

if __name__ == "__main__":
    main()
