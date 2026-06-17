import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import 'processing_screen.dart';
import 'admin_panel_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;

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
          pageBuilder: (_, __, ___) => const ProcessingScreen(),
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeInOutCubic)),
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
          // Main content
          SafeArea(
            child: Column(
              children: [
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
                transitionDuration: const Duration(milliseconds: 250),
                transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: VastraColors.surfaceElevated,
                border: Border.all(color: VastraColors.border, width: 1.0),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      size: 14, color: VastraColors.textSecondary),
                  SizedBox(width: 6),
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: VastraColors.textSecondary,
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

  Widget _buildLogo() {
    return Column(
      children: [
        // Flat minimal medallion
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: VastraColors.ivory,
          ),
          child: const Center(
            child: Text(
              'V',
              style: TextStyle(
                color: VastraColors.background,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Wordmark
        Text(
          'VASTRA',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 28,
                letterSpacing: 10,
                color: VastraColors.ivory,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }

  Widget _buildTagline() {
    return Column(
      children: [
        Text(
          'AI Interior Fabric Visualizer',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: VastraColors.textPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'See your fabric in your room.\nBefore you buy.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: VastraColors.textSecondary,
                height: 1.6,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionSection() {
    return Column(
      children: [
        // Take photo (Primary white button)
        _ShadcnButton(
          label: 'Take Room Photo',
          icon: Icons.camera_alt_rounded,
          onTap: () => _pickImage(ImageSource.camera),
          isPrimary: true,
        ),

        const SizedBox(height: 12),

        // Gallery (Secondary outline button)
        _ShadcnButton(
          label: 'Upload from Gallery',
          icon: Icons.photo_library_rounded,
          onTap: () => _pickImage(ImageSource.gallery),
          isPrimary: false,
        ),
      ],
    );
  }


  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.60),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VastraColors.ivory,
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Preparing image...',
              style: TextStyle(color: VastraColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shadcn Button ───────────────────────────────────────────────────────────

class _ShadcnButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ShadcnButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: isPrimary
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: VastraColors.ivory,
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
                border: Border.all(
                  color: VastraColors.border,
                  width: 1.0,
                ),
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isPrimary ? VastraColors.background : VastraColors.ivory,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isPrimary ? VastraColors.background : VastraColors.ivory,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
