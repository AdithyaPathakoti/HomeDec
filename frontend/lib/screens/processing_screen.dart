import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final Uint8List originalImageBytes;
  final Uint8List maskImageBytes;
  final String prompt;
  final Uint8List? designBytes;

  const ProcessingScreen({
    Key? key,
    required this.originalImageBytes,
    required this.maskImageBytes,
    required this.prompt,
    this.designBytes,
  }) : super(key: key);

  @override
  _ProcessingScreenState createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final ApiService _apiService = ApiService();
  String _status = "Uploading images...";

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    setState(() {
      _status = "AI is redesigning your fabric. This may take a minute...";
    });

    final requestId = await _apiService.generateImage(
      imageBytes: widget.originalImageBytes,
      maskBytes: widget.maskImageBytes,
      prompt: widget.prompt,
      designBytes: widget.designBytes,
    );

    if (requestId != null) {
      final resultUrl = _apiService.getResultUrl(requestId);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(resultUrl: resultUrl, originalImageBytes: widget.originalImageBytes),
        ),
      );
    } else {
      setState(() {
        _status = "Error occurred. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 32),
              Text(
                _status,
                style: TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
