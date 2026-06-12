import os
from pathlib import Path
from typing import Optional

def resolve_texture(texture_id: str) -> Optional[str]:
    """
    Resolves a fabric texture identifier (e.g. SKU, ID, or file name) 
    to a path on the local file system.

    Layers:
      1. Exact Asset Lookup: Checks if texture_id exists directly as a file in assets/fabrics/
      2. Future DB Lookup Placeholder: Hook for future metadata storage lookup
      3. Fallback Category Mapping: Maps missing SKUs (e.g. 'floral_rose') to closest matching base swatch
      4. Default Swatch: Returns a safe default swatch if no match is found
    """
    # Define search directory relative to backend execution directory
    fabric_dir = Path("assets/fabrics")

    # Layer 1: Exact Asset Lookup
    # Try direct filename check (e.g., if texture_id already has extension)
    direct = fabric_dir / texture_id
    if direct.is_file():
        return str(direct)

    # Try common image extensions
    for ext in [".jpg", ".jpeg", ".png", ".webp"]:
        candidate = fabric_dir / f"{texture_id}{ext}"
        if candidate.is_file():
            return str(candidate)

    # Layer 2: Future DB Lookup Placeholder
    # Placeholder to query texture metadata from a database, download from S3/blob,
    # or query cache before attempting generic mappings.
    db_metadata_path = None
    if db_metadata_path is not None:
        return db_metadata_path

    # Layer 3: Fallback Category Mapping (Substring SKUs to base swatches)
    tid = texture_id.lower()
    fallback_filename = None
    
    if any(k in tid for k in ["floral", "traditional", "printed", "cotton", "paisley", "rose", "blush", "terracotta"]):
        fallback_filename = "floral.jpg"
    elif any(k in tid for k in ["velvet", "stripe", "geometric", "textured", "herringbone", "navy", "emerald", "midnight", "azure", "desert"]):
        fallback_filename = "velvet.jpg"
    elif any(k in tid for k in ["silk", "luxury", "minimalist", "damask", "linen", "ivory", "white", "sage", "royal"]):
        fallback_filename = "luxury_white.jpg"

    if fallback_filename:
        candidate = fabric_dir / fallback_filename
        if candidate.is_file():
            print(f"[FabricRegistry] Texture '{texture_id}' fallback resolved to '{fallback_filename}'")
            return str(candidate)

    # Layer 4: Default Swatch
    default_swatch = "luxury_white.jpg"
    default_path = fabric_dir / default_swatch
    if default_path.is_file():
        print(f"[FabricRegistry] Texture '{texture_id}' unresolved. Defaulting to '{default_swatch}'")
        return str(default_path)

    # Final emergency fallback: First file in assets/fabrics
    all_files = list(fabric_dir.glob("*"))
    if all_files:
        print(f"[FabricRegistry] Texture '{texture_id}' unresolved. Final fallback to '{all_files[0].name}'")
        return str(all_files[0])

    return None
