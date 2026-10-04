import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';

enum LoginOtpMethod {
  totp('totp'),
  email('email');

  const LoginOtpMethod(this.value);

  final String value;
}

abstract class LoginAttempt {
  const LoginAttempt();
}

class LoginAuthenticated extends LoginAttempt {
  const LoginAuthenticated(this.user);

  final LoginUser user;
}

class LoginOtpRequired extends LoginAttempt {
  const LoginOtpRequired(this.challenge);

  final LoginOtpChallenge challenge;
}

class LoginUser {
  const LoginUser({
    required this.role,
    required this.accountSource,
    required this.id,
    required this.name,
    required this.passwordChanged,
    required this.sessionToken,
    required this.sessionExpiresAtEpochSeconds,
  });

  final String role;
  final String accountSource;
  final String id;
  final String name;
  final bool passwordChanged;
  final String sessionToken;
  final int sessionExpiresAtEpochSeconds;
}

class LoginOtpChallenge {
  const LoginOtpChallenge({
    required this.challengeToken,
    required this.method,
    required this.availableMethods,
    required this.expiresIn,
    required this.resendAfter,
    required this.message,
    this.destinationMasked,
  });

  final String challengeToken;
  final LoginOtpMethod method;
  final List<LoginOtpMethod> availableMethods;
  final String? destinationMasked;
  final int expiresIn;
  final int resendAfter;
  final String message;
}

