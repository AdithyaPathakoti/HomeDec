from huggingface_hub import HfApi
from gradio_client import Client

api = HfApi()
spaces_to_check = [
    "fffiloni/stable-diffusion-inpainting",
    "ysharma/gradio_sketching_inpainting_LaMa",
    "nightfury/SD-InPainting",
    "nielsr/text-based-inpainting",
    "ctei/stable-diffusion-inpainting",
    "flygomel/stable-diffusion-inpainting",
    "dskill/stable-diffusion-inpainting",
    "dskill/stable-diffusion-inpainting-2",
    "jjabrams/text-based-inpainting"
]

print("Checking space run states and Gradio connectivity...")
for space_id in spaces_to_check:
    try:
        runtime = api.get_space_runtime(space_id)
        print(f"Space: {space_id} | Stage: {runtime.stage}")
        if runtime.stage == "RUNNING":
            print(f"  --> Connecting via Gradio Client...")
            client = Client(space_id)
            print(f"  --> Connected successfully!")
            # Let's inspect the API to see if it's usable
            client.view_api()
            break  # Stop at the first working one
    except Exception as e:
        print(f"  --> Error with {space_id}: {e}")
