import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../providers/vastra_provider.dart';
import '../widgets/animated_glow_button.dart';
import '../widgets/before_after_slider.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _showComparison = false;
  bool _isSaving = false;

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

      final fileName =
          'vastra_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved: $fileName'),
          action: SnackBarAction(
            label: 'OK',
            textColor: VastraColors.purpleNeon,
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

  void _tryAnotherFabric() {
    context.read<VastraProvider>().resetForNewFabric();
    // Pop back to fabric upload screen (pop processing was pushReplacement, so pop once)
    Navigator.pop(context);
  }

  void _startOver() {
    context.read<VastraProvider>().reset();
    Navigator.popUntil(context, (route) => route.isFirst);
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
          child: CircularProgressIndicator(color: VastraColors.purpleNeon),
        ),
      );
    }

    return Scaffold(
      backgroundColor: VastraColors.background,
      body: Stack(
        children: [
          Container(
              decoration:
                  const BoxDecoration(gradient: VastraTheme.deepGradient)),
          SafeArea(
            child: Column(
              children: [
                // ── App bar ────────────────────────────────────────────────
                _buildAppBar(context),

                // ── Image area ─────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: VastraConstants.pagePadding),
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

                const SizedBox(height: 16),

                // ── Toggle button ──────────────────────────────────────────
                if (roomBytes != null)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showComparison = !_showComparison),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _showComparison
                            ? VastraColors.purpleAccent.withOpacity(0.2)
                            : Colors.white.withOpacity(0.06),
                        border: Border.all(
                          color: _showComparison
                              ? VastraColors.purpleNeon.withOpacity(0.6)
                              : Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.compare_rounded,
                            size: 16,
                            color: _showComparison
                                ? VastraColors.purpleNeon
                                : VastraColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _showComparison
                                ? 'Show Result'
                                : 'Compare Before/After',
                            style: TextStyle(
                              color: _showComparison
                                  ? VastraColors.purpleNeon
                                  : VastraColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // ── Action buttons ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      VastraConstants.pagePadding,
                      0,
                      VastraConstants.pagePadding,
                      24),
                  child: Column(
                    children: [
                      AnimatedGlowButton(
                        label: 'Download Image',
                        icon: Icons.download_rounded,
                        onTap: () => _downloadImage(resultBytes),
                        isPrimary: true,
                        isLoading: _isSaving,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedGlowButton(
                              label: 'Try Another',
                              icon: Icons.texture_rounded,
                              onTap: _tryAnotherFabric,
                              isPrimary: false,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AnimatedGlowButton(
                              label: 'Start Over',
                              icon: Icons.refresh_rounded,
                              onTap: _startOver,
                              isPrimary: false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-builders ───────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Your Design',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: VastraColors.purpleAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: VastraColors.purpleNeon.withOpacity(0.3),
                width: 0.8,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 12, color: VastraColors.purpleNeon),
                SizedBox(width: 5),
                Text(
                  'AI Generated',
                  style: TextStyle(
                    color: VastraColors.purpleNeon,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
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
    return ClipRRect(
      key: const ValueKey('result'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: VastraColors.purpleAccent.withOpacity(0.25),
              blurRadius: 40,
              spreadRadius: 2,
            ),
          ],
        ),
        child: InteractiveViewer(
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
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
              )
              .fadeIn(duration: const Duration(milliseconds: 600)),
        ),
      ),
    );
  }
}
