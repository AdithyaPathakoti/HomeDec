import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/vastra_provider.dart';
import 'result_screen.dart';

// ── AI Animation Painter ────────────────────────────────────────────────────

class _AIAnimationPainter extends CustomPainter {
  final double elapsed; // seconds since animation start

  _AIAnimationPainter(this.elapsed);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Expanding pulse rings
    _drawPulseRings(canvas, cx, cy, cx * 0.85);

    // 2. Three concentric rotating rings (dashed arcs)
    _drawDashedRing(
      canvas, cx, cy,
      radius: cx * 0.70,
      strokeWidth: 1.2,
      rotation: elapsed * 0.45,
      dashCount: 24,
      color: VastraColors.purpleAccent.withOpacity(0.45),
    );
    _drawDashedRing(
      canvas, cx, cy,
      radius: cx * 0.52,
      strokeWidth: 1.8,
      rotation: -elapsed * 0.80,
      dashCount: 14,
      color: VastraColors.purpleNeon.withOpacity(0.60),
    );
    _drawDashedRing(
      canvas, cx, cy,
      radius: cx * 0.34,
      strokeWidth: 2.4,
      rotation: elapsed * 1.20,
      dashCount: 8,
      color: VastraColors.purpleGlow.withOpacity(0.75),
    );

    // 3. Laser sweep
    _drawLaserSweep(canvas, cx, cy, cx * 0.70);

    // 4. Data nodes on rings
    _drawRingNodes(canvas, cx, cy, cx * 0.70, elapsed * 0.45, 6);
    _drawRingNodes(canvas, cx, cy, cx * 0.52, -elapsed * 0.80, 4);
    _drawRingNodes(canvas, cx, cy, cx * 0.34, elapsed * 1.20, 3);

    // 5. Neural-network connecting lines
    _drawNeuralLines(canvas, cx, cy);