class LoginException implements Exception {
  const LoginException(
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

abstract interface class LoginApi {
  Future<LoginAttempt> login({
    required String id,
    required String password,
  });

  Future<LoginOtpChallenge> requestOtp({
    required LoginOtpChallenge challenge,
    required LoginOtpMethod method,
  });

  Future<LoginUser> verifyOtp({
    required String challengeToken,
    required String code,
  });
}

class LoginService implements LoginApi {
  LoginService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 12),
    Future<String> Function()? deviceIdProvider,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _deviceIdProvider =
            deviceIdProvider ?? AppSessionService.instance.getDeviceId;

  final http.Client _client;
  final String _baseUrl;
  final Future<String> Function() _deviceIdProvider;
  final Duration timeout;

  @override
  Future<LoginAttempt> login({
    required String id,
    required String password,
  }) async {
    final deviceId = await _deviceIdProvider();
    final data = await _post('login.php', {
      'id': id,
      'password': password,
      'device_id': deviceId,
    });
    final status = _optionalString(data['status'])?.toLowerCase();
    if (status == 'success') {
      return LoginAuthenticated(_parseUser(data));
    }
    if (status == 'otp_required') {
      return LoginOtpRequired(_parseChallenge(data));
    }
    throw LoginException(
      _optionalString(data['message']) ?? 'Invalid user ID or password.',
      attemptsRemaining: _asNullableNonNegativeInt(
        data['remaining_attempts'] ?? data['attempts_remaining'],
      ),
      retryAfter: _asNullableNonNegativeInt(data['retry_after']),
    );
  }

  @override
  Future<LoginOtpChallenge> requestOtp({
    required LoginOtpChallenge challenge,
    required LoginOtpMethod method,
  }) async {
    final deviceId = await _deviceIdProvider();
    final data = await _post('request_login_otp.php', {
      'challenge_token': challenge.challengeToken,
      'method': method.value,
      'device_id': deviceId,
    });
    _requireSuccess(
      data,
      fallbackMessage: 'The verification code could not be requested.',
    );
    return _parseChallenge(
      data,
      fallbackToken: challenge.challengeToken,
      fallbackMethods: challenge.availableMethods,
      fallbackMethod: method,
    );
  }

  @override
  Future<LoginUser> verifyOtp({
    required String challengeToken,
    required String code,
  }) async {
    final deviceId = await _deviceIdProvider();
    final data = await _post('verify_login_otp.php', {
      'challenge_token': challengeToken,
      'code': code,
      'device_id': deviceId,
    });
    _requireSuccess(
      data,
      fallbackMessage: 'Login verification could not be completed.',
    );
    return _parseUser(data);
  }

  void close() => _client.close();

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> body,
  ) async {
    final uri = _endpointUri(endpoint);
    _requireProtectedTransport(uri);

    late http.Response response;
    try {
      response = await _client.post(uri, body: body).timeout(timeout);
    } on TimeoutException {
      throw LoginException(
        'The server took too long to respond. Check your connection and try again.',
      );
    } on LoginException {
      rethrow;
    } catch (_) {
      throw const LoginException(
        'Unable to connect to EduPocket. Check your connection and try again.',
      );
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const LoginException(
        'The server returned an invalid response. Please contact support.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final endpointMissing = response.statusCode == 404;
      throw LoginException(
        _optionalString(data['message']) ??
            (endpointMissing
                ? 'The login service is not available on this server.'
                : 'The server could not complete the request.'),
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
      throw const LoginException('The EduPocket server address is invalid.');
    }
  }

  void _requireProtectedTransport(Uri uri) {
    if (ApiConfig.usesProtectedOrLocalTransport(uri)) return;

    throw const LoginException(
      'Login requires HTTPS outside the local development network.',
    );
  }

  static void _requireSuccess(
    Map<String, dynamic> data, {
    required String fallbackMessage,
  }) {
    if (_optionalString(data['status'])?.toLowerCase() == 'success') return;
    throw LoginException(
      _optionalString(data['message']) ?? fallbackMessage,
      attemptsRemaining: _asNullableNonNegativeInt(
        data['remaining_attempts'] ?? data['attempts_remaining'],
      ),
      retryAfter: _asNullableNonNegativeInt(data['retry_after']),
    );
  }

  static LoginUser _parseUser(Map<String, dynamic> data) {
    final role = _optionalString(data['role'])?.toLowerCase();
    final accountSource =
        _optionalString(data['account_source'])?.toLowerCase();
    final id = _optionalString(data['id']);
    final sessionToken = _optionalString(data['session_token']);
    final sessionExpiry = _parseSessionExpiry(data);
    if (role == null ||
        accountSource == null ||
        id == null ||
        sessionToken == null ||
        sessionExpiry == null) {
      throw const LoginException(
        'The server returned incomplete secure-session details. Please contact support.',
      );
    }
    return LoginUser(
      role: role,
      accountSource: accountSource,
      id: id,
      name: _optionalString(data['name']) ?? id,
      passwordChanged: _asBool(data['password_changed'], fallback: true),
      sessionToken: sessionToken,
      sessionExpiresAtEpochSeconds: sessionExpiry,
    );
  }

  static LoginOtpChallenge _parseChallenge(
    Map<String, dynamic> data, {
    String? fallbackToken,
    List<LoginOtpMethod>? fallbackMethods,
    LoginOtpMethod? fallbackMethod,
  }) {
    final token = _optionalString(data['challenge_token']) ?? fallbackToken;
    final method = _parseMethod(data['method']) ?? fallbackMethod;
    if (token == null || method == null) {
      throw const LoginException(
        'The server returned an incomplete login verification request.',
      );
    }

    final parsedMethods = <LoginOtpMethod>[];
    final rawMethods = data['available_methods'];
    if (rawMethods is List) {
      for (final rawMethod in rawMethods) {
        final parsed = _parseMethod(rawMethod);
        if (parsed != null && !parsedMethods.contains(parsed)) {
          parsedMethods.add(parsed);
        }
      }
    }
    if (parsedMethods.isEmpty && fallbackMethods != null) {
      parsedMethods.addAll(fallbackMethods);
    }
    if (!parsedMethods.contains(method)) parsedMethods.insert(0, method);

    final destination = _optionalString(data['destination_masked']);
    final defaultMessage = method == LoginOtpMethod.email
        ? 'Enter the 6-digit code sent to your verified email.'
        : 'Enter the current 6-digit code from Google Authenticator.';
    return LoginOtpChallenge(
      challengeToken: token,
      method: method,
      availableMethods: List.unmodifiable(parsedMethods),
      destinationMasked: destination,
      expiresIn: _asNonNegativeInt(
        data['expires_in'],
        fallback: 300,
      ).clamp(0, 300).toInt(),
      resendAfter: _asNonNegativeInt(
        data['resend_after'],
        fallback: method == LoginOtpMethod.email ? 60 : 0,
      ),
      message: _optionalString(data['message']) ?? defaultMessage,
    );
  }

  static LoginOtpMethod? _parseMethod(Object? value) {
    final normalized = _optionalString(value)?.toLowerCase();
    for (final method in LoginOtpMethod.values) {
      if (method.value == normalized) return method;
    }
    return null;
  }

  static bool _asBool(Object? value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
    return fallback;
  }

  static int _asNonNegativeInt(Object? value, {required int fallback}) {
    return _asNullableNonNegativeInt(value) ?? fallback;
  }

  static int? _asNullableNonNegativeInt(Object? value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static int? _parseSessionExpiry(Map<String, dynamic> data) {
    final absoluteValue = data['session_expires_at'];
    if (absoluteValue is num) {
      final value = absoluteValue.toInt();
      return value > 20000000000 ? value ~/ 1000 : value;
    }
    final absoluteText = _optionalString(absoluteValue);
    if (absoluteText != null) {
      final numeric = int.tryParse(absoluteText);
      if (numeric != null) {
        return numeric > 20000000000 ? numeric ~/ 1000 : numeric;
      }
      final parsed = DateTime.tryParse(absoluteText);
      if (parsed != null) {
        return parsed.toUtc().millisecondsSinceEpoch ~/ 1000;
      }
    }

    final expiresIn = _asNullableNonNegativeInt(
      data['session_expires_in'] ?? data['expires_in'],
    );
    if (expiresIn == null || expiresIn == 0) return null;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
