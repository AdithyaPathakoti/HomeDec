import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// Quick health check – returns true if the backend is reachable.
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('${VastraConstants.baseUrl}${VastraConstants.healthEndpoint}'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends the room image, selected product category, and fabric image to the
  /// backend and returns the generated result as raw PNG bytes.
  Future<Uint8List> generateFabric({
    required Uint8List roomImageBytes,
    required String productCategory,
    required Uint8List fabricImageBytes,
  }) async {
    final uri =
        Uri.parse('${VastraConstants.baseUrl}${VastraConstants.generateEndpoint}');

    final request = http.MultipartRequest('POST', uri);

    request.files.add(http.MultipartFile.fromBytes(
      'room_image',
      roomImageBytes,
      filename: 'room.jpg',
      contentType: MediaType('image', 'jpeg'),
    ));

    request.files.add(http.MultipartFile.fromBytes(
      'fabric_image',
      fabricImageBytes,
      filename: 'fabric.jpg',
      contentType: MediaType('image', 'jpeg'),
    ));

    request.fields['product_category'] = productCategory;

    final streamedResponse = await request.send().timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        throw Exception(
            'Request timed out. The AI processing took longer than 3 minutes.');
      },
    );

    if (streamedResponse.statusCode == 200) {
      return await streamedResponse.stream.toBytes();
    } else {
      final body = await streamedResponse.stream.bytesToString();
      throw Exception('Backend returned ${streamedResponse.statusCode}: $body');
    }
  }
}
