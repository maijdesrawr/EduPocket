import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';

abstract interface class ProfileEmailApi {
  Future<VerifiedEmailStatus> getStatus({
    required String role,
    required String id,
  });

  Future<EmailVerificationRequestResult> requestVerification({
    required String role,
    required String id,
    required String currentPassword,
    required String email,
  });

  Future<EmailVerificationResult> verify({
    required String challengeToken,
    required String code,
  });

  Future<EmailVerificationChallenge> resend({
    required String challengeToken,
  });
}

class VerifiedEmailStatus {
  final bool verified;
  final String? emailMasked;

  const VerifiedEmailStatus({
    required this.verified,
    this.emailMasked,
  });
}

class EmailVerificationChallenge {
  final String challengeToken;
  final String? destination;
  final int expiresIn;
  final int? attemptsRemaining;
  final int resendAfter;

  const EmailVerificationChallenge({
    required this.challengeToken,
    this.destination,
    required this.expiresIn,
    this.attemptsRemaining,
    required this.resendAfter,
  });
}

class EmailVerificationRequestResult {
  final bool verificationComplete;
  final bool alreadyVerified;
  final String message;
  final String? emailMasked;
  final EmailVerificationChallenge? challenge;

  const EmailVerificationRequestResult({
    required this.verificationComplete,
    required this.alreadyVerified,
    required this.message,
    this.emailMasked,
    this.challenge,
  });
}

class EmailVerificationResult {
  final String message;
  final String? emailMasked;
  final bool verificationComplete;
  final String? nextStep;
  final EmailVerificationChallenge? nextChallenge;

  const EmailVerificationResult({
    required this.message,
    this.emailMasked,
    this.verificationComplete = true,
    this.nextStep,
    this.nextChallenge,
  });
}

class ProfileEmailException implements Exception {
  final String message;
  final int? attemptsRemaining;
  final int? retryAfter;

  const ProfileEmailException(
    this.message, {
    this.attemptsRemaining,
    this.retryAfter,
  });

  @override
  String toString() => message;
}

class ProfileEmailService implements ProfileEmailApi {
  final http.Client _client;
  final Duration timeout;

  ProfileEmailService({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  @override
  Future<VerifiedEmailStatus> getStatus({
    required String role,
    required String id,
  }) async {
    final data = await _post('get_verified_email.php', {
      'role': role,
      'id': id,
    });

    return VerifiedEmailStatus(
      verified: _asBool(data['verified']),
      emailMasked: _optionalString(data['email_masked']),
    );
  }

  @override
  Future<EmailVerificationRequestResult> requestVerification({
    required String role,
    required String id,
    required String currentPassword,
    required String email,
  }) async {
    final data = await _post('request_email_verification.php', {
      'role': role,
      'id': id,
      'current_password': currentPassword,
      'email': email,
    });
    final alreadyVerified = _asBool(data['already_verified']);
    final complete = alreadyVerified || _asBool(data['verification_complete']);

    if (complete) {
      return EmailVerificationRequestResult(
        verificationComplete: true,
        alreadyVerified: alreadyVerified,
        message: _optionalString(data['message']) ??
            'This email address is already verified.',
        emailMasked: _optionalString(data['email_masked']),
      );
    }

    return EmailVerificationRequestResult(
      verificationComplete: false,
      alreadyVerified: false,
      message: _optionalString(data['message']) ??
          'Enter the verification code sent to your email.',
      emailMasked: _optionalString(data['email_masked']),
      challenge: _challengeFrom(data),
    );
  }

  @override
  Future<EmailVerificationResult> verify({
    required String challengeToken,
    required String code,
  }) async {
    final data = await _post('verify_email_verification.php', {
      'challenge_token': challengeToken,
      'code': code,
    });
    final complete = data['verification_complete'] == null
        ? true
        : _asBool(data['verification_complete']);

    return EmailVerificationResult(
      message: _optionalString(data['message']) ??
          (complete
              ? 'Your email address is now verified.'
              : 'Now verify the code sent to your new email address.'),
      emailMasked: _optionalString(data['email_masked']),
      verificationComplete: complete,
      nextStep: _optionalString(data['next_step']),
      nextChallenge: complete ? null : _challengeFrom(data),
    );
  }

  @override
  Future<EmailVerificationChallenge> resend({
    required String challengeToken,
  }) async {
    final data = await _post('resend_email_verification_otp.php', {
      'challenge_token': challengeToken,
    });
    return _challengeFrom(data);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, String> body,
  ) async {
    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(ApiConfig.url(endpoint)),
            headers: AppSessionService.instance.authorizationHeaders,
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ProfileEmailException(
        'The server took too long to respond. Please try again.',
      );
    } on ProfileEmailException {
      rethrow;
    } catch (_) {
      throw const ProfileEmailException(
        'Unable to connect to EduPocket. Check your connection and try again.',
      );
    }

    await AppSessionService.instance.handleResponse(response);

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException();
      }
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ProfileEmailException(
        'The server returned an invalid response. Please contact support.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['status']?.toString().toLowerCase() != 'success') {
      throw ProfileEmailException(
        _optionalString(data['message']) ??
            'The email request could not be completed.',
        attemptsRemaining: _asNullableInt(data['attempts_remaining']),
        retryAfter: _asNullableInt(data['retry_after']),
      );
    }

    return data;
  }

  EmailVerificationChallenge _challengeFrom(Map<String, dynamic> data) {
    final token = _optionalString(data['challenge_token']);
    if (token == null) {
      throw const ProfileEmailException(
        'The server did not create a verification request.',
      );
    }

    return EmailVerificationChallenge(
      challengeToken: token,
      destination: _optionalString(data['destination']),
      expiresIn: _asPositiveInt(data['expires_in'], fallback: 300),
      attemptsRemaining: _asNullableInt(data['attempts_remaining']),
      resendAfter: _asPositiveInt(data['resend_after'], fallback: 60),
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  static int _asPositiveInt(Object? value, {required int fallback}) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : fallback;
  }

  static int? _asNullableInt(Object? value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
