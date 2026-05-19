from gradio_client import Client, handle_file
from PIL import Image
import os

try:
    print("Initializing client...")
    client = Client("diffusers/stable-diffusion-xl-inpainting")
    
    # 1. Load the original sample image in the workspace
    orig_path = r"c:\Users\Kadimi Jaswanth\ai-app1\bedroom_sample.png"
    if not os.path.exists(orig_path):
        print(f"Sample image not found at {orig_path}")
        # Create a tiny dummy image if not exists
        img = Image.new("RGB", (512, 512), color="blue")
        orig_path = "dummy_orig.png"
        img.save(orig_path)
    else:
        print(f"Using original sample image: {orig_path}")
        img = Image.open(orig_path)
        
    # 2. Create a test mask (a white rectangle in the center on a black background)
    mask = Image.new("L", img.size, color=0)
    w, h = img.size
    # Paint a white square in the center (where the bed sheet or curtain might be)
    from PIL import ImageDraw
    draw = ImageDraw.Draw(mask)
    draw.rectangle([w // 4, h // 4, 3 * w // 4, 3 * h // 4], fill=255)
    
    mask_path = "test_mask.png"
    mask.save(mask_path)
    print(f"Created test mask: {mask_path}")
    
    # 3. Call predict
    print("Calling predict endpoint on SDXL space...")
    
    # Structure of Imageeditor under Gradio:
    # background is the original image, layers is a list containing the mask
    input_image_data = {
        "background": handle_file(orig_path),
        "layers": [handle_file(mask_path)],
        "composite": None
    }
    
    result = client.predict(
        input_image=input_image_data,
        prompt="Emerald green luxury velvet fabric, realistic bedsheet folds and texture",
        negative_prompt="poorly drawn, distorted, low resolution, ugly, bad lighting",
        guidance_scale=7.5,
        steps=20,
        strength=0.99,
        scheduler="EulerDiscreteScheduler",
        api_name="/predict"
    )
    
    print("Success! Prediction output:")
    print(result)
    
    # If successful, let's see where the output image is stored
    if result:
        print("Result details:")
        for idx, item in enumerate(result):
            if item:
                print(f"Item {idx}: {item.get('path')} | URL: {item.get('url')}")
except Exception as e:
    print("Error during execution:", e)
