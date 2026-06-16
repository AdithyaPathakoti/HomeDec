import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants.dart';

/// Service class to communicate with Vastra SAM2 decoupled backend engine.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// Quick health check – returns true if the backend is reachable.
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse(
              '${VastraConstants.baseUrl}${VastraConstants.healthEndpoint}'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 1. Sends the room image as a multipart request to /api/upload.
  /// Returns the generated session_id.
  Future<String> uploadRoomImage(Uint8List imageBytes, String filename) async {
    final uri = Uri.parse(
        '${VastraConstants.baseUrl}${VastraConstants.uploadEndpoint}');
    
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'room_image',
      imageBytes,
      filename: filename,
      contentType: MediaType('image', 'jpeg'),
    ));

    final streamedResponse = await request.send().timeout(
      const Duration(minutes: 1),
      onTimeout: () {
        throw Exception('Upload request timed out.');
      },
    );

    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      final sessionId = jsonResponse['session_id'] as String?;
      if (sessionId == null) {
        throw Exception('session_id not found in response: ${response.body}');
      }
      return sessionId;
    } else {
      throw Exception('Upload failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// 2. Sends the session_id, category, and point prompts to /api/interact.
  /// Expects binary image data back (the preview overlay PNG).
  Future<Uint8List> sendInteractiveTap({
    required String sessionId,
    required String productCategory,
    required List<Map<String, dynamic>> points,
  }) async {
    final uri = Uri.parse(
        '${VastraConstants.baseUrl}${VastraConstants.interactEndpoint}');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'session_id': sessionId,
        'product_category': productCategory,
        'points': points,
      }),
    ).timeout(const Duration(minutes: 1));

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Interaction failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// 3. Sends the session_id, fabricTextureId, productCategory, and optional
  /// custom fabric image (base64) to /api/render.
  /// Returns the final OpenCV composited room image.
  Future<Uint8List> renderFinalFabric({
    required String sessionId,
    required String fabricTextureId,
    required String productCategory,
    String? fabricImageBase64,
    bool refineWithDiffusion = false,
    double tileScale = 1.0,
    double rotation = 0.0,
    double offsetX = 0.0,
    double offsetY = 0.0,
  }) async {
    final uri = Uri.parse(
        '${VastraConstants.baseUrl}${VastraConstants.renderEndpoint}');

    final payload = {
      'session_id': sessionId,
      'fabric_texture_id': fabricTextureId,
      'product_category': productCategory,
      'refine_with_diffusion': refineWithDiffusion,
      'tile_scale': tileScale,
      'rotation': rotation,
      'offset_x': offsetX,
      'offset_y': offsetY,
    };
    if (fabricImageBase64 != null) {
      payload['fabric_image_base64'] = fabricImageBase64;
    }

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(payload),
    ).timeout(const Duration(minutes: 2));

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Render failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// 4. Fetches the binary mask PNG of the current session.
  Future<Uint8List> fetchMask(String sessionId) async {
    final uri = Uri.parse('${VastraConstants.baseUrl}/api/session/$sessionId/mask');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to fetch mask: ${response.statusCode} - ${response.body}');
    }
  }

  /// 5. Uploads a manual brush-corrected binary mask (base64) to update session mask.
  Future<Uint8List> updateSessionMask({
    required String sessionId,
    required String base64Mask,
  }) async {
    final uri = Uri.parse('${VastraConstants.baseUrl}/api/session/mask');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'session_id': sessionId,
        'mask_base64': base64Mask,
      }),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to update mask: ${response.statusCode} - ${response.body}');
    }
  }
}
