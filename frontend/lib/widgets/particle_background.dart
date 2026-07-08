import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

// ── Particle data model ───────────────────────────────────────────────────────
class _Particle {
  final double startX; // 0.0–1.0 of screen width
  final double startY; // 0.0–1.0 of screen height
  final double speed; // screen-heights per second (upward drift)
  final double size; // radius in logical pixels
  final double opacity; // base opacity
  final double phase; // phase for sinusoidal horizontal drift
  final Color color;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.phase,
    required this.color,
  });

  factory _Particle.random(math.Random rng) {
    final colors = [
      VastraColors.gold,
      VastraColors.terracotta,
      VastraColors.warmGray,
      VastraColors.goldLight,
    ];
    return _Particle(
      startX: rng.nextDouble(),
      startY: rng.nextDouble(),
      speed: 0.025 + rng.nextDouble() * 0.045,
      size: 1.0 + rng.nextDouble() * 2.2,
      opacity: 0.06 + rng.nextDouble() * 0.18,
      phase: rng.nextDouble() * math.pi * 2,
      color: colors[rng.nextInt(colors.length)],
    );
  }

}

// ── Custom Painter ─────────────────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double elapsed; // seconds since start

  _ParticlePainter({required this.particles, required this.elapsed});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Y drifts upward: subtract speed * elapsed then wrap with modulo
      final rawY = p.startY - p.speed * elapsed;
      final yFrac = ((rawY % 1.0) + 1.0) % 1.0; // always [0, 1)

      // Gentle sinusoidal horizontal drift
      final xFrac = (p.startX +
              math.sin(elapsed * 0.6 + p.phase) * 0.02)
          .clamp(0.0, 1.0);

      // Opacity pulses slowly
      final opacity =
          p.opacity * (0.5 + 0.5 * math.sin(elapsed * 0.9 + p.phase));

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0.04, 0.85))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.9);

      canvas.drawCircle(
        Offset(xFrac * size.width, yFrac * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true; // always repaint while animating
}

// ── Widget ─────────────────────────────────────────────────────────────────────

/// Renders an animated floating-particle layer behind [child].
/// Uses [RepaintBoundary] so particle repaints do not dirty the rest of the tree.
class ParticleBackground extends StatefulWidget {
  final Widget child;

  const ParticleBackground({super.key, required this.child});

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late final List<_Particle> _particles;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Fixed seed gives a consistent initial spread across runs
    final rng = math.Random(37);
    _particles = List.generate(42, (_) => _Particle.random(rng));

    // The controller drives repaint at ~60 fps; it doesn't produce a value we use –
    // elapsed real-time comes from DateTime instead to avoid repeat-boundary jumps.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Isolated repaint boundary so particles don't trigger full tree repaints
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ticker,
            builder: (_, __) {
              final elapsed =
                  DateTime.now().difference(_startTime).inMilliseconds / 1000.0;
              return CustomPaint(
                painter: _ParticlePainter(
                  particles: _particles,
                  elapsed: elapsed,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
        widget.child,
      ],
    );
  }
}
