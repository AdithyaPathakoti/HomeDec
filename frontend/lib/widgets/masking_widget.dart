import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/api_service.dart';

enum MaskMode { smart, manual }

class Stroke {
  final List<Offset> points;
  final double strokeWidth;

  Stroke({required this.points, this.strokeWidth = 20.0});
}

class DetectedObject {
  final String label;
  final Rect boundingBox; // Normalized top-left, bottom-right coordinates
  final double confidence;

  DetectedObject({
    required this.label,
    required this.boundingBox,
    required this.confidence,
  });

  factory DetectedObject.fromJson(Map<String, dynamic> json) {
    final box = List<double>.from(json['box']);
    return DetectedObject(
      label: json['label'],
      boundingBox: Rect.fromLTRB(box[0], box[1], box[2], box[3]),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}

class MaskPainter extends CustomPainter {
  final List<Stroke> strokes;
  final ui.Image? image;
  final ui.Image? smartMaskImage;
  final List<DetectedObject> detectedObjects;
  final DetectedObject? selectedObject;
  final MaskMode mode;
  final double animationValue;
  final bool isAnalyzingRoom;

  MaskPainter({
    required this.strokes,
    this.image,
    this.smartMaskImage,
    required this.detectedObjects,
    this.selectedObject,
    required this.mode,
    required this.animationValue,
    required this.isAnalyzingRoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw base image
    if (image != null) {
      canvas.drawImageRect(
        image!,
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint(),
      );
    }

    // 2. Draw smart mask (if any)
    if (smartMaskImage != null) {
      const ColorFilter purpleMaskFilter = ColorFilter.matrix(<double>[
        0.6,   0,   0, 0, 0, // R = 0.6 * input_R
          0,   0,   0, 0, 0, // G = 0
        1.0,   0,   0, 0, 0, // B = 1.0 * input_R
        0.5,   0,   0, 0, 0, // A = 0.5 * input_R
      ]);
      
      canvas.drawImageRect(
        smartMaskImage!,
        Rect.fromLTWH(0, 0, smartMaskImage!.width.toDouble(), smartMaskImage!.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..colorFilter = purpleMaskFilter,
      );
    }

    // 3. Draw manual brush strokes
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (var stroke in strokes) {
      paint.strokeWidth = stroke.strokeWidth;
      for (int i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }

    // 4. Draw scanning laser sweep line when analyzing
    if (isAnalyzingRoom) {
      final double laserY = animationValue * size.height;
      
      // Laser line paint
      final laserPaint = Paint()
        ..color = Colors.purpleAccent
        ..strokeWidth = 3.0;
        
      canvas.drawLine(
        Offset(0, laserY),
        Offset(size.width, laserY),
        laserPaint,
      );

      // Add a fading glow under/above the laser line
      final glowPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, laserY - 30),
          Offset(0, laserY + 30),
          [
            Colors.purpleAccent.withOpacity(0.0),
            Colors.purpleAccent.withOpacity(0.4),
            Colors.purpleAccent.withOpacity(0.0),
          ],
          [0.0, 0.5, 1.0],
        );
      
      canvas.drawRect(
        Rect.fromLTRB(0, laserY - 30, size.width, laserY + 30),
        glowPaint,
      );
    }

    // 5. Draw selectable overlays in Smart mode
    if (mode == MaskMode.smart && detectedObjects.isNotEmpty && !isAnalyzingRoom) {
      for (var obj in detectedObjects) {
        final isSelected = obj == selectedObject;
        final double pulse = 0.7 + 0.3 * math.sin(animationValue * 2 * math.pi);
        
        final rect = Rect.fromLTRB(
          obj.boundingBox.left * size.width,
          obj.boundingBox.top * size.height,
          obj.boundingBox.right * size.width,
          obj.boundingBox.bottom * size.height,
        );

        final boxPaint = Paint()
          ..color = isSelected 
              ? Colors.purpleAccent.withOpacity(0.9) 
              : Colors.purpleAccent.withOpacity(0.3 * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3.0 : 1.5;

        if (isSelected) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(8)),
            Paint()
              ..color = Colors.purpleAccent.withOpacity(0.2 * pulse)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8.0,
          );
        }
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          boxPaint,
        );

        final fillPaint = Paint()
          ..color = isSelected 
              ? Colors.purpleAccent.withOpacity(0.15) 
              : Colors.purpleAccent.withOpacity(0.04 * pulse)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), fillPaint);

        // Draw badge tag: label + confidence
        final badgeWidth = math.max(100.0, rect.width * 0.45);
        final badgeRect = Rect.fromLTWH(rect.left, rect.top - 24, badgeWidth, 24);

        final badgePaint = Paint()
          ..color = isSelected ? Colors.purpleAccent : const Color(0xFF1E003B).withOpacity(0.85)
          ..style = PaintingStyle.fill;
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            badgeRect, 
            const Radius.circular(4)
          ),
          badgePaint,
        );

        final textPainter = TextPainter(
          text: TextSpan(
            text: "✨ ${obj.label[0].toUpperCase()}${obj.label.substring(1)} (${(obj.confidence * 100).toStringAsFixed(0)}%)",
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: badgeRect.width - 12);
        textPainter.paint(canvas, Offset(rect.left + 6, rect.top - 18));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MaskingWidget extends StatefulWidget {
  final ui.Image image;
  final Uint8List imageBytes;
  final double brushSize;
  final Function(Uint8List) onMaskGenerated;

  const MaskingWidget({
    Key? key,
    required this.image,
    required this.imageBytes,
    this.brushSize = 30.0,
    required this.onMaskGenerated,
  }) : super(key: key);

  @override
  _MaskingWidgetState createState() => _MaskingWidgetState();
}

class _MaskingWidgetState extends State<MaskingWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  MaskMode _mode = MaskMode.smart;
  List<Stroke> _strokes = [];
  Stroke? _currentStroke;
  
  double _renderWidth = 1.0;
  double _renderHeight = 1.0;
  
  bool _isLoadingMask = false;
  Uint8List? _smartMaskBytes;
  ui.Image? _smartMaskImage;
  
  int _tolerance = 40;
  double? _lastTapX;
  double? _lastTapY;

  // YOLO variables
  List<DetectedObject> _detectedObjects = [];
  bool _isAnalyzingRoom = false;
  DetectedObject? _selectedObject;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analyzeRoomImage();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _analyzeRoomImage() async {
    setState(() {
      _isAnalyzingRoom = true;
      _detectedObjects = [];
      _selectedObject = null;
    });

    try {
      final objectsJson = await ApiService().detectObjects(imageBytes: widget.imageBytes);
      if (objectsJson != null) {
        final parsed = objectsJson.map((obj) => DetectedObject.fromJson(obj as Map<String, dynamic>)).toList();
        setState(() {
          _detectedObjects = parsed;
        });
      }
    } catch (e) {
      print("Error analyzing room image: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingRoom = false;
        });
      }
    }
  }

  void _startStroke(DragStartDetails details) {
    if (_mode != MaskMode.manual) return;
    setState(() {
      _currentStroke = Stroke(points: [details.localPosition], strokeWidth: widget.brushSize);
      _strokes.add(_currentStroke!);
    });
  }

  void _updateStroke(DragUpdateDetails details) {
    if (_mode != MaskMode.manual || _currentStroke == null) return;
    setState(() {
      _currentStroke!.points.add(details.localPosition);
    });
  }

  void _endStroke(DragEndDetails details) {
    _currentStroke = null;
  }
  
  Future<void> _onSmartMaskTap(TapDownDetails details) async {
    if (_mode != MaskMode.smart || _isAnalyzingRoom) return;
    
    // Calculate percentage based on rendered size
    final xPct = details.localPosition.dx / _renderWidth;
    final yPct = details.localPosition.dy / _renderHeight;
    
    _lastTapX = xPct;
    _lastTapY = yPct;
    
    // Check if tapped inside any bounding box
    DetectedObject? tappedObj;
    for (var obj in _detectedObjects) {
      // Bounding box bounds are normalized (0 to 1)
      if (obj.boundingBox.contains(Offset(xPct, yPct))) {
        tappedObj = obj;
        break;
      }
    }

    if (tappedObj != null) {
      setState(() {
        _selectedObject = tappedObj;
      });
      final boxStr = "${tappedObj.boundingBox.left},${tappedObj.boundingBox.top},${tappedObj.boundingBox.right},${tappedObj.boundingBox.bottom}";
      await _fetchSmartMask(xPct, yPct, _tolerance, box: boxStr);
    } else {
      setState(() {
        _selectedObject = null;
      });
      await _fetchSmartMask(xPct, yPct, _tolerance);
    }
  }
  
  Future<void> _fetchSmartMask(double xPct, double yPct, int tol, {String? box}) async {
    setState(() {
      _isLoadingMask = true;
    });
    
    try {
      final maskBytes = await ApiService().autoMask(
        imageBytes: widget.imageBytes,
        xPct: xPct,
        yPct: yPct,
        tolerance: tol,
        box: box,
      );
      
      if (maskBytes != null) {
        // Decode bytes to ui.Image for rendering
        final completer = Completer<ui.Image>();
        ui.decodeImageFromList(maskBytes, (img) {
          completer.complete(img);
        });
        final decodedImage = await completer.future;
        
        setState(() {
          _smartMaskBytes = maskBytes;
          _smartMaskImage = decodedImage;
        });
      }
    } catch (e) {
      print("Error fetching smart mask: \$e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMask = false;
        });
      }
    }
  }

  void _onToleranceChanged(double value) {
    setState(() {
      _tolerance = value.toInt();
    });
  }
  
  void _onToleranceChangeEnd(double value) {
    if (_lastTapX != null && _lastTapY != null) {
      if (_selectedObject != null) {
        final boxStr = "${_selectedObject!.boundingBox.left},${_selectedObject!.boundingBox.top},${_selectedObject!.boundingBox.right},${_selectedObject!.boundingBox.bottom}";
        _fetchSmartMask(_lastTapX!, _lastTapY!, _tolerance, box: boxStr);
      } else {
        _fetchSmartMask(_lastTapX!, _lastTapY!, _tolerance);
      }
    }
  }

  void undo() {
    if (_mode == MaskMode.manual && _strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
      });
    } else if (_mode == MaskMode.smart && _smartMaskBytes != null) {
      setState(() {
        _smartMaskBytes = null;
        _smartMaskImage = null;
        _lastTapX = null;
        _lastTapY = null;
        _selectedObject = null;
      });
    }
  }

  void clear() {
    setState(() {
      _strokes.clear();
      _smartMaskBytes = null;
      _smartMaskImage = null;
      _lastTapX = null;
      _lastTapY = null;
      _selectedObject = null;
    });
  }

  Future<void> generateMask() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(widget.image.width.toDouble(), widget.image.height.toDouble());
    
    // Background must be completely black for the inpainting mask
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black);
    
    // 1. Draw the Smart Mask base if it exists
    if (_smartMaskImage != null) {
       // Since the smart mask is already black (bg) and white (fg), we can just draw it
       canvas.drawImageRect(
         _smartMaskImage!,
         Rect.fromLTWH(0, 0, _smartMaskImage!.width.toDouble(), _smartMaskImage!.height.toDouble()),
         Rect.fromLTWH(0, 0, size.width, size.height),
         Paint(),
       );
    }

    // 2. Overlay any manual strokes
    double scaleX = size.width / _renderWidth;
    double scaleY = size.height / _renderHeight;
    
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (var stroke in _strokes) {
      paint.strokeWidth = stroke.strokeWidth * scaleX;
      for (int i = 0; i < stroke.points.length - 1; i++) {
        Offset p1 = Offset(stroke.points[i].dx * scaleX, stroke.points[i].dy * scaleY);
        Offset p2 = Offset(stroke.points[i + 1].dx * scaleX, stroke.points[i + 1].dy * scaleY);
        canvas.drawLine(p1, p2, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(widget.image.width, widget.image.height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      widget.onMaskGenerated(byteData.buffer.asUint8List());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Mode Selector Tab
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = MaskMode.smart),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _mode == MaskMode.smart ? Colors.purpleAccent.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        "✨ Smart Mask",
                        style: TextStyle(
                          color: _mode == MaskMode.smart ? Colors.purpleAccent : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = MaskMode.manual),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _mode == MaskMode.manual ? Colors.white24 : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        "🖌️ Manual Brush",
                        style: TextStyle(
                          color: _mode == MaskMode.manual ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Instructions & Scanner / Slider Status
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _isAnalyzingRoom
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.purpleAccent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "⚡ AI Scanning Room Furniture...",
                        style: TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : _mode == MaskMode.smart
                  ? Column(
                      children: [
                        Text(
                          _detectedObjects.isNotEmpty
                              ? "Tap inside the purple bounding boxes to auto-segment furniture."
                              : "Tap on the fabric to magically select it.",
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text("Tolerance", style: TextStyle(color: Colors.white54, fontSize: 12)),
                            Expanded(
                              child: Slider(
                                value: _tolerance.toDouble(),
                                min: 5,
                                max: 100,
                                activeColor: Colors.purpleAccent,
                                inactiveColor: Colors.white12,
                                onChanged: _onToleranceChanged,
                                onChangeEnd: _onToleranceChangeEnd,
                              ),
                            ),
                          ],
                        )
                      ],
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        "Paint over any remaining areas.",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
        ),
        
        // Image Canvas
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              color: Colors.grey[950],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    _renderWidth = constraints.maxWidth;
                    _renderHeight = constraints.maxHeight;
                    
                    return GestureDetector(
                      onPanStart: _startStroke,
                      onPanUpdate: _updateStroke,
                      onPanEnd: _endStroke,
                      onTapDown: _onSmartMaskTap,
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: MaskPainter(
                              strokes: _strokes, 
                              image: widget.image,
                              smartMaskImage: _smartMaskImage,
                              detectedObjects: _detectedObjects,
                              selectedObject: _selectedObject,
                              mode: _mode,
                              animationValue: _animController.value,
                              isAnalyzingRoom: _isAnalyzingRoom,
                            ),
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                          );
                        },
                      ),
                    );
                  }
                ),
                if (_isLoadingMask)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(color: Colors.purpleAccent),
                          SizedBox(height: 12),
                          Text(
                            "⚡ Smart Masking...",
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        // Bottom Action Bar
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: IconButton(
                  icon: const Icon(Icons.undo, color: Colors.white, size: 20),
                  onPressed: undo,
                  tooltip: 'Undo',
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white, size: 20),
                  onPressed: clear,
                  tooltip: 'Clear',
                ),
              ),
              if (_detectedObjects.isNotEmpty && _mode == MaskMode.smart) ...[
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.purpleAccent, size: 20),
                    onPressed: _analyzeRoomImage,
                    tooltip: 'Rescan Room',
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: generateMask, 
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text(
                    "Redesign Fabric",
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.2),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}
