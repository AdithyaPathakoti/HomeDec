import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.camera_alt_rounded,
      title: 'Photograph Your Room',
      subtitle: 'Take or upload a photo of any room in your home — bedroom, living room, or anywhere you want to redesign.',
    ),
    _OnboardingPage(
      icon: Icons.texture_rounded,
      title: 'Pick Your Fabric',
      subtitle: 'Browse our curated fabric catalog — floral, velvet, silk, geometric, and more. Or upload your own swatch.',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      title: 'See It Come Alive',
      subtitle: 'Our 9-stage AI pipeline applies your chosen fabric to the exact object in your room with photorealistic lighting and depth.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(VastraConstants.onboardingDoneKey, true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VastraColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 24, 0),
                child: GestureDetector(
                  onTap: _finish,
                  child: Text(
                    'Skip',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: VastraColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _buildPage(_pages[i], i),
              ),
            ),

            // Page indicators (Shadcn style monochrome)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: 200.ms,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentPage ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _currentPage
                        ? VastraColors.ivory
                        : VastraColors.ivory.withOpacity(0.2),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // CTA button (Shadcn style primary white button)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VastraConstants.pagePadding),
              child: GestureDetector(
                onTap: () {
                  if (_currentPage < _pages.length - 1) {
                    _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                    );
                  } else {
                    _finish();
                  }
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: VastraColors.ivory,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _currentPage < _pages.length - 1 ? 'Next' : 'Start Visualizing',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: VastraColors.background,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon Container (Shadcn Card style)
          Container(
            width: 96,
            height: 96,
            decoration: VastraTheme.glassDecoration(borderRadius: 12),
            child: Icon(page.icon, size: 36, color: VastraColors.ivory)
                .animate(key: ValueKey(index))
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.0, 1.0),
                  duration: 300.ms,
                  curve: Curves.easeOutCubic,
                )
                .fadeIn(duration: 250.ms),
          ),

          const SizedBox(height: 36),

          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: VastraColors.textPrimary,
                ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('t$index'))
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.1, end: 0, duration: 300.ms),

          const SizedBox(height: 16),

          Text(
            page.subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: VastraColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('s$index'))
              .fadeIn(duration: 350.ms),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String subtitle;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
