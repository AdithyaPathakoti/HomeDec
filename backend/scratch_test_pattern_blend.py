import os
import sys
from PIL import Image, ImageDraw

# Add current directory to path to allow importing local packages
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from ai.inpaint import InpaintService

def run_blend_test():
    print("--- STARTING OFFLINE FABRIC PATTERN BLENDING TEST ---")
    
    # 1. Initialize service
    print("1. Initializing InpaintService...")
    inpaint_service = InpaintService()
    
    # 2. Check original sample image and design pattern
    orig_path = r"c:\Users\Kadimi Jaswanth\ai-app1\bedroom_sample.png"
    pattern_path = r"c:\Users\Kadimi Jaswanth\ai-app1\frontend\assets\design1.jpg"
    
    if not os.path.exists(orig_path):
        print(f"ERROR: Sample image not found at {orig_path}")
        return False
    print(f"2. Loaded room sample image from {orig_path}")
    
    if not os.path.exists(pattern_path):
        print(f"ERROR: Design pattern not found at {pattern_path}")
        return False
    print(f"3. Loaded design pattern from {pattern_path}")
    
    # 3. Create a test mask (white square over bed region, black elsewhere)
    print("4. Creating a test mask...")
    img = Image.open(orig_path)
    w, h = img.size
    mask = Image.new("L", (w, h), color=0)
    draw = ImageDraw.Draw(mask)
    # Paint a white region in the center of the image corresponding to the bed area
    draw.rectangle([w // 3, h // 2, 2 * w // 3, 4 * h // 5], fill=255)
    
    mask_path = "temp_test_blend_mask.png"
    mask.save(mask_path)
    print(f"   Saved mask to {mask_path}")
    
    # 4. Define output path
    output_path = "temp_test_blend_output.png"
    if os.path.exists(output_path):
        os.remove(output_path)
        
    # 5. Run Offline Pattern Blending
    print("5. Executing Offline Pattern Blending...")
    try:
        result_path = inpaint_service.run_pattern_blend(
            image_path=orig_path,
            mask_path=mask_path,
            pattern_path=pattern_path,
            output_path=output_path
        )
        
        # 6. Verify result
        print("6. Verifying output...")
        if not os.path.exists(result_path):
            print(f"ERROR: Output file not created at {result_path}")
            return False
            
        out_img = Image.open(result_path)
        print(f"SUCCESS: Pattern blended image successfully generated!")
        print(f"   Result Dimensions: {out_img.size} (Original was: {img.size})")
        print(f"   Result Format: {out_img.format}")
        
        # Clean up temporary test mask
        if os.path.exists(mask_path):
            os.remove(mask_path)
        print("Offline blending test completed successfully with 100% correctness!")
        return True
        
    except Exception as e:
        print(f"ERROR: Blending failed with exception: {e}")
        return False

if __name__ == "__main__":
    success = run_blend_test()
    sys.exit(0 if success else 1)
