import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import 'onboarding_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fabricCtrl;
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _fabricCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    // Run entrance animation then decide where to go
    _fabricCtrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      await _navigate();
    });
  }

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool(VastraConstants.onboardingDoneKey) ?? false;

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            onboardingDone ? const HomeScreen() : const OnboardingScreen(),
        transitionDuration: const Duration(milliseconds: 700),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fabricCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          // Background
          Container(decoration: const BoxDecoration(gradient: VastraTheme.deepGradient)),

          // Fabric wave background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _fabricCtrl,
              builder: (_, __) {
                return CustomPaint(
                  painter: _SplashFabricPainter(
                    progress: _fabricCtrl.value,
                    elapsed: _fabricCtrl.value * 3.0,
                  ),
                );
              },
            ),
          ),

          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gold V medallion
                AnimatedBuilder(
                  animation: _glowAnim,
                  builder: (_, child) => Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: VastraTheme.goldGradient,
                      boxShadow: [
                        BoxShadow(
                          color: VastraColors.gold
                              .withOpacity(0.45 + _glowAnim.value * 0.15),
                          blurRadius: 40 + _glowAnim.value * 15,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: VastraColors.terracotta
                              .withOpacity(0.20 + _glowAnim.value * 0.08),
                          blurRadius: 70,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'V',
                        style: TextStyle(
                          color: Color(0xFF1A0E05),
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.0, 0.0),
                      end: const Offset(1.0, 1.0),
                      duration: 900.ms,
                      curve: Curves.easeOutBack,
                    )
                    .fadeIn(duration: 700.ms),

                const SizedBox(height: 28),

                Text(
                  'VASTRA',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 34,
                        letterSpacing: 14,
                        color: VastraColors.ivory,
                        fontWeight: FontWeight.w700,
                      ),
                )
                    .animate(delay: 400.ms)
                    .fadeIn(duration: 600.ms)
                    .slideY(
                        begin: 0.2,
                        end: 0,
                        duration: 600.ms,
                        curve: Curves.easeOutCubic),

                const SizedBox(height: 12),

                Text(
                  'See your fabric in your room.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VastraColors.warmGray.withOpacity(0.6),
                        letterSpacing: 0.5,
                      ),
                )
                    .animate(delay: 700.ms)
                    .fadeIn(duration: 500.ms),
              ],
            ),
          ),

          // Bottom loading indicator
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 48,
                height: 3,
                child: LinearProgressIndicator(
                  backgroundColor: VastraColors.borderLight,
                  color: VastraColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ).animate(delay: 600.ms).fadeIn(duration: 400.ms),
          ),
        ],
      ),
    );
  }
}

// ── Splash Fabric Wave Painter ─────────────────────────────────────────────────

class _SplashFabricPainter extends CustomPainter {
  final double progress;
  final double elapsed;

  const _SplashFabricPainter({required this.progress, required this.elapsed});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.1) return;

    final opacity = (progress * 1.5).clamp(0.0, 1.0);

    for (int s = 0; s < 3; s++) {
      final yBase = size.height * (0.2 + s * 0.25);
      final amplitude = 20.0 + s * 8;
      final speed = 0.8 + s * 0.3;
      final color = [VastraColors.gold, VastraColors.terracotta, VastraColors.warmGray][s];

      final path = Path();
      for (int i = 0; i <= 80; i++) {
        final x = (i / 80) * size.width;
        final y = yBase + math.sin(elapsed * speed + x * 0.01 + s * 1.5) * amplitude;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withOpacity(0.06 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_SplashFabricPainter old) =>
      old.progress != progress || old.elapsed != elapsed;
}
