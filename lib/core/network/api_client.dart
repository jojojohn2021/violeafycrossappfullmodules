import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../config/env_config.dart';
import '../errors/app_errors.dart';

class ApiClient {
  final http.Client _client = http.Client();

  // Retrieve auth headers (including dynamic Firebase ID token)
  Future<Map<String, String>> _getHeaders() async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Retrieve fresh token (cached or auto-refreshed)
        final String? token = await user.getIdToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (e) {
      debugPrint('[API Client] Token retrieval warning: $e');
    }
    return headers;
  }

  // Handle Response states
  dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return json.decode(response.body);
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      debugPrint('[API Client] Auth error: ${response.statusCode}');
      throw const AuthException('Authentication failed. Please sign in again.', statusCode: 401);
    } else {
      debugPrint('[API Client] Call failed: ${response.statusCode}');
      throw ServerException('Request failed. Please try again.', statusCode: response.statusCode);
    }
  }

  // GET request
  Future<dynamic> get(String endpoint) async {
    final String url = '${EnvConfig.baseUrl}$endpoint';
    final headers = await _getHeaders();

    try {
      debugPrint('[API Client] GET -> $url');
      final response = await _client.get(Uri.parse(url), headers: headers).timeout(
        const Duration(seconds: 15),
      );
      return _processResponse(response);
    } catch (e) {
      debugPrint('[API Client] GET Error: $e');
      rethrow;
    }
  }

  // POST request
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final String url = '${EnvConfig.baseUrl}$endpoint';
    final headers = await _getHeaders();

    try {
      debugPrint('[API Client] POST -> $url');
      final response = await _client.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(body),
      ).timeout(const Duration(seconds: 15));
      return _processResponse(response);
    } catch (e) {
      debugPrint('[API Client] POST Error: $e');
      rethrow;
    }
  }

  // DELETE request
  Future<dynamic> delete(String endpoint) async {
    final String url = '${EnvConfig.baseUrl}$endpoint';
    final headers = await _getHeaders();

    try {
      debugPrint('[API Client] DELETE -> $url');
      final response = await _client.delete(Uri.parse(url), headers: headers).timeout(
        const Duration(seconds: 15),
      );
      return _processResponse(response);
    } catch (e) {
      debugPrint('[API Client] DELETE Error: $e');
      rethrow;
    }
  }
}
