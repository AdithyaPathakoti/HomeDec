from gradio_client import Client, handle_file
from PIL import Image
import traceback

def test_sam2():
    client = Client('SkalskiP/segment-anything-model-2')
    
    img_path = "test_sam2_img.png"
    img = Image.new("RGB", (512, 512), "blue")
    img.save(img_path)
    
    try:
        prompter_input = {
            "image": handle_file(img_path),
            "points": [[256.0, 256.0, 1]]
        }
        
        result = client.predict(
            checkpoint_dropdown="tiny",
            mode_dropdown="point prompt", # wait, the options were box prompt or mask generation
            image_input=handle_file(img_path),
            image_prompter_input=prompter_input,
            api_name="/process_1"
        )
        print("Success! Result:", result)
    except Exception as e:
        print("Error:")
        traceback.print_exc()

if __name__ == "__main__":
    test_sam2()