    // 6. Center glow + core dot
    _drawCenter(canvas, cx, cy);
  }

  void _drawPulseRings(Canvas canvas, double cx, double cy, double maxR) {
    for (int i = 0; i < 4; i++) {
      final progress = ((elapsed * 0.45 + i * 0.25) % 1.0);
      final r = progress * maxR;
      final opacity = (1.0 - progress) * 0.22;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = VastraColors.purpleNeon.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawDashedRing(
    Canvas canvas,
    double cx,
    double cy, {
    required double radius,
    required double strokeWidth,
    required double rotation,
    required int dashCount,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final dashAngle = (math.pi * 2) / dashCount;
    const gapFraction = 0.38;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = rotation + i * dashAngle;
      final sweep = dashAngle * (1.0 - gapFraction);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  void _drawLaserSweep(Canvas canvas, double cx, double cy, double radius) {
    final angle = elapsed * 1.8; // radians/sec

    // Filled pie slice with gradient
    final sweepGrad = SweepGradient(
      colors: [
        VastraColors.purpleNeon.withOpacity(0.0),
        VastraColors.purpleNeon.withOpacity(0.55),
        VastraColors.purpleNeon.withOpacity(0.0),
      ],
      stops: const [0.0, 0.04, 0.12],
      transform: GradientRotation(angle),
    );

    final path = Path()
      ..moveTo(cx, cy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        angle - 0.25,
        0.5,
        false,
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = sweepGrad
            .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius)),
    );

    // Bright leading edge line
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + math.cos(angle) * radius, cy + math.sin(angle) * radius),
      Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  void _drawRingNodes(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double rotation,
    int count,
  ) {
    for (int i = 0; i < count; i++) {
      final a = rotation + (math.pi * 2 * i / count);
      final x = cx + math.cos(a) * radius;
      final y = cy + math.sin(a) * radius;
      canvas.drawCircle(
        Offset(x, y),
        3.5,
        Paint()
          ..color = Colors.white.withOpacity(0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _drawNeuralLines(Canvas canvas, double cx, double cy) {
    // Connect random-but-stable points with faint lines to simulate neural net
    final rng = math.Random(12);
    final pts = List.generate(
      8,
      (_) => Offset(
        cx + (rng.nextDouble() - 0.5) * cx * 1.4,
        cy + (rng.nextDouble() - 0.5) * cy * 1.4,
      ),
    );

    final t = elapsed * 0.5;
    for (int i = 0; i < pts.length; i++) {
      for (int j = i + 1; j < pts.length; j++) {
        final opacity =
            0.06 + 0.06 * math.sin(t + i * 0.7 + j * 0.3);
        canvas.drawLine(
          pts[i],
          pts[j],
          Paint()
            ..color = VastraColors.purpleAccent.withOpacity(opacity)
            ..strokeWidth = 0.6,
        );
      }
      // Small dot at each node
      canvas.drawCircle(
        pts[i],
        2,
        Paint()
          ..color = VastraColors.purpleGlow.withOpacity(
              0.2 + 0.15 * math.sin(t + i)),
      );
    }
  }

  void _drawCenter(Canvas canvas, double cx, double cy) {
    final pulse = 0.5 + 0.5 * math.sin(elapsed * 2.2);

    // Outer ambient glow
    canvas.drawCircle(
      Offset(cx, cy),
      32 + pulse * 10,
      Paint()
        ..color = VastraColors.purpleNeon.withOpacity(0.12 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Inner glow ring
    canvas.drawCircle(
      Offset(cx, cy),
      14 + pulse * 4,
      Paint()
        ..color = VastraColors.purpleAccent.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Core bright dot
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()
        ..color = Colors.white.withOpacity(0.92)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_AIAnimationPainter old) => old.elapsed != elapsed;
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
  late final AnimationController _textFadeCtrl;
  late final Animation<double> _textFadeAnim;

  final DateTime _startTime = DateTime.now();

  static const List<String> _messages = [
    'Analyzing room geometry...',
    'Detecting target object...',
    'Understanding spatial layout...',
    'Segmenting selected region...',
    'Extracting fabric texture...',
    'Applying perspective transform...',
    'Matching room lighting...',
    'Preserving shadows & depth...',
    'Blending fabric naturally...',
    'Finalizing your design...',
  ];

  int _msgIndex = 0;
  Timer? _msgTimer;

  @override
  void initState() {
    super.initState();

    // Drives repaints at ~60 fps without using the value itself
    _repaintTicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();

    _textFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _textFadeAnim =
        CurvedAnimation(parent: _textFadeCtrl, curve: Curves.easeInOut);

    // Cycle messages with fade
    _msgTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      _textFadeCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
        _textFadeCtrl.forward();
      });
    });

    // Kick off actual generation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGeneration());
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
          // Background gradient
          Container(
            decoration: const BoxDecoration(gradient: VastraTheme.deepGradient),
          ),

          // Ambient top glow
          Positioned(
            top: -120,
            left: size.width / 2 - 150,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    VastraColors.purpleAccent.withOpacity(0.18),
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

                // Animation canvas
                Expanded(
                  flex: 5,
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvasSize = math.min(
                          constraints.maxWidth * 0.88,
                          constraints.maxHeight,
                        );
                        return RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _repaintTicker,
                            builder: (_, __) {
                              final elapsed = DateTime.now()
                                      .difference(_startTime)
                                      .inMilliseconds /
                                  1000.0;
                              return CustomPaint(
                                painter: _AIAnimationPainter(elapsed),
                                size: Size(canvasSize, canvasSize),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Title
                Text(
                  'AI Processing',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        letterSpacing: 0.5,
                      ),
                ),

                const SizedBox(height: 10),

                // Cycling status message
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48),
                  child: FadeTransition(
                    opacity: _textFadeAnim,
                    child: Text(
                      _messages[_msgIndex],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VastraColors.purpleNeon,
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
                      width: i == _msgIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _msgIndex
                            ? VastraColors.purpleNeon
                            : Colors.white.withOpacity(0.15),
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
