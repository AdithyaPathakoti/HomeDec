import 'dart:typed_data';
import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  final String resultUrl;
  final Uint8List originalImageBytes;

  const ResultScreen({Key? key, required this.resultUrl, required this.originalImageBytes}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Your New Fabric'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.download),
            onPressed: () {
              // TODO: Implement save to gallery
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to Gallery!')));
            },
          ),
          IconButton(
            icon: Icon(Icons.share),
            onPressed: () {
              // TODO: Implement share
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.network(
                resultUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(child: CircularProgressIndicator(color: Colors.white));
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(child: Text('Error loading result image', style: TextStyle(color: Colors.white)));
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                    child: Text('Start Over'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
