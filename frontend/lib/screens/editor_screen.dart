import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/masking_widget.dart';
import 'catalog_screen.dart';

class EditorScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const EditorScreen({Key? key, required this.imageBytes}) : super(key: key);

  @override
  _EditorScreenState createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  ui.Image? _uiImage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final imageProvider = MemoryImage(widget.imageBytes);
      final imageStream = imageProvider.resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      
      listener = ImageStreamListener((info, _) {
        completer.complete(info.image);
        imageStream.removeListener(listener);
      }, onError: (exception, stackTrace) {
        completer.completeError(exception);
        imageStream.removeListener(listener);
      });
      
      imageStream.addListener(listener);
      final uiImage = await completer.future;
      
      setState(() {
        _uiImage = uiImage;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading image: \$e");
    }
  }

  void _onMaskGenerated(Uint8List maskBytes) async {
    // Navigate to catalog screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CatalogScreen(
          originalImageBytes: widget.imageBytes,
          maskImageBytes: maskBytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Draw Mask over Fabric'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                SizedBox(height: 8),
                Expanded(
                  child: MaskingWidget(
                    image: _uiImage!,
                    imageBytes: widget.imageBytes,
                    brushSize: 30.0,
                    onMaskGenerated: _onMaskGenerated,
                  ),
                ),
              ],
            ),
    );
  }
}
