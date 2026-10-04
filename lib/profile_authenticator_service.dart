import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';

enum AuthenticatorAction {
  enroll('enroll'),
  remove('remove');

  const AuthenticatorAction(this.value);

  final String value;
}

abstract interface class ProfileAuthenticatorApi {
  Future<AuthenticatorStatus> getStatus({
    required String role,
    required String userId,
    required String currentPassword,
  });

  Future<AuthenticatorManagementChallenge> requestManagement({
    required String role,
    required String userId,
    required AuthenticatorAction action,
    required String currentPassword,
  });

  Future<AuthenticatorManagementResult> verifyManagement({
    required String role,
    required String userId,
    required AuthenticatorAction action,
    required String challengeToken,
    required String authenticatorCode,
  });
}

class AuthenticatorStatus {
  const AuthenticatorStatus({required this.isEnrolled});

  final bool isEnrolled;
}

class AuthenticatorManagementChallenge {
  const AuthenticatorManagementChallenge({
    required this.challengeToken,
    required this.action,
    required this.expiresIn,
    required this.message,
    this.attemptsRemaining,
    this.setupKey,
    this.otpauthUri,
  });

  final String challengeToken;
  final AuthenticatorAction action;
  final int expiresIn;
  final int? attemptsRemaining;
  final String message;
  final String? setupKey;
  final String? otpauthUri;
}

class AuthenticatorManagementResult {
  const AuthenticatorManagementResult({
    required this.isEnrolled,
    required this.message,
  });

  final bool isEnrolled;
  final String message;
}

class ProfileAuthenticatorException implements Exception {
  const ProfileAuthenticatorException(
    this.message, {
    this.attemptsRemaining,
    this.retryAfter,
  });

  final String message;
  final int? attemptsRemaining;
  final int? retryAfter;

  @override
  String toString() => message;
}

class ProfileAuthenticatorService implements ProfileAuthenticatorApi {
  ProfileAuthenticatorService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<AuthenticatorStatus> getStatus({
    required String role,
    required String userId,
    required String currentPassword,
  }) async {
    final data = await _post('authenticator_status.php', {
      'role': role,
      'user_id': userId,
      'current_password': currentPassword,
    });
    final enrollmentValue = data['enrolled'] ??
        data['authenticator_bound'] ??
        data['is_enrolled'] ??
        data['bound'];
    if (enrollmentValue == null) {
      throw const ProfileAuthenticatorException(
        'The server returned an incomplete authenticator status.',
      );
    }
    return AuthenticatorStatus(isEnrolled: _asBool(enrollmentValue));
  }

  @override
  Future<AuthenticatorManagementChallenge> requestManagement({
    required String role,
    required String userId,
    required AuthenticatorAction action,
    required String currentPassword,
  }) async {
    final data = await _post('request_authenticator_management.php', {
      'role': role,
      'user_id': userId,
      'action': action.value,
      'current_password': currentPassword,
    });

    final token = _optionalString(data['challenge_token']);
    if (token == null) {
      throw const ProfileAuthenticatorException(
        'The server did not create an authenticator request.',
      );
    }

    final setupKey = _optionalString(
      data['setup_key'] ?? data['totp_setup_key'],
    );
    final otpauthUri = _optionalString(data['otpauth_uri']);
    if (action == AuthenticatorAction.enroll &&
        (setupKey == null || otpauthUri == null)) {
      throw const ProfileAuthenticatorException(
        'The server did not return complete authenticator setup details.',
      );
    }

    return AuthenticatorManagementChallenge(
      challengeToken: token,
      action: _parseAction(data['action'], fallback: action),
      expiresIn: _asNonNegativeInt(data['expires_in'], fallback: 300),
      attemptsRemaining: _asNullableNonNegativeInt(
        data['attempts_remaining'],
      ),
      message: _optionalString(data['message']) ??
          (action == AuthenticatorAction.enroll
              ? 'Scan the QR code or enter the setup key, then confirm the 6-digit code.'
              : 'Enter the current 6-digit code from your authenticator app.'),
      setupKey: setupKey,
      otpauthUri: otpauthUri,
    );
  }

  @override
  Future<AuthenticatorManagementResult> verifyManagement({
    required String role,
    required String userId,
    required AuthenticatorAction action,
    required String challengeToken,
    required String authenticatorCode,
  }) async {
    final data = await _post('verify_authenticator_management.php', {
      'role': role,
      'user_id': userId,
      'action': action.value,
      'challenge_token': challengeToken,
      'authenticator_code': authenticatorCode,
    });
    final enrollmentValue = data['enrolled'] ??
        data['authenticator_bound'] ??
        data['is_enrolled'] ??
        data['bound'];

    return AuthenticatorManagementResult(
      isEnrolled: enrollmentValue == null
          ? action == AuthenticatorAction.enroll
          : _asBool(enrollmentValue),
      message: _optionalString(data['message']) ??
          (action == AuthenticatorAction.enroll
              ? 'Google Authenticator was linked successfully.'
              : 'Google Authenticator was removed successfully.'),
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
      throw const ProfileAuthenticatorException(
        'The server took too long to respond. Please try again.',
      );
    } on ProfileAuthenticatorException {
      rethrow;
    } catch (_) {
      throw const ProfileAuthenticatorException(
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
      throw const ProfileAuthenticatorException(
        'The server returned an invalid response. Please contact support.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['status']?.toString().toLowerCase() != 'success') {
      throw ProfileAuthenticatorException(
        _optionalString(data['message']) ??
            'The authenticator request could not be completed.',
        attemptsRemaining: _asNullableNonNegativeInt(
          data['attempts_remaining'],
        ),
        retryAfter: _asNullableNonNegativeInt(data['retry_after']),
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
      throw const ProfileAuthenticatorException(
        'The authenticator server address is invalid.',
      );
    }
  }

  void _requireProtectedTransport(Uri uri) {
    if (ApiConfig.usesProtectedOrLocalTransport(uri)) return;

    throw const ProfileAuthenticatorException(
      'Authenticator management requires HTTPS outside the local development network.',
    );
  }

  static AuthenticatorAction _parseAction(
    Object? value, {
    required AuthenticatorAction fallback,
  }) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final action in AuthenticatorAction.values) {
      if (action.value == normalized) return action;
    }
    return fallback;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  static int _asNonNegativeInt(Object? value, {required int fallback}) {
    return _asNullableNonNegativeInt(value) ?? fallback;
  }

  static int? _asNullableNonNegativeInt(Object? value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
