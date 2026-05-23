import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/vastra_provider.dart';
import 'result_screen.dart';

// ── Fabric Ripple Loader — Signature Feature C1 ──────────────────────────────
//
// A waving cloth simulation rendered on Flutter Canvas.
// The fabric colors are extracted from the uploaded fabric swatch.
// Three overlapping sine-wave cloth strips create a 3D draping illusion.

class _FabricRipplePainter extends CustomPainter {
  final double elapsed; // seconds
  final List<Color> fabricColors;
  final double shimmerPhase;

  _FabricRipplePainter({
    required this.elapsed,
    required this.fabricColors,
    required this.shimmerPhase,
  });

  Color get _c1 => fabricColors.isNotEmpty ? fabricColors[0] : VastraColors.gold;
  Color get _c2 => fabricColors.length > 1 ? fabricColors[1] : VastraColors.terracotta;
  Color get _c3 => fabricColors.length > 2 ? fabricColors[2] : VastraColors.warmGray;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Background glow ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [
            _c1.withOpacity(0.07),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Draw 3 cloth strips ──
    _drawClothStrip(canvas, size, strip: 0, yOffset: 0.25, amplitude: 18, speed: 1.0, color: _c1);
    _drawClothStrip(canvas, size, strip: 1, yOffset: 0.45, amplitude: 22, speed: 0.7, color: _c2);
    _drawClothStrip(canvas, size, strip: 2, yOffset: 0.65, amplitude: 16, speed: 1.3, color: _c3);

    // ── Warp thread lines (vertical) ──
    _drawWarpThreads(canvas, size);

    // ── Gold shimmer scan line ──
    _drawShimmerLine(canvas, size);

    // ── Center weave indicator ──
    _drawCenterIndicator(canvas, size);
  }

