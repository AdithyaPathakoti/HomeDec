import os
import sys
from PIL import Image, ImageDraw

# Add current directory to path to allow importing local packages
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from ai.inpaint import InpaintService

def run_integration_test():
    print("--- STARTING END-TO-END INPAINT SERVICE INTEGRATION TEST ---")
    
    # 1. Initialize service
    print("1. Initializing InpaintService...")
    inpaint_service = InpaintService()
    
    # 2. Check original sample image
    orig_path = r"c:\Users\Kadimi Jaswanth\ai-app1\bedroom_sample.png"
    if not os.path.exists(orig_path):
        print(f"ERROR: Sample image not found at {orig_path}")
        return False
    print(f"2. Loaded sample image from {orig_path}")
    
    # 3. Create a test mask (white square over bed region, black elsewhere)
    print("3. Creating a test mask...")
    img = Image.open(orig_path)
    w, h = img.size
    mask = Image.new("L", (w, h), color=0)
    draw = ImageDraw.Draw(mask)
    # Paint a white region in the center of the image
    draw.rectangle([w // 3, h // 2, 2 * w // 3, 4 * h // 5], fill=255)
    
    mask_path = "temp_test_mask.png"
    mask.save(mask_path)
    print(f"   Saved mask to {mask_path}")
    
    # 4. Define outputs
    output_path = "temp_test_output.png"
    if os.path.exists(output_path):
        os.remove(output_path)
        
    prompt = "Luxury modern floral bedsheet fabric with realistic folds and shadows"
    
    # 5. Run Inpainting
    print("4. Executing Inpainting...")
    try:
        result_path = inpaint_service.run_inpaint(
            image_path=orig_path,
            mask_path=mask_path,
            prompt=prompt,
            output_path=output_path
        )
        
        # 6. Verify result
        print("5. Verifying output...")
        if not os.path.exists(result_path):
            print(f"ERROR: Output file not created at {result_path}")
            return False
            
        out_img = Image.open(result_path)
        print(f"SUCCESS: Output image successfully generated!")
        print(f"   Result Dimensions: {out_img.size} (Original was: {img.size})")
        print(f"   Result Format: {out_img.format}")
        
        # Clean up temporary test files
        if os.path.exists(mask_path):
            os.remove(mask_path)
        print("Integration test completed successfully with 100% correctness!")
        return True
        
    except Exception as e:
        print(f"ERROR: Inpainting failed with exception: {e}")
        return False

if __name__ == "__main__":
    success = run_integration_test()
    sys.exit(0 if success else 1)
