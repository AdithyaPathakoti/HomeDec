// This screen is superseded by FabricCatalogScreen.
// Kept as a stub to avoid breaking any legacy imports.
// The active navigation flow goes: ProductSelectionScreen → FabricCatalogScreen

import 'package:flutter/material.dart';
import 'fabric_catalog_screen.dart';

@Deprecated('Use FabricCatalogScreen instead')
class FabricUploadScreen extends StatelessWidget {
  const FabricUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Immediately redirect to the new catalog screen
    return const FabricCatalogScreen();
  }
}
