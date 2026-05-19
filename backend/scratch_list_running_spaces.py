from huggingface_hub import HfApi

api = HfApi()
try:
    print("Searching for spaces containing 'inpainting'...")
    # List a larger number of spaces to find active ones
    spaces = api.list_spaces(search="inpainting", limit=100)
    running_spaces = []
    for space in spaces:
        try:
            runtime = api.get_space_runtime(space.id)
            if runtime.stage == "RUNNING" and space.sdk == "gradio":
                running_spaces.append(space.id)
                print(f"RUNNING Space: {space.id} | SDK: {space.sdk}")
        except Exception:
            pass
            
    print(f"\nFound {len(running_spaces)} running Gradio spaces:")
    print(running_spaces)
except Exception as e:
    print("Error listing spaces:", e)
