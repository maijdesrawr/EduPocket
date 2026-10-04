import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_session_service.dart';

abstract interface class StudentTransferApi {
  Future<double> fetchBalance({required String studentId});

  Future<StudentTransferResult> transfer({
    required String senderId,
    required String recipientId,
    required String amount,
    required String pin,
    required String clientRequestId,
  });
}

class StudentTransferResult {
  const StudentTransferResult({
    required this.message,
    required this.transferId,
    required this.newBalance,
    this.senderTransactionId,
    this.recipientTransactionId,
    this.recipientName,
  });

  final String message;
  final int transferId;
  final double newBalance;
  final int? senderTransactionId;
  final int? recipientTransactionId;
  final String? recipientName;
}

class StudentTransferException implements Exception {
  const StudentTransferException(
    this.message, {
    this.outcomeUnknown = false,
  });

  final String message;
  final bool outcomeUnknown;

  @override
  String toString() => message;
}

class StudentTransferService implements StudentTransferApi {
  StudentTransferService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;

  @override
  Future<double> fetchBalance({required String studentId}) async {
    final uri = _endpointUri('student_topups.php').replace(
      queryParameters: {'student_id': studentId},
    );
    final data = await _request(() => _client.get(
          uri,
          headers: AppSessionService.instance.authorizationHeaders,
        ));
    final balance = double.tryParse(data['total_balance']?.toString() ?? '');
    if (balance == null || !balance.isFinite || balance < 0) {
      throw const StudentTransferException(
        'The server returned an invalid wallet balance.',
      );
    }
    return balance;
  }

  @override
  Future<StudentTransferResult> transfer({
    required String senderId,
    required String recipientId,
    required String amount,
    required String pin,
    required String clientRequestId,
  }) async {
    final data = await _request(
      () => _client.post(
        _endpointUri('student_transfer.php'),
        headers: AppSessionService.instance.authorizationHeaders,
        body: {
          'sender_id': senderId,
          'recipient_id': recipientId,
          'amount': amount,
          'pin': pin,
          'client_request_id': clientRequestId,
        },
      ),
      transferOutcomeCanBeUnknown: true,
    );

    final transferId = int.tryParse(data['transfer_id']?.toString() ?? '');
    final newBalance = double.tryParse(
      data['new_balance']?.toString() ?? '',
    );
    if (transferId == null || transferId <= 0 || newBalance == null) {
      throw const StudentTransferException(
        'The server returned an incomplete transfer confirmation.',
      );
    }

    return StudentTransferResult(
      message:
          _optionalString(data['message']) ?? 'Funds transferred successfully.',
      transferId: transferId,
      newBalance: newBalance,
      senderTransactionId:
          int.tryParse(data['sender_transaction_id']?.toString() ?? ''),
      recipientTransactionId:
          int.tryParse(data['recipient_transaction_id']?.toString() ?? ''),
      recipientName: _optionalString(data['recipient_name']),
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send, {
    bool transferOutcomeCanBeUnknown = false,
  }) async {
    late http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      throw StudentTransferException(
        'The server took too long to respond. You can safely retry.',
        outcomeUnknown: transferOutcomeCanBeUnknown,
      );
    } on StudentTransferException {
      rethrow;
    } catch (_) {
      throw StudentTransferException(
        'Unable to reach EduPocket. Check your connection and try again.',
        outcomeUnknown: transferOutcomeCanBeUnknown,
      );
    }

    await AppSessionService.instance.handleResponse(response);

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const StudentTransferException(
        'The server returned an invalid transfer response.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data['status']?.toString().toLowerCase() != 'success') {
      throw StudentTransferException(
        _optionalString(data['message']) ??
            'The transfer could not be completed.',
      );
    }
    return data;
  }

  Uri _endpointUri(String endpoint) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final path = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    final uri = Uri.parse('$base/$path');
    if (!ApiConfig.usesProtectedOrLocalTransport(uri)) {
      throw const StudentTransferException(
        'Fund transfers require HTTPS outside the local development network.',
      );
    }
    return uri;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
