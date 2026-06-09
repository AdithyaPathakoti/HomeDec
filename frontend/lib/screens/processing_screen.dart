import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import 'fabric_catalog_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize the room image upload session on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<VastraProvider>();
      if (provider.currentSessionId == null) {
        provider.uploadSessionImage().catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to initialize session: $error'),
                backgroundColor: Colors.red[900],
              ),
            );
          }
        });
      }
    });
  }

  void _onCanvasTap(TapUpDetails details, BoxConstraints constraints) {
    final provider = context.read<VastraProvider>();
    if (provider.isProcessing) return;

    final localPosition = details.localPosition;
    final normalizedX = localPosition.dx / constraints.maxWidth;
    final normalizedY = localPosition.dy / constraints.maxHeight;

    provider.addInteractiveTap(normalizedX, normalizedY).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Segmentation error: $error'),
            backgroundColor: Colors.red[900],
          ),
        );
      }
    });
  }

  void _onProceed() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const FabricCatalogScreen(),
        transitionDuration: VastraConstants.animationSlow,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VastraProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: VastraTheme.deepGradient,
            ),
          ),

          // Main Layout
          SafeArea(
            child: Column(
              children: [
                // Top Custom Header / Bar
                _buildHeader(context),

                // Interactive Workspace
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Tap the target object in your room to select it',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: VastraColors.gold,
                                  fontWeight: FontWeight.w500,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          _buildInteractiveCanvas(provider),
                          const SizedBox(height: 12),
                          if (provider.interactivePoints.isNotEmpty)
                            Text(
                              '${provider.interactivePoints.length} point(s) placed',
                              style: TextStyle(
                                color: VastraColors.warmGray.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            )
                          else
                            Text(
                              'E.g. Tap on your bedsheet or curtain to overlay fabrics',
                              style: TextStyle(
                                color: VastraColors.warmGray.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating Toolbar / Action Controls
                _buildControlToolbar(provider),
              ],
            ),
          ),

          // Loading Overlay
          if (provider.isProcessing) _buildLoadingOverlay(provider),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: VastraColors.ivory, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Text(
            'Interactive Canvas',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: VastraColors.ivory,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          // Custom step badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: VastraColors.gold.withOpacity(0.12),
              border: Border.all(color: VastraColors.gold.withOpacity(0.35)),
            ),
            child: const Text(
              'Step 2 of 3',
              style: TextStyle(
                color: VastraColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveCanvas(VastraProvider provider) {
    if (provider.roomImageBytes == null) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: VastraColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VastraColors.borderLight),
        ),
        child: const Center(
          child: Text('No room image available', style: TextStyle(color: VastraColors.warmGray)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: AspectRatio(
            aspectRatio: provider.roomImageAspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapUp: (details) => _onCanvasTap(details, constraints),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base Layer: Room image
                      Image.memory(
                        provider.roomImageBytes!,
                        fit: BoxFit.fill,
                      ),

                      // Overlay Layer: Mask preview
                      if (provider.maskPreviewOverlay != null)
                        Image.memory(
                          provider.maskPreviewOverlay!,
                          fit: BoxFit.fill,
                        ),

                      // Interaction Coordinates / Dots
                      ...provider.interactivePoints.map((pt) {
                        final double posX = pt['x'] * constraints.maxWidth;
                        final double posY = pt['y'] * constraints.maxHeight;
                        final bool isPositive = pt['label'] == 1;

                        return Positioned(
                          left: posX - 10,
                          top: posY - 10,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPositive ? Colors.green.withOpacity(0.85) : Colors.red.withOpacity(0.85),
                              border: Border.all(color: Colors.white, width: 2.0),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: Icon(
                              isPositive ? Icons.add : Icons.remove,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlToolbar(VastraProvider provider) {
    final hasPoints = provider.interactivePoints.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: VastraColors.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: VastraColors.borderLight, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Mode Switch & Reset
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Positive / Negative Toggle
              Row(
                children: [
                  Text(
                    'Tap Mode:',
                    style: TextStyle(
                      color: VastraColors.warmGray.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.add_circle_outline_rounded, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Add Zone', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ],
                    ),
                    selected: provider.isPositiveSelectionMode,
                    onSelected: (_) => provider.toggleSelectionMode(),
                    selectedColor: VastraColors.gold.withOpacity(0.25),
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: provider.isPositiveSelectionMode
                            ? VastraColors.gold
                            : VastraColors.borderLight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.remove_circle_outline_rounded, size: 14, color: Colors.red),
                        SizedBox(width: 4),
                        Text('Remove', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ],
                    ),
                    selected: !provider.isPositiveSelectionMode,
                    onSelected: (_) => provider.toggleSelectionMode(),
                    selectedColor: VastraColors.gold.withOpacity(0.25),
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: !provider.isPositiveSelectionMode
                            ? VastraColors.gold
                            : VastraColors.borderLight,
                      ),
                    ),
                  ),
                ],
              ),

              // Reset Button
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: VastraColors.gold),
                tooltip: 'Reset Taps',
                onPressed: hasPoints ? () => provider.resetTaps() : null,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 2: Action Button
          GestureDetector(
            onTap: hasPoints && !provider.isProcessing ? _onProceed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 56,
              decoration: hasPoints
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                      gradient: VastraTheme.goldGradient,
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.gold.withOpacity(0.40),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    )
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                      color: VastraColors.surface,
                      border: Border.all(color: VastraColors.borderLight),
                    ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_motion_rounded,
                    size: 20,
                    color: hasPoints ? VastraColors.textOnGold : VastraColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasPoints ? 'Proceed to Fabrics' : 'Tap Image to Start',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: hasPoints ? VastraColors.textOnGold : VastraColors.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay(VastraProvider provider) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VastraColors.gold,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              provider.statusMessage.isNotEmpty ? provider.statusMessage : 'Processing tap inputs...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VastraColors.warmGray,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
