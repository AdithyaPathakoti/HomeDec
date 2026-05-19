import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  // Use the PC's local IP address so physical mobile devices on the same Wi-Fi can access the backend
  static const String baseUrl = 'http://192.168.1.10:8000';

  Future<String?> generateImage({
    required Uint8List imageBytes,
    required Uint8List maskBytes,
    required String prompt,
    Uint8List? designBytes,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/generate'));
      
      request.files.add(http.MultipartFile.fromBytes(
        'image', 
        imageBytes,
        filename: 'image.png',
        contentType: MediaType('image', 'png')
      ));
      
      request.files.add(http.MultipartFile.fromBytes(
        'mask', 
        maskBytes,
        filename: 'mask.png',
        contentType: MediaType('image', 'png')
      ));
      
      if (designBytes != null && designBytes.isNotEmpty) {
        request.files.add(http.MultipartFile.fromBytes(
          'design', 
          designBytes,
          filename: 'design.png',
          contentType: MediaType('image', 'png')
        ));
      }
      
      request.fields['prompt'] = prompt;

      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var json = jsonDecode(responseData);
        return json['request_id'];
      } else {
        print('Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('API Error: $e');
      return null;
    }
  }

  Future<List<dynamic>?> detectObjects({
    required Uint8List imageBytes,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/detect_objects'));
      
      request.files.add(http.MultipartFile.fromBytes(
        'image', 
        imageBytes,
        filename: 'image.png',
        contentType: MediaType('image', 'png')
      ));

      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var json = jsonDecode(responseData);
        return json['objects'];
      } else {
        print('Detect objects API Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Detect objects API Exception: $e');
      return null;
    }
  }

  Future<Uint8List?> autoMask({
    required Uint8List imageBytes,
    required double xPct,
    required double yPct,
    required int tolerance,
    String? box,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/auto_mask'));
      
      request.files.add(http.MultipartFile.fromBytes(
        'image', 
        imageBytes,
        filename: 'image.png',
        contentType: MediaType('image', 'png')
      ));
      
      request.fields['x_pct'] = xPct.toString();
      request.fields['y_pct'] = yPct.toString();
      request.fields['tolerance'] = tolerance.toString();
      if (box != null) {
        request.fields['box'] = box;
      }

      var response = await request.send();
      if (response.statusCode == 200) {
        final responseBytes = await response.stream.toBytes();
        return responseBytes;
      } else {
        print('Auto-mask API Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Auto-mask API Exception: $e');
      return null;
    }
  }

  String getResultUrl(String requestId) {
    return '$baseUrl/result/$requestId';
  }
}
