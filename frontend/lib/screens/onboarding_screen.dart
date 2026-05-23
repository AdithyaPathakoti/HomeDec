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
      color: VastraColors.gold,
    ),
    _OnboardingPage(
      icon: Icons.texture_rounded,
      title: 'Pick Your Fabric',
      subtitle: 'Browse our curated fabric catalog — floral, velvet, silk, geometric, and more. Or upload your own swatch.',
      color: VastraColors.terracotta,
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      title: 'See It Come Alive',
      subtitle: 'Our 9-stage AI pipeline applies your chosen fabric to the exact object in your room with photorealistic lighting and depth.',
      color: Color(0xFF4CAF82),
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
        transitionDuration: const Duration(milliseconds: 600),
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
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: VastraTheme.deepGradient)),
          SafeArea(
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
                              color: VastraColors.warmGrayDark,
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

                // Page indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: 250.ms,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _currentPage
                            ? _pages[_currentPage].color
                            : VastraColors.ivory.withOpacity(0.12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // CTA button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VastraConstants.pagePadding),
                  child: GestureDetector(
                    onTap: () {
                      if (_currentPage < _pages.length - 1) {
                        _pageCtrl.nextPage(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                        );
                      } else {
                        _finish();
                      }
                    },
                    child: AnimatedContainer(
                      duration: 300.ms,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                        gradient: LinearGradient(
                          colors: [
                            _pages[_currentPage].color,
                            _pages[_currentPage].color.withOpacity(0.7),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _pages[_currentPage].color.withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _currentPage < _pages.length - 1 ? 'Next' : 'Start Visualizing',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: VastraColors.textOnGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
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
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon circle
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page.color.withOpacity(0.10),
              border: Border.all(color: page.color.withOpacity(0.30), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: page.color.withOpacity(0.20),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(page.icon, size: 46, color: page.color),
          )
              .animate(key: ValueKey(index))
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
                duration: 500.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 400.ms),

          const SizedBox(height: 36),

          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 24,
                  height: 1.3,
                ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('t$index'), delay: 100.ms)
              .fadeIn(duration: 450.ms)
              .slideY(begin: 0.2, end: 0, duration: 450.ms),

          const SizedBox(height: 16),

          Text(
            page.subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: VastraColors.textSecondary.withOpacity(0.8),
                  height: 1.7,
                ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('s$index'), delay: 200.ms)
              .fadeIn(duration: 450.ms),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
