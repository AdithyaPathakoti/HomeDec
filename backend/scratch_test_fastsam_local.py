import os
from PIL import Image
import numpy as np
from ultralytics import FastSAM
from ultralytics.models.fastsam import FastSAMPrompt

def main():
    print("Initializing local FastSAM model...")
    # Load model (downloads FastSAM-s.pt if not present)
    model = FastSAM("FastSAM-s.pt")
    
    img_path = "test_sam2_img.png"
    if not os.path.exists(img_path):
        # Create a dummy test image if it doesn't exist
        print(f"Creating a dummy test image {img_path}...")
        img = Image.new("RGB", (512, 512), color="blue")
        img.save(img_path)
        
    print(f"Running inference on {img_path}...")
    results = model(img_path, device="cpu")
    
    print("Initializing FastSAMPrompt...")
    prompt_process = FastSAMPrompt(img_path, results, device="cpu")
    
    # Bbox prompt test (box around center)
    print("Testing bbox prompt...")
    # bbox format: [x1, y1, x2, y2]
    ann = prompt_process.box_prompt(bboxes=[[128, 128, 384, 384]])
    
    print(f"Prompt output type: {type(ann)}")
    
    # Let's see what is inside results[0].masks
    if results and len(results) > 0:
        result = results[0]
        if hasattr(result, "masks") and result.masks is not None:
            print(f"Found {len(result.masks)} masks in result.")
            print(f"Mask shape: {result.masks.data.shape}")
        else:
            print("No masks found in result.")
            
    # Let's inspect the returned prompt annotations
    # FastSAMPrompt's box_prompt or point_prompt returns a results object or similar list
    print("Successfully ran local FastSAM test!")

if __name__ == "__main__":
    main()
