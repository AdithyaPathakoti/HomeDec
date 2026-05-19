from gradio_client import Client

try:
    print("Connecting to diffusers/stable-diffusion-xl-inpainting...")
    client = Client("diffusers/stable-diffusion-xl-inpainting")
    print("Connected successfully! Viewing API...")
    client.view_api()
except Exception as e:
    print("Error:", e)
