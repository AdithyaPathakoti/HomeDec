from gradio_client import Client

try:
    space_id = "ameerazam08/FLUX.1-dev-Inpainting-Model-Beta-GPU"
    print(f"Connecting to {space_id}...")
    client = Client(space_id)
    print("Connected successfully! Viewing API...")
    client.view_api()
except Exception as e:
    print("Error:", e)
