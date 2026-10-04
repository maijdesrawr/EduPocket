import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';

abstract interface class ProfilePinApi {
  Future<ProfilePinStatus> getStatus({
    required String role,
    required String userId,
    required String currentPassword,
  });

  Future<ProfilePinChangeResult> changePin({
    required String role,
    required String userId,
    required String currentPassword,
    required String currentPin,
    required String newPin,
  });
}

class ProfilePinStatus {
  const ProfilePinStatus({required this.hasPin});

  final bool hasPin;
}

class ProfilePinChangeResult {
  const ProfilePinChangeResult({required this.message});

  final String message;
}

class ProfilePinException implements Exception {
  const ProfilePinException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProfilePinService implements ProfilePinApi {
  ProfilePinService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<ProfilePinStatus> getStatus({
    required String role,
    required String userId,
    required String currentPassword,
  }) async {
    final data = await _post('pin_status.php', {
      'role': role,
      'user_id': userId,
      'current_password': currentPassword,
    });
    if (!data.containsKey('has_pin')) {
      throw const ProfilePinException(
        'The server returned an incomplete PIN status.',
      );
    }
    return ProfilePinStatus(hasPin: _asBool(data['has_pin']));
  }

  @override
  Future<ProfilePinChangeResult> changePin({
    required String role,
    required String userId,
    required String currentPassword,
    required String currentPin,
    required String newPin,
  }) async {
    final data = await _post('change_pin.php', {
      'role': role,
      'user_id': userId,
      'current_password': currentPassword,
      'current_pin': currentPin,
      'new_pin': newPin,
    });
    return ProfilePinChangeResult(
      message: _optionalString(data['message']) ??
          'Your 6-digit PIN was changed successfully.',
    );
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> body,
  ) async {
    final uri = _endpointUri(endpoint);
    _requireProtectedTransport(uri);

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: AppSessionService.instance.authorizationHeaders,
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ProfilePinException(
        'The server took too long to respond. Please try again.',
      );
    } on ProfilePinException {
      rethrow;
    } catch (_) {
      throw const ProfilePinException(
        'Unable to connect to EduPocket. Check your connection and try again.',
      );
    }

    await AppSessionService.instance.handleResponse(response);

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ProfilePinException(
        'The server returned an invalid response. Please contact support.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['status']?.toString().toLowerCase() != 'success') {
      throw ProfilePinException(
        _optionalString(data['message']) ??
            'The PIN request could not be completed.',
      );
    }
    return data;
  }

  Uri _endpointUri(String endpoint) {
    final trimmedBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final trimmedEndpoint =
        endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    try {
      return Uri.parse('$trimmedBase/$trimmedEndpoint');
    } on FormatException {
      throw const ProfilePinException('The PIN server address is invalid.');
    }
  }

  void _requireProtectedTransport(Uri uri) {
    if (ApiConfig.usesProtectedOrLocalTransport(uri)) return;

    throw const ProfilePinException(
      'PIN management requires HTTPS outside the local development network.',
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
