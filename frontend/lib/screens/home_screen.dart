import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import '../widgets/particle_background.dart';
import '../widgets/animated_glow_button.dart';
import 'product_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _blobCtrl;
  late final Animation<double> _blobAnim;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _blobAnim = CurvedAnimation(parent: _blobCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    super.dispose();
  }

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    if (_isLoading) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: VastraConstants.maxImageDimension.toDouble(),
        maxHeight: VastraConstants.maxImageDimension.toDouble(),
        imageQuality: VastraConstants.imageQuality,
      );

      if (picked == null || !mounted) return;

      setState(() => _isLoading = true);
      final bytes = await picked.readAsBytes();

      if (!mounted) return;
      setState(() => _isLoading = false);

      context.read<VastraProvider>().setRoomImage(bytes);

      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ProductSelectionScreen(),
          transitionDuration: VastraConstants.animationSlow,
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.08),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not access image: $e'),
          backgroundColor: Colors.red[900],
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VastraColors.background,
      body: ParticleBackground(
        child: Stack(
          children: [
            // Animated gradient ambient blobs
            _buildAmbientBlobs(),

            // Main content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: VastraConstants.pagePadding),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _buildLogo(),
                    const SizedBox(height: 22),
                    _buildSubtitle(),
                    const Spacer(flex: 3),
                    _buildButtons(),
                    const SizedBox(height: 28),
                    _buildFooter(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),

            // Loading overlay
            if (_isLoading) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Sub-builders ───────────────────────────────────────────────────────────

  Widget _buildAmbientBlobs() {
    return AnimatedBuilder(
      animation: _blobAnim,
      builder: (_, __) {
        final t = _blobAnim.value;
        return Stack(
          children: [
            Positioned(
              top: -90 + t * 25,
              left: -90 + t * 12,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      VastraColors.purpleAccent.withOpacity(0.13),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -110 + t * 18,
              right: -80,
              child: Container(
                width: 270,
                height: 270,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      VastraColors.purpleNeon.withOpacity(0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4 + t * 10,
              left: MediaQuery.of(context).size.width * 0.5 - 80,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      VastraColors.indigo.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // V glyph mark
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: VastraTheme.purpleGradient,
            boxShadow: [
              BoxShadow(
                color: VastraColors.purpleAccent.withOpacity(0.55),
                blurRadius: 32,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: VastraColors.purpleNeon.withOpacity(0.25),
                blurRadius: 60,
                spreadRadius: 8,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'V',
              style: TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        )
            .animate()
            .scale(
              begin: const Offset(0.4, 0.4),
              end: const Offset(1.0, 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: const Duration(milliseconds: 500)),

        const SizedBox(height: 22),

        // Wordmark
        Text(
          'VASTRA',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 30,
                letterSpacing: 11,
              ),
        )
            .animate(delay: const Duration(milliseconds: 300))
            .fadeIn(duration: const Duration(milliseconds: 600))
            .slideY(
              begin: 0.3,
              end: 0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
            ),

        const SizedBox(height: 10),

        // Decorative divider
        Container(
          width: 56,
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                VastraColors.purpleNeon,
                Colors.transparent,
              ],
            ),
          ),
        )
            .animate(delay: const Duration(milliseconds: 600))
            .scaleX(
              begin: 0,
              end: 1,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            ),
      ],
    );
  }

  Widget _buildSubtitle() {
    return Column(
      children: [
        Text(
          'AI Interior Fabric Visualizer',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: VastraColors.purpleNeon,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
              ),
          textAlign: TextAlign.center,
        )
            .animate(delay: const Duration(milliseconds: 750))
            .fadeIn(duration: const Duration(milliseconds: 500)),
        const SizedBox(height: 12),
        Text(
          'Upload your room photo, choose a fabric,\nand let AI do the rest.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: VastraColors.textSecondary.withOpacity(0.75),
                height: 1.75,
              ),
          textAlign: TextAlign.center,
        )
            .animate(delay: const Duration(milliseconds: 950))
            .fadeIn(duration: const Duration(milliseconds: 500)),
      ],
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        AnimatedGlowButton(
          label: 'Take Photo',
          icon: Icons.camera_alt_rounded,
          onTap: () => _pickImage(ImageSource.camera),
          isPrimary: true,
        )
            .animate(delay: const Duration(milliseconds: 1100))
            .fadeIn(duration: const Duration(milliseconds: 500))
            .slideY(
              begin: 0.3,
              end: 0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            ),
        const SizedBox(height: 14),
        AnimatedGlowButton(
          label: 'Upload from Gallery',
          icon: Icons.photo_library_rounded,
          onTap: () => _pickImage(ImageSource.gallery),
          isPrimary: false,
        )
            .animate(delay: const Duration(milliseconds: 1250))
            .fadeIn(duration: const Duration(milliseconds: 500))
            .slideY(
              begin: 0.3,
              end: 0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            ),
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.auto_awesome_rounded,
          size: 12,
          color: VastraColors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          'Fully automatic · No manual selection needed',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: VastraColors.textMuted,
                fontSize: 11.5,
              ),
        ),
      ],
    )
        .animate(delay: const Duration(milliseconds: 1450))
        .fadeIn(duration: const Duration(milliseconds: 500));
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VastraColors.purpleNeon,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Preparing image...',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: VastraColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
