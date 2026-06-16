import 'dart:math';
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
  final List<Offset> _currentStrokePoints = [];
  final TransformationController _transformationController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onZoomChanged);
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

  @override
  void dispose() {
    _transformationController.removeListener(_onZoomChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.05;
    if (isZoomed != _isZoomed) {
      setState(() => _isZoomed = isZoomed);
    }
  }

  void _onCanvasTap(TapUpDetails details, BoxConstraints constraints) {
    final provider = context.read<VastraProvider>();
    if (provider.isProcessing) return;

    final localPosition = details.localPosition;

    // Check if the tap is close to an existing point to delete it
    int clickedPointIndex = -1;
    const double clickThreshold = 24.0; // logical pixels

    for (int i = 0; i < provider.interactivePoints.length; i++) {
      final pt = provider.interactivePoints[i];
      final double ptX = pt['x'] * constraints.maxWidth;
      final double ptY = pt['y'] * constraints.maxHeight;
      final double dx = localPosition.dx - ptX;
      final double dy = localPosition.dy - ptY;
      final double distance = sqrt(dx * dx + dy * dy);

      if (distance < clickThreshold) {
        clickedPointIndex = i;
        break;
      }
    }

    if (clickedPointIndex != -1) {
      provider.removeInteractiveTapAt(clickedPointIndex).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing point: $error'),
              backgroundColor: Colors.red[900],
            ),
          );
        }
      });
    } else {
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
                          Flexible(
                            child: _buildInteractiveCanvas(provider),
                          ),
                          const SizedBox(height: 12),
                          if (provider.interactivePoints.isNotEmpty)
                            Text(
                              '${provider.interactivePoints.length} point(s) placed • Tap a point to delete it',
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
          borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
          border: Border.all(color: VastraColors.borderLight),
        ),
        child: const Center(
          child: Text('No room image available', style: TextStyle(color: VastraColors.warmGray)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
        child: Center(
          child: AspectRatio(
            aspectRatio: provider.roomImageAspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1.0,
                  maxScale: 5.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: provider.isBrushMode ? null : (details) => _onCanvasTap(details, constraints),
                      onPanStart: provider.isBrushMode ? (details) {
                        setState(() {
                          _currentStrokePoints.clear();
                          _currentStrokePoints.add(details.localPosition);
                        });
                      } : null,
                      onPanUpdate: provider.isBrushMode ? (details) {
                        setState(() {
                          _currentStrokePoints.add(details.localPosition);
                        });
                      } : null,
                      onPanEnd: provider.isBrushMode ? (details) async {
                        if (_currentStrokePoints.isEmpty) return;
                        final pts = List<Offset>.from(_currentStrokePoints);
                        setState(() {
                          _currentStrokePoints.clear();
                        });
                        await provider.applyPaintStrokes(
                          pts,
                          provider.isBrushAdd,
                          provider.brushSize,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        await provider.uploadLocalMask();
                      } : null,
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

                          // Real-time brush stroke overlay
                          if (_currentStrokePoints.isNotEmpty)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: BrushStrokePainter(
                                  points: _currentStrokePoints,
                                  isAdd: provider.isBrushAdd,
                                  brushSize: provider.brushSize,
                                ),
                              ),
                            ),

                          // Interaction Coordinates / Dots
                          if (!provider.isBrushMode)
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

                          // Floating Reset Zoom indicator
                          if (_isZoomed)
                            Positioned(
                              right: 12,
                              top: 12,
                              child: GestureDetector(
                                onTap: () {
                                  _transformationController.value = Matrix4.identity();
                                  setState(() => _isZoomed = false);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: VastraColors.gold.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.zoom_out_map_rounded, size: 12, color: VastraColors.gold),
                                      SizedBox(width: 4),
                                      Text(
                                        'Reset Zoom',
                                        style: TextStyle(color: VastraColors.gold, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
    final hasPoints = provider.interactivePoints.isNotEmpty || provider.maskPreviewOverlay != null;

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
          if (provider.isBrushMode) ...[
            // Brush mode controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.brush_rounded, color: VastraColors.gold, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Brush Mode',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: VastraColors.ivory,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => provider.toggleBrushMode(),
                  icon: const Icon(Icons.touch_app_rounded, size: 14, color: VastraColors.gold),
                  label: const Text('Back to Taps', style: TextStyle(color: VastraColors.gold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add_circle_outline_rounded, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Brush Add', style: TextStyle(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  selected: provider.isBrushAdd,
                  onSelected: (_) => provider.setBrushAdd(true),
                  selectedColor: VastraColors.gold.withOpacity(0.25),
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: provider.isBrushAdd ? VastraColors.gold : VastraColors.borderLight,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.remove_circle_outline_rounded, size: 14, color: Colors.red),
                      SizedBox(width: 4),
                      Text('Brush Erase', style: TextStyle(fontSize: 12, color: Colors.white)),
                    ],
                  ),
                  selected: !provider.isBrushAdd,
                  onSelected: (_) => provider.setBrushAdd(false),
                  selectedColor: VastraColors.gold.withOpacity(0.25),
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: !provider.isBrushAdd ? VastraColors.gold : VastraColors.borderLight,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Size: ${provider.brushSize.round()}px',
                  style: const TextStyle(color: VastraColors.warmGray, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: provider.brushSize,
                    min: 5.0,
                    max: 60.0,
                    divisions: 11,
                    activeColor: VastraColors.gold,
                    inactiveColor: VastraColors.borderLight,
                    onChanged: (val) => provider.setBrushSize(val),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Row 1: Mode Switch & Reset (Wrapped to prevent overflow)
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Positive / Negative Toggle
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Tap Mode:',
                        style: TextStyle(
                          color: VastraColors.warmGray.withOpacity(0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: provider.isPositiveSelectionMode
                                ? VastraColors.gold
                                : VastraColors.borderLight,
                          ),
                        ),
                      ),
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
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: !provider.isPositiveSelectionMode
                                ? VastraColors.gold
                                : VastraColors.borderLight,
                          ),
                        ),
                      ),
                    ],
                  ),
    
                  // Undo & Reset Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (provider.maskPreviewOverlay != null) ...[
                        IconButton(
                          icon: const Icon(Icons.brush_rounded, color: VastraColors.gold),
                          tooltip: 'Paint Corrections',
                          onPressed: () => provider.toggleBrushMode(),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        icon: const Icon(Icons.undo_rounded, color: VastraColors.gold),
                        tooltip: 'Undo Last Tap',
                        onPressed: hasPoints && !provider.isProcessing
                            ? () => provider.undoLastTap().catchError((error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error performing undo: $error'),
                                      backgroundColor: Colors.red[900],
                                    ),
                                  );
                                }
                              })
                            : null,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: VastraColors.gold),
                        tooltip: 'Reset Taps',
                        onPressed: hasPoints && !provider.isProcessing
                            ? () {
                                provider.resetTaps();
                                _transformationController.value = Matrix4.identity();
                                setState(() => _isZoomed = false);
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

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

// ── Brush Stroke Painter ─────────────────────────────────────────────────────

class BrushStrokePainter extends CustomPainter {
  final List<Offset> points;
  final bool isAdd;
  final double brushSize;

  BrushStrokePainter({
    required this.points,
    required this.isAdd,
    required this.brushSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    
    final paint = Paint()
      ..color = isAdd ? Colors.green.withOpacity(0.55) : Colors.red.withOpacity(0.55)
      ..strokeWidth = brushSize
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    } else {
      canvas.drawCircle(
        points.first,
        brushSize / 2,
        Paint()..color = paint.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BrushStrokePainter oldDelegate) => true;
}