  void _drawClothStrip(
    Canvas canvas,
    Size size, {
    required int strip,
    required double yOffset,
    required double amplitude,
    required double speed,
    required Color color,
  }) {
    final w = size.width;
    final h = size.height;
    final centerY = h * yOffset;
    final stripH = h * 0.14;
    const numPoints = 80;

    final topPath = Path();
    final bottomPath = Path();

    for (int i = 0; i <= numPoints; i++) {
      final x = (i / numPoints) * w;
      final phase = elapsed * speed + strip * 1.2 + x * 0.012;
      final wave = math.sin(phase) * amplitude +
          math.sin(phase * 1.6 + 0.8) * (amplitude * 0.4);
      final foldDepth = math.cos(phase * 0.7) * (stripH * 0.08);

      final ty = centerY - stripH * 0.5 + wave + foldDepth;
      final by = centerY + stripH * 0.5 + wave * 0.6 - foldDepth;

      if (i == 0) {
        topPath.moveTo(x, ty);
        bottomPath.moveTo(x, by);
      } else {
        topPath.lineTo(x, ty);
        bottomPath.lineTo(x, by);
      }
    }

    // Build closed cloth shape
    final clothPath = Path()
      ..addPath(topPath, Offset.zero);
    // Trace bottom path in reverse
    for (int i = numPoints; i >= 0; i--) {
      final x = (i / numPoints) * w;
      final phase = elapsed * speed + strip * 1.2 + x * 0.012;
      final wave = math.sin(phase) * amplitude +
          math.sin(phase * 1.6 + 0.8) * (amplitude * 0.4);
      final foldDepth = math.cos(phase * 0.7) * (stripH * 0.08);
      final by = centerY + stripH * 0.5 + wave * 0.6 - foldDepth;
      clothPath.lineTo(x, by);
    }
    clothPath.close();

    // Fill with fabric gradient
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.85),
        color.withOpacity(0.55),
        color.withOpacity(0.80),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    canvas.drawPath(
      clothPath,
      Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, centerY - stripH, w, stripH * 2),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );

    // Highlight edge line (top of cloth)
    canvas.drawPath(
      topPath,
      Paint()
        ..color = color.withOpacity(0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Shadow edge (bottom of cloth)
    canvas.drawPath(
      bottomPath,
      Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawWarpThreads(Canvas canvas, Size size) {
    const threadCount = 32;
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < threadCount; i++) {
      final x = (i / threadCount) * w;
      final opacity = 0.05 + 0.04 * math.sin(elapsed * 0.8 + i * 0.3);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..color = VastraColors.ivory.withOpacity(opacity)
          ..strokeWidth = 0.5,
      );
    }
  }

  void _drawShimmerLine(Canvas canvas, Size size) {
    // A diagonal shimmer line that sweeps across the cloth
    final x = (shimmerPhase % 1.0) * size.width * 1.4 - size.width * 0.2;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.transparent,
        VastraColors.goldLight.withOpacity(0.55),
        Colors.white.withOpacity(0.45),
        VastraColors.goldLight.withOpacity(0.55),
        Colors.transparent,
      ],
      stops: const [0.0, 0.45, 0.5, 0.55, 1.0],
    );

    canvas.save();
    canvas.translate(x, 0);
    canvas.skew(-0.3, 0); // diagonal slant
    canvas.drawRect(
      Rect.fromLTWH(-30, 0, 60, size.height),
      Paint()
        ..shader = gradient.createShader(Rect.fromLTWH(-30, 0, 60, size.height))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.restore();
  }

  void _drawCenterIndicator(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.45;
    final pulse = 0.5 + 0.5 * math.sin(elapsed * 2.5);

    // Outer glow ring
    canvas.drawCircle(
      Offset(cx, cy),
      28 + pulse * 6,
      Paint()
        ..color = VastraColors.gold.withOpacity(0.08 + pulse * 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Ring
    canvas.drawCircle(
      Offset(cx, cy),
      16 + pulse * 3,
      Paint()
        ..color = VastraColors.gold.withOpacity(0.5 + pulse * 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Core gold dot
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()..color = VastraColors.gold.withOpacity(0.9),
    );
  }

  @override
  bool shouldRepaint(_FabricRipplePainter old) =>
      old.elapsed != elapsed || old.shimmerPhase != shimmerPhase;
}

// ── Processing Screen ─────────────────────────────────────────────────────────

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _repaintTicker;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _textFadeCtrl;
  late final Animation<double> _textFadeAnim;

  final DateTime _startTime = DateTime.now();

  // Fabric colors extracted from the uploaded swatch
  List<Color> _fabricColors = [VastraColors.gold, VastraColors.terracotta, VastraColors.warmGray];

  static const List<String> _messages = [
    'Reading room geometry...',
    'Detecting target object...',
    'Understanding spatial depth...',
    'Segmenting fabric region...',
    'Extracting fabric texture...',
    'Applying perspective transform...',
    'Matching room lighting...',
    'Preserving shadows & depth...',
    'Weaving your fabric in...',
    'Finalizing your design...',
  ];

  int _msgIndex = 0;
  Timer? _msgTimer;

  @override
  void initState() {
    super.initState();

    _repaintTicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _textFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _textFadeAnim = CurvedAnimation(parent: _textFadeCtrl, curve: Curves.easeInOut);

    _msgTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted) return;
      _textFadeCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
        _textFadeCtrl.forward();
      });
    });

    // Extract fabric colors from the uploaded fabric image
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extractFabricColors();
      _runGeneration();
    });
  }

  void _extractFabricColors() {
    final provider = context.read<VastraProvider>();
    final bytes = provider.fabricImageBytes;
    if (bytes == null) return;

    // Sample a few pixel regions to get dominant colors
    try {
      final colors = _sampleDominantColors(bytes);
      if (mounted && colors.isNotEmpty) {
        setState(() => _fabricColors = colors);
      }
    } catch (_) {
      // Keep defaults
    }
  }

  List<Color> _sampleDominantColors(Uint8List bytes) {
    // Quick sampling — every ~1000th byte interpreted as RGBA groups
    // For production, use image package for proper histogram analysis
    if (bytes.length < 12) return [];
    final results = <Color>[];
    final step = (bytes.length / 4).floor();
    for (int i = 0; i < 4 && i * step + 3 < bytes.length; i++) {
      final offset = i * step;
      final r = bytes[offset];
      final g = bytes[offset + 1];
      final b = bytes[offset + 2];
      results.add(Color.fromARGB(255, r, g, b));
    }
    return results.isNotEmpty ? results : [VastraColors.gold];
  }

  Future<void> _runGeneration() async {
    final provider = context.read<VastraProvider>();
    await provider.generate();
    if (!mounted) return;

    _msgTimer?.cancel();

    if (provider.status == ProcessingStatus.done) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ResultScreen(),
          transitionDuration: const Duration(milliseconds: 900),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
            child: child,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${provider.errorMessage ?? "Generation failed. Please try again."}',
          ),
          backgroundColor: Colors.red[900],
          duration: const Duration(seconds: 5),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _repaintTicker.dispose();
    _shimmerCtrl.dispose();
    _textFadeCtrl.dispose();
    _msgTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: VastraTheme.deepGradient)),

          // Ambient top glow in fabric color
          Positioned(
            top: -120,
            left: size.width / 2 - 160,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _fabricColors.first.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 1),

                // Fabric ripple canvas
                Expanded(
                  flex: 5,
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvasW = constraints.maxWidth * 0.90;
                        final canvasH = math.min(constraints.maxHeight, canvasW * 0.70);
                        return RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_repaintTicker, _shimmerCtrl]),
                            builder: (_, __) {
                              final elapsed = DateTime.now()
                                      .difference(_startTime)
                                      .inMilliseconds /
                                  1000.0;
                              return CustomPaint(
                                painter: _FabricRipplePainter(
                                  elapsed: elapsed,
                                  fabricColors: _fabricColors,
                                  shimmerPhase: _shimmerCtrl.value,
                                ),
                                size: Size(canvasW, canvasH),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Title
                Text(
                  'Weaving Your Design',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        letterSpacing: 0.3,
                        color: VastraColors.ivory,
                      ),
                ),

                const SizedBox(height: 10),

                // Status message
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: FadeTransition(
                    opacity: _textFadeAnim,
                    child: Text(
                      _messages[_msgIndex],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VastraColors.gold,
                            fontWeight: FontWeight.w500,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Progress dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _messages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _msgIndex ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _msgIndex
                            ? VastraColors.gold
                            : VastraColors.ivory.withOpacity(0.12),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
