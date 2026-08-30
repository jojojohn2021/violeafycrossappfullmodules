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
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final isHtml = contentType.contains('text/html') || response.body.trimLeft().startsWith('<!doctype html');
    if (isHtml) {
      throw ServerException(
        'The backend API is not available at this address. Configure production API routing.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return json.decode(response.body);
    } else {
      String errorMessage = 'Request failed with status ${response.statusCode}';
      try {
        if (response.body.isNotEmpty) {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
            errorMessage = decoded['error'].toString();
          }
        }
      } catch (_) {}

      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('[API Client] Auth error (${response.statusCode}): $errorMessage');
        throw AuthException(errorMessage, statusCode: response.statusCode);
      }
      debugPrint('[API Client] Call failed (${response.statusCode}): $errorMessage');
      throw ServerException(errorMessage, statusCode: response.statusCode);
    }
  }

  // Helper to build list of target URLs to attempt (Primary URL + Fallbacks)
  List<String> _buildCandidateUrls(String endpoint) {
    final primaryBase = EnvConfig.baseUrl;
    final candidates = <String>[];
    if (primaryBase.isNotEmpty) {
      candidates.add('$primaryBase$endpoint');
    }
    for (final fallbackBase in EnvConfig.fallbackBaseUrls) {
      final full = '$fallbackBase$endpoint';
      if (!candidates.contains(full)) {
        candidates.add(full);
      }
    }
    return candidates;
  }

  // GET request
  Future<dynamic> get(String endpoint) async {
    final candidateUrls = _buildCandidateUrls(endpoint);
    final headers = await _getHeaders();
    Object? lastError;

    for (final url in candidateUrls) {
      try {
        debugPrint('[API Client] GET -> $url');
        final response = await _client.get(Uri.parse(url), headers: headers).timeout(
          const Duration(seconds: 10),
        );
        final contentType = response.headers['content-type']?.toLowerCase() ?? '';
        final isHtml = contentType.contains('text/html') || response.body.trimLeft().startsWith('<!doctype html');
        if (isHtml) {
          debugPrint('[API Client] $url returned HTML (static web page), trying next fallback...');
          lastError = ServerException(
            'The backend API is not available at this address. Configure production API routing.',
            statusCode: response.statusCode,
          );
          continue;
        }

        final result = _processResponse(response);
        final workingBaseUrl = url.replaceAll(endpoint, '');
        if (workingBaseUrl != EnvConfig.baseUrl) {
          EnvConfig.setCustomBaseUrl(workingBaseUrl);
        }
        return result;
      } catch (e) {
        debugPrint('[API Client] GET Error for $url: $e');
        lastError = e;
      }
    }

    if (lastError != null) throw lastError;
    throw ServerException('The backend API is not available at this address. Configure production API routing.');
  }

  // POST request
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final candidateUrls = _buildCandidateUrls(endpoint);
    final headers = await _getHeaders();
    Object? lastError;

    for (final url in candidateUrls) {
      try {
        debugPrint('[API Client] POST -> $url');
        final response = await _client.post(
          Uri.parse(url),
          headers: headers,
          body: json.encode(body),
        ).timeout(const Duration(seconds: 10));

        final contentType = response.headers['content-type']?.toLowerCase() ?? '';
        final isHtml = contentType.contains('text/html') || response.body.trimLeft().startsWith('<!doctype html');
        if (isHtml) {
          debugPrint('[API Client] $url returned HTML (static web page), trying next fallback...');
          lastError = ServerException(
            'The backend API is not available at this address. Configure production API routing.',
            statusCode: response.statusCode,
          );
          continue;
        }

        final result = _processResponse(response);
        final workingBaseUrl = url.replaceAll(endpoint, '');
        if (workingBaseUrl != EnvConfig.baseUrl) {
          EnvConfig.setCustomBaseUrl(workingBaseUrl);
        }
        return result;
      } catch (e) {
        debugPrint('[API Client] POST Error for $url: $e');
        lastError = e;
      }
    }

    if (lastError != null) throw lastError;
    throw ServerException('The backend API is not available at this address. Configure production API routing.');
  }

  // DELETE request
  Future<dynamic> delete(String endpoint) async {
    final candidateUrls = _buildCandidateUrls(endpoint);
    final headers = await _getHeaders();
    Object? lastError;

    for (final url in candidateUrls) {
      try {
        debugPrint('[API Client] DELETE -> $url');
        final response = await _client.delete(Uri.parse(url), headers: headers).timeout(
          const Duration(seconds: 10),
        );
        final contentType = response.headers['content-type']?.toLowerCase() ?? '';
        final isHtml = contentType.contains('text/html') || response.body.trimLeft().startsWith('<!doctype html');
        if (isHtml) {
          debugPrint('[API Client] $url returned HTML (static web page), trying next fallback...');
          lastError = ServerException(
            'The backend API is not available at this address. Configure production API routing.',
            statusCode: response.statusCode,
          );
          continue;
        }

        final result = _processResponse(response);
        final workingBaseUrl = url.replaceAll(endpoint, '');
        if (workingBaseUrl != EnvConfig.baseUrl) {
          EnvConfig.setCustomBaseUrl(workingBaseUrl);
        }
        return result;
      } catch (e) {
        debugPrint('[API Client] DELETE Error for $url: $e');
        lastError = e;
      }
    }

    if (lastError != null) throw lastError;
    throw ServerException('The backend API is not available at this address. Configure production API routing.');
  }
}
