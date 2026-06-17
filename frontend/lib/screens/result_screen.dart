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

class _ResultScreenState extends State<ResultScreen> {
  bool _showComparison = false;
  bool _isSaving = false;
  bool _isSharing = false;

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
            textColor: VastraColors.ivory,
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
      // Bake the final AI image once adjustment closes
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
          child: CircularProgressIndicator(color: VastraColors.ivory, strokeWidth: 2.0),
        ),
      );
    }

    return Scaffold(
      backgroundColor: VastraColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(provider),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VastraConstants.pagePadding),
                  child: AspectRatio(
                    aspectRatio: provider.roomImageAspectRatio,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VastraColors.border, width: 1.0),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
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
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (roomBytes != null) _buildCompareToggle(),
            const SizedBox(height: 16),
            _buildActionButtons(resultBytes),
          ],
        ),
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
          // AI Generated badge (Shadcn Style)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: VastraColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: VastraColors.border,
                width: 1.0,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 12, color: VastraColors.ivory),
                SizedBox(width: 6),
                Text(
                  'AI Generated',
                  style: TextStyle(
                    color: VastraColors.ivory,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(Uint8List resultBytes) {
    final isProcessing = context.watch<VastraProvider>().isProcessing;

    return Stack(
      key: const ValueKey('result'),
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          minScale: 1.0,
          maxScale: 5.0,
          child: Image.memory(
            resultBytes,
            fit: BoxFit.fill,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
          ),
        ),
        if (isProcessing)
          Container(
            color: Colors.black.withOpacity(0.55),
            child: const Center(
              child: CircularProgressIndicator(
                color: VastraColors.ivory,
                strokeWidth: 2.0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompareToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showComparison = !_showComparison),
      child: AnimatedContainer(
        duration: 150.ms,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _showComparison ? VastraColors.ivory : Colors.transparent,
          border: Border.all(
            color: _showComparison ? VastraColors.ivory : VastraColors.border,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.compare_rounded,
              size: 14,
              color: _showComparison ? VastraColors.background : VastraColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              _showComparison ? 'Show Result Only' : 'Before / After',
              style: TextStyle(
                color: _showComparison ? VastraColors.background : VastraColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Uint8List resultBytes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VastraConstants.pagePadding, 0, VastraConstants.pagePadding, 24),
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
              const SizedBox(width: 8),
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
          const SizedBox(height: 8),
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
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'Try Another',
                  icon: Icons.texture_rounded,
                  isPrimary: false,
                  onTap: _tryAnotherFabric,
                ),
              ),
              const SizedBox(width: 8),
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
      child: Container(
        height: 48,
        decoration: isPrimary
            ? VastraTheme.goldDecoration(borderRadius: 12)
            : VastraTheme.glassDecoration(borderRadius: 12),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: isPrimary ? VastraColors.background : VastraColors.ivory,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: isPrimary ? VastraColors.background : VastraColors.ivory,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: isPrimary ? VastraColors.background : VastraColors.ivory,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
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
      decoration: BoxDecoration(
        color: VastraColors.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, -4),
          )
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle and Title
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: VastraColors.border,
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
                  icon: const Icon(Icons.refresh_rounded, size: 14, color: VastraColors.ivory),
                  label: const Text('Reset', style: TextStyle(color: VastraColors.ivory, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
  
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
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: VastraColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
              Text(displayValue, style: const TextStyle(color: VastraColors.ivory, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            activeColor: VastraColors.ivory,
            inactiveColor: VastraColors.border,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
