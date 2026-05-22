import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import '../widgets/animated_glow_button.dart';
import 'processing_screen.dart';

class FabricUploadScreen extends StatefulWidget {
  const FabricUploadScreen({super.key});

  @override
  State<FabricUploadScreen> createState() => _FabricUploadScreenState();
}

class _FabricUploadScreenState extends State<FabricUploadScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _fabricBytes;
  bool _isPickingImage = false;

  late final AnimationController _cardGlowCtrl;
  late final Animation<double> _cardGlowAnim;

  @override
  void initState() {
    super.initState();
    _cardGlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _cardGlowAnim =
        CurvedAnimation(parent: _cardGlowCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _cardGlowCtrl.dispose();
    super.dispose();
  }

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _pickFabric(ImageSource source) async {
    if (_isPickingImage) return;
    try {
      setState(() => _isPickingImage = true);
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        setState(() => _fabricBytes = bytes);
        context.read<VastraProvider>().setFabricImage(bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load fabric image: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _clearFabric() {
    setState(() => _fabricBytes = null);
    context.read<VastraProvider>().clearFabricImage();
  }

  void _onGenerate() {
    if (_fabricBytes == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ProcessingScreen(),
        transitionDuration: VastraConstants.animationSlow,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  void _showSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VastraColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SourceSheet(onPick: _pickFabric),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VastraProvider>();

    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          Container(
              decoration:
                  const BoxDecoration(gradient: VastraTheme.deepGradient)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── App bar ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _buildStepIndicator(step: 2, total: 3),
                    ],
                  ),
                ),

                // ── Header ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VastraConstants.pagePadding,
                      20,
                      VastraConstants.pagePadding,
                      0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload Your Fabric',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Photo of ${provider.selectedProduct?.label ?? 'the selected item'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: VastraColors.purpleNeon,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Take a photo of a real fabric swatch or upload one from your gallery.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Fabric preview / upload area ─────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: VastraConstants.pagePadding),
                    child: _fabricBytes == null
                        ? _buildUploadArea()
                        : _buildPreviewCard(),
                  ),
                ),

                // ── Upload source buttons ────────────────────────────────────
                if (_fabricBytes == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: VastraConstants.pagePadding),
                    child: Column(
                      children: [
                        AnimatedGlowButton(
                          label: 'Take Fabric Photo',
                          icon: Icons.camera_alt_rounded,
                          onTap: () => _pickFabric(ImageSource.camera),
                          isPrimary: true,
                          isLoading: _isPickingImage,
                        ),
                        const SizedBox(height: 12),
                        AnimatedGlowButton(
                          label: 'Upload from Gallery',
                          icon: Icons.photo_library_rounded,
                          onTap: () => _pickFabric(ImageSource.gallery),
                          isPrimary: false,
                          isLoading: _isPickingImage,
                        ),
                      ],
                    ),
                  ),

                // ── Generate button ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VastraConstants.pagePadding,
                      16,
                      VastraConstants.pagePadding,
                      28),
                  child: AnimatedGlowButton(
                    label: _fabricBytes == null
                        ? 'Select a Fabric First'
                        : 'Generate Design',
                    icon: Icons.auto_awesome_rounded,
                    onTap: _fabricBytes != null ? _onGenerate : null,
                    isPrimary: true,
                    isEnabled: _fabricBytes != null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Fabric upload placeholder ───────────────────────────────────────────────

  Widget _buildUploadArea() {
    return Container(
      decoration: VastraTheme.glassDecoration(borderRadius: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VastraColors.purpleAccent.withOpacity(0.1),
                border: Border.all(
                  color: VastraColors.purpleAccent.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.texture_rounded,
                size: 36,
                color: VastraColors.purpleNeon,
              ),
            )
                .animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.05, 1.05),
                  duration: const Duration(milliseconds: 1800),
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 20),
            Text(
              'No fabric selected yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: VastraColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the buttons below to add a fabric image',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VastraColors.textMuted,
                    fontSize: 13,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Fabric preview card ─────────────────────────────────────────────────────

  Widget _buildPreviewCard() {
    return AnimatedBuilder(
      animation: _cardGlowAnim,
      builder: (_, child) {
        final glow = 0.2 + _cardGlowAnim.value * 0.15;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: VastraColors.purpleAccent.withOpacity(glow),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Fabric image
            Positioned.fill(
              child: Image.memory(
                _fabricBytes!,
                fit: BoxFit.cover,
              )
                  .animate()
                  .fadeIn(duration: const Duration(milliseconds: 400))
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1.0, 1.0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutBack,
                  ),
            ),

            // Glassmorphism overlay at top
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: VastraColors.purpleAccent.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'FABRIC SELECTED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Change button
                    _buildChip(
                      icon: Icons.edit_rounded,
                      label: 'Change',
                      onTap: _showSourceSheet,
                    ),
                    const SizedBox(width: 8),
                    // Remove button
                    _buildChip(
                      icon: Icons.close_rounded,
                      label: 'Remove',
                      onTap: _clearFabric,
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDestructive
                ? Colors.red.withOpacity(0.4)
                : Colors.white.withOpacity(0.2),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: isDestructive
                    ? Colors.red[300]
                    : VastraColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isDestructive ? Colors.red[300] : VastraColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator({required int step, required int total}) {
    return Row(
      children: List.generate(total, (i) {
        final isActive = i < step;
        final isCurrent = i == step - 1;
        return Container(
          margin: const EdgeInsets.only(left: 6),
          width: isCurrent ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive
                ? VastraColors.purpleNeon
                : Colors.white.withOpacity(0.15),
          ),
        );
      }),
    );
  }
}

// ── Source bottom sheet ──────────────────────────────────────────────────────

class _SourceSheet extends StatelessWidget {
  final void Function(ImageSource) onPick;

  const _SourceSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      decoration: BoxDecoration(
        color: VastraColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'Choose Fabric Source',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Take a photo of a real fabric or pick from your gallery.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: VastraColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          AnimatedGlowButton(
            label: 'Take Photo',
            icon: Icons.camera_alt_rounded,
            onTap: () {
              Navigator.pop(context);
              onPick(ImageSource.camera);
            },
            isPrimary: true,
          ),
          const SizedBox(height: 12),
          AnimatedGlowButton(
            label: 'Choose from Gallery',
            icon: Icons.photo_library_rounded,
            onTap: () {
              Navigator.pop(context);
              onPick(ImageSource.gallery);
            },
            isPrimary: false,
          ),
        ],
      ),
    );
  }
}
