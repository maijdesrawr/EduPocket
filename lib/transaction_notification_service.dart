import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'app_session_service.dart';

class TransactionNotificationService {
  TransactionNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'edupocket/notifications',
  );
  static const Duration _pollInterval = Duration(seconds: 15);

  static Timer? _timer;
  static String? _role;
  static String? _accountSource;
  static String? _userId;
  static int _lastNotificationId = 0;
  static int _activationGeneration = 0;
  static int? _pollingGeneration;
  static final _lifecycleObserver = _TransactionNotificationLifecycleObserver();
  static bool _observingLifecycle = false;

  static Future<void> activate({
    required String role,
    required String accountSource,
    required String userId,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    final normalizedAccountSource = accountSource.trim().toLowerCase();
    final normalizedUserId = userId.trim();
    if (normalizedRole.isEmpty ||
        normalizedAccountSource.isEmpty ||
        normalizedUserId.isEmpty) {
      return;
    }

    final generation = ++_activationGeneration;
    _timer?.cancel();
    _timer = null;
    _role = normalizedRole;
    _accountSource = normalizedAccountSource;
    _userId = normalizedUserId;
    _observeLifecycle();
    final preferences = await SharedPreferences.getInstance();
    if (!_isCurrentActivation(
      generation,
      normalizedRole,
      normalizedAccountSource,
      normalizedUserId,
    )) {
      return;
    }
    _lastNotificationId = preferences.getInt(
          _preferenceKey(
            normalizedRole,
            normalizedAccountSource,
            normalizedUserId,
          ),
        ) ??
        0;

    var canNotify = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        canNotify =
            await _channel.invokeMethod<bool>('requestPermission') ?? false;
      } on PlatformException catch (error) {
        debugPrint('Notification permission request failed: $error');
        canNotify = false;
      }
    }

    if (!_isCurrentActivation(
      generation,
      normalizedRole,
      normalizedAccountSource,
      normalizedUserId,
    )) {
      return;
    }
    if (canNotify) await _poll(generation);
    if (!_isCurrentActivation(
      generation,
      normalizedRole,
      normalizedAccountSource,
      normalizedUserId,
    )) {
      return;
    }
    _timer = Timer.periodic(
      _pollInterval,
      (_) => unawaited(_poll(generation)),
    );
  }

  static void deactivate() {
    _activationGeneration++;
    _timer?.cancel();
    _timer = null;
    _role = null;
    _accountSource = null;
    _userId = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
      _observingLifecycle = false;
    }
  }

  static Future<void> refreshNow() => _poll(_activationGeneration);

  static String _preferenceKey(
    String role,
    String accountSource,
    String userId,
  ) =>
      'transaction_notification_cursor_v2_${role}_${accountSource}_$userId';

  static void _observeLifecycle() {
    if (_observingLifecycle) return;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _observingLifecycle = true;
  }

  static bool _isCurrentActivation(
    int generation,
    String role,
    String accountSource,
    String userId,
  ) =>
      generation == _activationGeneration &&
      role == _role &&
      accountSource == _accountSource &&
      userId == _userId;

  static Future<void> _poll(int generation) async {
    final role = _role;
    final accountSource = _accountSource;
    final userId = _userId;
    if (role == null ||
        accountSource == null ||
        userId == null ||
        !_isCurrentActivation(generation, role, accountSource, userId) ||
        _pollingGeneration == generation) {
      return;
    }
    _pollingGeneration = generation;
    var cursor = _lastNotificationId;
    try {
      final uri =
          Uri.parse(ApiConfig.url('get_account_notifications.php')).replace(
        queryParameters: {
          'role': role,
          'account_source': accountSource,
          'user_id': userId,
          'after_id': cursor.toString(),
        },
      );
      final response = await http
          .get(
            uri,
            headers: AppSessionService.instance.authorizationHeaders,
          )
          .timeout(const Duration(seconds: 8));
      if (!_isCurrentActivation(generation, role, accountSource, userId)) {
        return;
      }
      if (await AppSessionService.instance.handleResponse(response)) return;
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != 'success') {
        return;
      }

      final rawNotifications = decoded['notifications'];
      var deliveryBlocked = false;
      if (rawNotifications is List) {
        for (final raw in rawNotifications) {
          if (raw is! Map) continue;
          final notification = Map<String, dynamic>.from(raw);
          final notificationId =
              int.tryParse('${notification['notification_id']}') ?? 0;
          final transactionId =
              int.tryParse('${notification['transaction_id']}') ?? 0;
          final title = (notification['title'] ?? 'EduPocket').toString();
          final body = (notification['body'] ?? '').toString();
          if (notificationId <= cursor) continue;
          final shown = await _showNativeNotification(
            notificationId: notificationId,
            transactionId: transactionId,
            title: title,
            body: body,
          );
          if (!_isCurrentActivation(generation, role, accountSource, userId)) {
            return;
          }
          if (!shown) {
            deliveryBlocked = true;
            break;
          }
          cursor = notificationId;
        }
      }

      final serverLatest = int.tryParse('${decoded['latest_id']}') ?? 0;
      if (!deliveryBlocked && serverLatest > cursor) {
        cursor = serverLatest;
      }
      if (!_isCurrentActivation(generation, role, accountSource, userId)) {
        return;
      }
      _lastNotificationId = cursor;
      final preferences = await SharedPreferences.getInstance();
      if (!_isCurrentActivation(generation, role, accountSource, userId)) {
        return;
      }
      await preferences.setInt(
        _preferenceKey(role, accountSource, userId),
        cursor,
      );
    } on TimeoutException {
      debugPrint('Transaction notification poll timed out.');
    } catch (error) {
      debugPrint('Transaction notification poll failed: $error');
    } finally {
      if (_pollingGeneration == generation) {
        _pollingGeneration = null;
      }
    }
  }

  static Future<bool> _showNativeNotification({
    required int notificationId,
    required int transactionId,
    required String title,
    required String body,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('showTransactionNotification', {
            'notificationId': notificationId,
            'transactionId': transactionId,
            'title': title,
            'body': body,
          }) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('Native transaction notification failed: $error');
      return false;
    }
  }
}

class _TransactionNotificationLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(TransactionNotificationService.refreshNow());
    }
  }
}
