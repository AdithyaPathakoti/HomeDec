import os
from PIL import Image
import numpy as np
from ultralytics import FastSAM

def main():
    print("Loading local FastSAM model...")
    model = FastSAM("FastSAM-s.pt")
    
    img_path = "../bedroom_sample.png"
    if not os.path.exists(img_path):
        print(f"Error: {img_path} not found.")
        return
        
    pil_image = Image.open(img_path).convert("RGB")
    w, h = pil_image.size
    print(f"Loaded image size: {w}x{h}")
    
    # Let's test a point prompt on the bed.
    # Usually in a bedroom sample image, the bed is around the center-bottom, e.g. x=0.5, y=0.7.
    cx, cy = int(0.5 * w), int(0.7 * h)
    print(f"\n--- Testing Point Prompt at ({cx}, {cy}) ---")
    
    # We will try with conf=0.10 and a very low conf=0.01 to see the difference
    for conf_val in [0.25, 0.15, 0.05, 0.01]:
        print(f"\nRunning point prompt with conf={conf_val}...")
        try:
            results = model.predict(pil_image, points=[[cx, cy]], labels=[1], conf=conf_val, device="cpu")
            if results and len(results) > 0:
                result = results[0]
                if hasattr(result, "masks") and result.masks is not None and len(result.masks) > 0:
                    print(f"Success! Masks found: {len(result.masks)}")
                    mask_data = result.masks.data[0].numpy()
                    print(f"Mask data shape: {mask_data.shape}, dtype: {mask_data.dtype}")
                    
                    # Save mask
                    mask_img = Image.fromarray((mask_data * 255).astype(np.uint8))
                    mask_img.save(f"test_fastsam_bedroom_point_conf_{conf_val}.png")
                    break
                else:
                    print("No masks found in point prompt result.")
            else:
                print("No results returned.")
        except Exception as e:
            print(f"Point prompt failed with conf={conf_val}: {e}")

    # Let's also test a Box prompt (simulate a bounding box around the bed area)
    # E.g. x1=0.2, y1=0.4, x2=0.8, y2=0.9
    x1, y1 = int(0.2 * w), int(0.4 * h)
    x2, y2 = int(0.8 * w), int(0.9 * h)
    print(f"\n--- Testing Box Prompt: [{x1}, {y1}, {x2}, {y2}] ---")
    try:
        results = model.predict(pil_image, bboxes=[[x1, y1, x2, y2]], conf=0.15, device="cpu")
        if results and len(results) > 0:
            result = results[0]
            if hasattr(result, "masks") and result.masks is not None and len(result.masks) > 0:
                print(f"Success! Masks found: {len(result.masks)}")
                mask_data = Math_mask = result.masks.data[0].numpy()
                mask_img = Image.fromarray((mask_data * 255).astype(np.uint8))
                mask_img.save("test_fastsam_bedroom_box.png")
            else:
                print("No masks found in box prompt result.")
    except Exception as e:
        print(f"Box prompt failed: {e}")

if __name__ == "__main__":
    main()
