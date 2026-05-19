from gradio_client import Client, handle_file
from PIL import Image

def test_sam2_box():
    client = Client('SkalskiP/segment-anything-model-2')
    
    img_path = "test_sam2_img.png"
    img = Image.new("RGB", (512, 512), "blue")
    img.save(img_path)
    
    try:
        # Provide a box around the center
        prompter_input = {
            "image": handle_file(img_path),
            "points": [[200.0, 200.0, 2.0, 300.0, 300.0, 2.0]]
        }
        
        result = client.predict(
            checkpoint_dropdown="tiny",
            mode_dropdown="box prompt",
            image_input=handle_file(img_path),
            image_prompter_input=prompter_input,
            api_name="/process_1"
        )
        print("Success! Result:", result)
    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    test_sam2_box()
