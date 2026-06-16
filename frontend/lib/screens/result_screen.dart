import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import '../widgets/before_after_slider.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  bool _showComparison = false;
  bool _isSaving = false;
  bool _isSharing = false;

  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── Save to device ─────────────────────────────────────────────────────────

  Future<void> _downloadImage(Uint8List bytes) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      if (dir == null) throw Exception('Storage unavailable');
      final fileName = 'vastra_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to gallery: $fileName'),
          action: SnackBarAction(
            label: 'OK',
            textColor: VastraColors.gold,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red[900],
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  Future<void> _shareImage(Uint8List bytes) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/vastra_share.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'See how this fabric looks in my room! 🏠✨ Created with Vastra AI',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _tryAnotherFabric() {
    context.read<VastraProvider>().resetForNewFabric();
    Navigator.pop(context);
  }

  void _startOver() {
    context.read<VastraProvider>().reset();
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _showAdjustmentPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => const _FabricAdjustmentPanel(),
    ).then((_) {
      if (!mounted) return;
      // Bake the final AI image with diffusion refinement once user finishes adjustment and closes bottom sheet
      final provider = context.read<VastraProvider>();
      if (provider.refineWithDiffusion && provider.lastFabricTextureId != null) {
        provider.renderFinal(
          provider.lastFabricTextureId!,
          customFabricBytes: provider.lastCustomFabricBytes,
          bypassDiffusion: false,
        ).catchError((err) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to bake final diffusion: $err'),
                backgroundColor: Colors.red[900],
              ),
            );
          }
        });
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VastraProvider>();
    final resultBytes = provider.resultImageBytes;
    final roomBytes = provider.roomImageBytes;

    if (resultBytes == null) {
      return const Scaffold(
        backgroundColor: VastraColors.background,
        body: Center(
          child: CircularProgressIndicator(color: VastraColors.gold),
        ),
      );
    }

    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: VastraTheme.deepGradient)),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(provider),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: VastraConstants.pagePadding),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: _showComparison && roomBytes != null
                          ? BeforeAfterSlider(
                              key: const ValueKey('comparison'),
                              beforeBytes: roomBytes,
                              afterBytes: resultBytes,
                            )
                          : _buildResultView(resultBytes),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (roomBytes != null) _buildCompareToggle(),
                const SizedBox(height: 20),
                _buildActionButtons(resultBytes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(VastraProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: VastraColors.ivory, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Your Design',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          // AI Generated badge with gold glow
          AnimatedBuilder(
            animation: _glowCtrl,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: VastraColors.gold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: VastraColors.gold.withOpacity(0.35 + _glowCtrl.value * 0.2),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: VastraColors.gold.withOpacity(0.15 * _glowCtrl.value),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 12,
                      color: VastraColors.gold.withOpacity(0.8 + _glowCtrl.value * 0.2)),
                  const SizedBox(width: 5),
                  Text(
                    'AI Generated',
                    style: TextStyle(
                      color: VastraColors.gold.withOpacity(0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
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

  Widget _buildResultView(Uint8List resultBytes) {
    final isProcessing = context.watch<VastraProvider>().isProcessing;

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
          boxShadow: [
            BoxShadow(
              color: VastraColors.gold.withOpacity(0.12 + _glowCtrl.value * 0.06),
              blurRadius: 32,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: VastraColors.terracotta.withOpacity(0.08),
              blurRadius: 60,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          key: const ValueKey('result'),
          borderRadius: BorderRadius.circular(VastraConstants.cardBorderRadius),
          child: child,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 5.0,
            child: Image.memory(
              resultBytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            )
                .animate()
                .scale(
                  begin: const Offset(0.88, 0.88),
                  end: const Offset(1.0, 1.0),
                  duration: 750.ms,
                  curve: Curves.easeOutCubic,
                )
                .fadeIn(duration: 600.ms),
          ),
          if (isProcessing)
            Container(
              color: Colors.black.withOpacity(0.55),
              child: const Center(
                child: CircularProgressIndicator(
                  color: VastraColors.gold,
                  strokeWidth: 2.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompareToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showComparison = !_showComparison),
      child: AnimatedContainer(
        duration: 250.ms,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: _showComparison
              ? VastraColors.gold.withOpacity(0.15)
              : VastraColors.surface,
          border: Border.all(
            color: _showComparison
                ? VastraColors.gold.withOpacity(0.6)
                : VastraColors.borderLight,
            width: _showComparison ? 1.2 : 0.8,
          ),
          boxShadow: _showComparison
              ? [
                  BoxShadow(
                    color: VastraColors.gold.withOpacity(0.15),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_rounded,
              size: 16,
              color: _showComparison ? VastraColors.gold : VastraColors.warmGrayDark,
            ),
            const SizedBox(width: 8),
            Text(
              _showComparison ? 'Show Result Only' : 'Before / After',
              style: TextStyle(
                color: _showComparison ? VastraColors.gold : VastraColors.warmGrayDark,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Uint8List resultBytes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          VastraConstants.pagePadding, 0, VastraConstants.pagePadding, 28),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _ActionButton(
                  label: 'Save to Gallery',
                  icon: Icons.download_rounded,
                  isPrimary: true,
                  isLoading: _isSaving,
                  onTap: () => _downloadImage(resultBytes),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _ActionButton(
                  label: 'Adjust',
                  icon: Icons.tune_rounded,
                  isPrimary: false,
                  onTap: _showAdjustmentPanel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  isPrimary: false,
                  isLoading: _isSharing,
                  onTap: () => _shareImage(resultBytes),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Try Another',
                  icon: Icons.texture_rounded,
                  isPrimary: false,
                  onTap: _tryAnotherFabric,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Start Over',
                  icon: Icons.refresh_rounded,
                  isPrimary: false,
                  onTap: _startOver,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: 250.ms,
        height: 52,
        decoration: isPrimary
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                gradient: VastraTheme.goldGradient,
                boxShadow: [
                  BoxShadow(
                    color: VastraColors.gold.withOpacity(0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(VastraConstants.buttonBorderRadius),
                color: VastraColors.surface,
                border: Border.all(color: VastraColors.borderLight),
              ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: isPrimary ? VastraColors.textOnGold : VastraColors.gold,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isPrimary ? VastraColors.textOnGold : VastraColors.warmGray,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: isPrimary
                                  ? VastraColors.textOnGold
                                  : VastraColors.warmGray,
                              fontWeight: FontWeight.w600,
                              fontSize: isPrimary ? 14 : 12,
                            ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Fabric Adjustment Panel Bottom Sheet ──────────────────────────────────────

class _FabricAdjustmentPanel extends StatefulWidget {
  const _FabricAdjustmentPanel();

  @override
  State<_FabricAdjustmentPanel> createState() => _FabricAdjustmentPanelState();
}

class _FabricAdjustmentPanelState extends State<_FabricAdjustmentPanel> {
  late double _localScale;
  late double _localRotation;
  late double _localOffsetX;
  late double _localOffsetY;

  @override
  void initState() {
    super.initState();
    final provider = context.read<VastraProvider>();
    _localScale = provider.tileScale;
    _localRotation = provider.rotation;
    _localOffsetX = provider.offsetX;
    _localOffsetY = provider.offsetY;
  }

  void _triggerUpdate() {
    final provider = context.read<VastraProvider>();
    provider.setTileScale(_localScale);
    provider.setRotation(_localRotation);
    provider.setOffsetX(_localOffsetX);
    provider.setOffsetY(_localOffsetY);

    if (provider.lastFabricTextureId != null) {
      provider.renderFinal(
        provider.lastFabricTextureId!,
        customFabricBytes: provider.lastCustomFabricBytes,
        bypassDiffusion: true,
      ).catchError((err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update fabric placement: $err'),
              backgroundColor: Colors.red[900],
            ),
          );
        }
      });
    }
  }

  void _reset() {
    setState(() {
      _localScale = 1.0;
      _localRotation = 0.0;
      _localOffsetX = 0.0;
      _localOffsetY = 0.0;
    });
    _triggerUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: VastraColors.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle and Title
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VastraColors.warmGray.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Adjust Fabric Placement',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: VastraColors.ivory,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: VastraColors.gold),
                  label: const Text('Reset', style: TextStyle(color: VastraColors.gold, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 20),
  
            // Scale Slider
            _buildSliderRow(
              label: 'Pattern Scale',
              value: _localScale,
              min: 0.2,
              max: 3.0,
              displayValue: '${_localScale.toStringAsFixed(1)}x',
              onChanged: (val) => setState(() => _localScale = val),
              onChangeEnd: (_) => _triggerUpdate(),
            ),
  
            // Rotation Slider
            _buildSliderRow(
              label: 'Rotation Angle',
              value: _localRotation,
              min: -180.0,
              max: 180.0,
              displayValue: '${_localRotation.round()}°',
              onChanged: (val) => setState(() => _localRotation = val),
              onChangeEnd: (_) => _triggerUpdate(),
            ),
  
            // Offset X Slider
            _buildSliderRow(
              label: 'Position X Shift',
              value: _localOffsetX,
              min: -1.0,
              max: 1.0,
              displayValue: _localOffsetX == 0.0 ? 'Center' : (_localOffsetX > 0 ? '+${(_localOffsetX * 100).round()}%' : '${(_localOffsetX * 100).round()}%'),
              onChanged: (val) => setState(() => _localOffsetX = val),
              onChangeEnd: (_) => _triggerUpdate(),
            ),
  
            // Offset Y Slider
            _buildSliderRow(
              label: 'Position Y Shift',
              value: _localOffsetY,
              min: -1.0,
              max: 1.0,
              displayValue: _localOffsetY == 0.0 ? 'Center' : (_localOffsetY > 0 ? '+${(_localOffsetY * 100).round()}%' : '${(_localOffsetY * 100).round()}%'),
              onChanged: (val) => setState(() => _localOffsetY = val),
              onChangeEnd: (_) => _triggerUpdate(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: VastraColors.warmGray, fontSize: 13, fontWeight: FontWeight.w500)),
              Text(displayValue, style: const TextStyle(color: VastraColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            activeColor: VastraColors.gold,
            inactiveColor: VastraColors.borderLight,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
