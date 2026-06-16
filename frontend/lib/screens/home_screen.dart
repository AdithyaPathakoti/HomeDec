import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import 'product_selection_screen.dart';
import 'admin_panel_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _ambientCtrl;
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _ambientAnim;
  late final Animation<double> _shimmerAnim;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _ambientAnim = CurvedAnimation(parent: _ambientCtrl, curve: Curves.easeInOut);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _shimmerAnim = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _shimmerCtrl.dispose();
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
                begin: const Offset(0.0, 0.06),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
      body: Stack(
        children: [
          // Deep warm gradient background
          Container(decoration: const BoxDecoration(gradient: VastraTheme.deepGradient)),

          // Animated warm ambient blobs
          _buildAmbientBlobs(),

          // Fabric weave texture overlay (subtle)
          _buildFabricTextureOverlay(),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Admin button row
                _buildTopBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: VastraConstants.pagePadding),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        _buildLogo(),
                        const SizedBox(height: 28),
                        _buildTagline(),
                        const Spacer(flex: 3),
                        _buildActionSection(),
                        const SizedBox(height: 24),
                        _buildFeaturePills(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ── Sub-builders ───────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminPanelScreen(),
                transitionDuration: VastraConstants.animationNormal,
                transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                color: VastraColors.surface,
                border: Border.all(color: VastraColors.borderGold.withOpacity(0.5), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      size: 14, color: VastraColors.gold.withOpacity(0.8)),
                  const SizedBox(width: 6),
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: VastraColors.gold.withOpacity(0.8),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ).animate(delay: 1500.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildAmbientBlobs() {
    return AnimatedBuilder(
      animation: _ambientAnim,
      builder: (_, __) {
        final t = _ambientAnim.value;
        return Stack(
          children: [
            // Top-left warm gold blob
            Positioned(
              top: -100 + t * 30,
              left: -80 + t * 15,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    VastraColors.gold.withOpacity(0.10),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            // Bottom-right terracotta blob
            Positioned(
              bottom: -120 + t * 20,
              right: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    VastraColors.terracotta.withOpacity(0.09),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            // Mid subtle ivory shimmer
            Positioned(
              top: MediaQuery.of(context).size.height * 0.38 + t * 12,
              left: MediaQuery.of(context).size.width * 0.5 - 90,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    VastraColors.ivory.withOpacity(0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFabricTextureOverlay() {
    // Subtle diagonal line pattern suggesting woven fabric texture
    return Opacity(
      opacity: 0.025,
      child: CustomPaint(
        painter: _FabricGridPainter(),
        size: MediaQuery.of(context).size,
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // Logo mark — golden V medallion
        AnimatedBuilder(
          animation: _shimmerAnim,
          builder: (_, child) {
            final shimmer = math.sin(_shimmerAnim.value * math.pi * 2);
            return Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: VastraTheme.goldGradient,
                boxShadow: [
                  BoxShadow(
                    color: VastraColors.gold.withOpacity(0.45 + shimmer * 0.08),
                    blurRadius: 36,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: VastraColors.terracotta.withOpacity(0.20 + shimmer * 0.05),
                    blurRadius: 64,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'V',
                  style: TextStyle(
                    color: Color(0xFF1A0E05),
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            );
          },
        )
            .animate()
            .scale(
              begin: const Offset(0.3, 0.3),
              end: const Offset(1.0, 1.0),
              duration: 800.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: 600.ms),

        const SizedBox(height: 24),

        // Wordmark
        Text(
          'VASTRA',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontFamily: 'Playfair Display',
                fontSize: 32,
                letterSpacing: 12,
                color: VastraColors.ivory,
                fontWeight: FontWeight.w700,
              ),
        )
            .animate(delay: 300.ms)
            .fadeIn(duration: 600.ms)
            .slideY(begin: 0.25, end: 0, duration: 600.ms, curve: Curves.easeOutCubic),

        const SizedBox(height: 12),

        // Decorative divider — gold line with center diamond
        _buildDividerWithDiamond()
            .animate(delay: 700.ms)
            .scaleX(begin: 0, end: 1, duration: 500.ms, curve: Curves.easeOut)
            .fadeIn(duration: 400.ms),
      ],
    );
  }

  Widget _buildDividerWithDiamond() {
    return SizedBox(
      width: 120,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  VastraColors.gold.withOpacity(0.6),
                  VastraColors.gold,
                  VastraColors.gold.withOpacity(0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: VastraColors.gold,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagline() {
    return Column(
      children: [
        Text(
          'AI Interior Fabric Visualizer',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: VastraColors.gold,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
              ),
          textAlign: TextAlign.center,
        )
            .animate(delay: 900.ms)
            .fadeIn(duration: 500.ms),
        const SizedBox(height: 10),
        Text(
          'See your fabric in your room.\nBefore you buy.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: VastraColors.textSecondary.withOpacity(0.8),
                height: 1.8,
              ),
          textAlign: TextAlign.center,
        )
            .animate(delay: 1100.ms)
            .fadeIn(duration: 500.ms),
      ],
    );
  }

  Widget _buildActionSection() {
    return Column(
      children: [
        // Primary CTA — Take Photo
        _WarmGlowButton(
          label: 'Take Room Photo',
          icon: Icons.camera_alt_rounded,
          onTap: () => _pickImage(ImageSource.camera),
          isPrimary: true,
        )
            .animate(delay: 1300.ms)
            .fadeIn(duration: 500.ms)
            .slideY(begin: 0.3, end: 0, duration: 500.ms, curve: Curves.easeOut),

        const SizedBox(height: 14),

        // Secondary CTA — Gallery
        _WarmGlowButton(
          label: 'Upload from Gallery',
          icon: Icons.photo_library_rounded,
          onTap: () => _pickImage(ImageSource.gallery),
          isPrimary: false,
        )
            .animate(delay: 1450.ms)
            .fadeIn(duration: 500.ms)
            .slideY(begin: 0.3, end: 0, duration: 500.ms, curve: Curves.easeOut),
      ],
    );
  }

  Widget _buildFeaturePills() {
    final features = [
      (Icons.auto_awesome_rounded, 'Fully Automatic'),
      (Icons.layers_rounded, '9-Stage AI'),
      (Icons.compare_rounded, 'Before/After'),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: features
          .asMap()
          .entries
          .map((e) => _buildPill(e.value.$1, e.value.$2)
              .animate(delay: Duration(milliseconds: 1600 + e.key * 100))
              .fadeIn(duration: 400.ms))
          .toList(),
    );
  }

  Widget _buildPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VastraConstants.chipBorderRadius),
        color: VastraColors.surface,
        border: Border.all(color: VastraColors.borderLight, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: VastraColors.warmGrayDark),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: VastraColors.warmGrayDark,
                  fontSize: 10.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.70),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VastraColors.gold,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Preparing image...',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: VastraColors.warmGray),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Warm Glow Button ──────────────────────────────────────────────────────────

class _WarmGlowButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _WarmGlowButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  State<_WarmGlowButton> createState() => _WarmGlowButtonState();
}

class _WarmGlowButtonState extends State<_WarmGlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _pressCtrl;
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.forward();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressCtrl.forward(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: widget.isPrimary
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                  gradient: VastraTheme.goldGradient,
                  boxShadow: [
                    BoxShadow(
                      color: VastraColors.gold.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                  color: VastraColors.surface,
                  border: Border.all(
                    color: VastraColors.borderLight,
                    width: 1.2,
                  ),
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.isPrimary
                    ? VastraColors.textOnGold
                    : VastraColors.warmGray,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: widget.isPrimary
                          ? VastraColors.textOnGold
                          : VastraColors.warmGray,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Fabric Grid Painter — background texture ──────────────────────────────────

class _FabricGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VastraColors.ivory
      ..strokeWidth = 0.5;

    const spacing = 24.0;

    // Horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
