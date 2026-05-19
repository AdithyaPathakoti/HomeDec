from gradio_client import Client, handle_file
from PIL import Image
import os
import json

def test_sam2():
    print("Testing SAM2 API...")
    client = Client('SkalskiP/segment-anything-model-2')
    
    # Create a dummy image
    img_path = "test_sam2_img.png"
    img = Image.new("RGB", (512, 512), "blue")
    img.save(img_path)
    
    try:
        # According to the API view:
        # image_prompter_input: Dict(image: filepath, points: List[List[float]])
        # Let's pass a point in the middle
        prompter_input = {
            "image": handle_file(img_path),
            "points": [[256.0, 256.0, 1.0]]  # x, y, label (1 for foreground)
        }
        
        result = client.predict(
            checkpoint_dropdown="tiny",
            mode_dropdown="box prompt",
            image_input=handle_file(img_path),
            image_prompter_input=prompter_input,
            api_name="/process_1"
        )
        print("Success! Result:")
        print(result)
    except Exception as e:
        print("Error:")
        print(e)

if __name__ == "__main__":
    test_sam2()
