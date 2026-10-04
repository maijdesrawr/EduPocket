import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_config.dart';

typedef InvalidSessionCallback = FutureOr<void> Function(String message);

class AppSessionException implements Exception {
  const AppSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppSessionService {
  AppSessionService({
    http.Client? client,
    String? baseUrl,
    Duration validationInterval = const Duration(seconds: 30),
    Duration inactivityTimeout = const Duration(minutes: 5),
    Future<SharedPreferences> Function()? preferencesLoader,
    Uuid? uuid,
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _validationInterval = validationInterval,
        _inactivityTimeout = inactivityTimeout,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now {
    if (validationInterval <= Duration.zero) {
      throw ArgumentError.value(
        validationInterval,
        'validationInterval',
        'must be greater than zero',
      );
    }
    if (inactivityTimeout <= Duration.zero) {
      throw ArgumentError.value(
        inactivityTimeout,
        'inactivityTimeout',
        'must be greater than zero',
      );
    }
  }

  static final AppSessionService instance = AppSessionService();

  static const _deviceIdKey = 'edupocket_installation_device_id';
  static const _tokenKey = 'edupocket_app_session_token';
  static const _roleKey = 'edupocket_app_session_role';
  static const _accountSourceKey = 'edupocket_app_session_account_source';
  static const _userIdKey = 'edupocket_app_session_user_id';
  static const _expiresAtKey = 'edupocket_app_session_expires_at_epoch';

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration _validationInterval;
  final Duration _inactivityTimeout;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Uuid _uuid;
  final DateTime Function() _now;

  Timer? _inactivityTimer;
  late final _AppSessionLifecycleObserver _lifecycleObserver =
      _AppSessionLifecycleObserver(this);
  bool _observingLifecycle = false;
  bool _validationInProgress = false;
  bool _invalidating = false;
  bool _isInBackground = false;
  int _generation = 0;

  String? _deviceId;
  String? _token;
  String? _role;
  String? _accountSource;
  String? _userId;
  int? _expiresAtEpochSeconds;
  DateTime? _lastUserActivityAt;
  DateTime? _lastSessionValidationAt;
  InvalidSessionCallback? _invalidSessionCallback;

  bool get hasActiveSession =>
      _token != null &&
      _role != null &&
      _accountSource != null &&
      _userId != null;

  String? get currentRole => _role;
  String? get currentAccountSource => _accountSource;
  String? get currentUserId => _userId;

  Map<String, String> get authorizationHeaders {
    final token = _token;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  void setInvalidSessionCallback(InvalidSessionCallback? callback) {
    _invalidSessionCallback = callback;
  }

  void registerUserActivity() {
    if (!hasActiveSession || _invalidating || _isInBackground) return;
    final activityAt = _now();
    _lastUserActivityAt = activityAt;
    _scheduleInactivityTimeout();
    final lastValidation = _lastSessionValidationAt;
    if (lastValidation == null ||
        activityAt.difference(lastValidation) >= _validationInterval) {
      unawaited(validate());
    }
  }

  Future<String> getDeviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;

    final preferences = await _preferencesLoader();
    final stored = preferences.getString(_deviceIdKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      _deviceId = stored;
      return stored;
    }

    final generated = 'edupocket-${_uuid.v4()}';
    await preferences.setString(_deviceIdKey, generated);
    _deviceId = generated;
    return generated;
  }

  Future<void> activate({
    required String token,
    required String role,
    required String accountSource,
    required String userId,
    required int expiresAtEpochSeconds,
  }) async {
    final normalizedToken = token.trim();
    final normalizedRole = role.trim().toLowerCase();
    final normalizedSource = accountSource.trim().toLowerCase();
    final normalizedUserId = userId.trim();
    if (normalizedToken.isEmpty ||
        normalizedRole.isEmpty ||
        normalizedSource.isEmpty ||
        normalizedUserId.isEmpty ||
        expiresAtEpochSeconds <= _now().millisecondsSinceEpoch ~/ 1000) {
      throw const AppSessionException(
        'The server returned an invalid app session. Please log in again.',
      );
    }

    final generation = ++_generation;
    _token = normalizedToken;
    _role = normalizedRole;
    _accountSource = normalizedSource;
    _userId = normalizedUserId;
    _expiresAtEpochSeconds = expiresAtEpochSeconds;
    _invalidating = false;
    _isInBackground = false;
    _lastUserActivityAt = _now();
    _lastSessionValidationAt = _lastUserActivityAt;

    final preferences = await _preferencesLoader();
    if (generation != _generation) return;
    await Future.wait([
      preferences.setString(_tokenKey, normalizedToken),
      preferences.setString(_roleKey, normalizedRole),
      preferences.setString(_accountSourceKey, normalizedSource),
      preferences.setString(_userIdKey, normalizedUserId),
      preferences.setInt(_expiresAtKey, expiresAtEpochSeconds),
    ]);
    if (generation != _generation) return;

    _observeLifecycle();
    _scheduleInactivityTimeout();

    unawaited(recordActivity('login', details: {
      'role': normalizedRole,
      'account_source': normalizedSource,
    }));
  }

  Future<bool> validate() async {
    if (_validationInProgress || !hasActiveSession) return hasActiveSession;
    if (_isLocallyExpired) {
      await _invalidate(
        'Your session expired. Please log in again.',
        eventName: 'session_expired',
      );
      return false;
    }

    _validationInProgress = true;
    _lastSessionValidationAt = _now();
    final generation = _generation;
    try {
      final response = await _client
          .post(
            _endpoint('validate_session.php'),
            headers: authorizationHeaders,
          )
          .timeout(const Duration(seconds: 10));
      if (generation != _generation) return false;
      final invalid = await handleResponse(response);
      if (invalid) return false;
      if (response.statusCode < 200 || response.statusCode >= 300) return true;

      final data = _decodeObject(response.body);
      if (_string(data?['status']).toLowerCase() != 'success') return true;
      _updateExpiryFromPayload(data!);
      return true;
    } on TimeoutException {
      debugPrint('App session validation timed out.');
      return true;
    } catch (error) {
      debugPrint('App session validation failed: $error');
      return true;
    } finally {
      _validationInProgress = false;
    }
  }

  Future<void> recordActivity(
    String eventType, {
    Map<String, Object?> details = const {},
  }) async {
    if (!hasActiveSession) return;
    final generation = _generation;
    try {
      final response = await _client.post(
        _endpoint('record_app_activity.php'),
        headers: authorizationHeaders,
        body: {
          'event_type': eventType,
          if (details.isNotEmpty) 'details': jsonEncode(details),
        },
      ).timeout(const Duration(seconds: 8));
      if (generation != _generation) return;
      await handleResponse(response);
    } on TimeoutException {
      debugPrint('App activity recording timed out for $eventType.');
    } catch (error) {
      debugPrint('App activity recording failed for $eventType: $error');
    }
  }

  Future<bool> handleResponse(http.Response response) async {
    final data = _decodeObject(response.body);
    final code = _string(data?['code']).toLowerCase();
    final invalid = response.statusCode == 401 ||
        response.statusCode == 403 ||
        code == 'session_invalid' ||
        code == 'session_replaced';
    if (!invalid) return false;

    final replaced = code == 'session_replaced';
    final fallback = replaced
        ? 'This account was opened on another device. Please log in again.'
        : 'Your session is no longer active. Please log in again.';
    await _invalidate(
      _string(data?['message']).isEmpty ? fallback : _string(data?['message']),
      eventName: replaced ? 'session_replaced' : 'session_invalid',
    );
    return true;
  }

  Future<void> endSession({String reason = 'logout'}) async {
    await _restoreStoredSessionIfNeeded();
    final token = _token;
    if (token == null) {
      await _clearLocalSession();
      return;
    }

    final headers = {'Authorization': 'Bearer $token'};
    final generation = ++_generation;
    _stopMonitoring();
    await _clearLocalSession(incrementGeneration: false);
    try {
      await _client.post(
        _endpoint('logout_session.php'),
        headers: headers,
        body: {'reason': reason},
      ).timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('Server logout could not be confirmed: $error');
    } finally {
      if (_generation == generation) _invalidating = false;
    }
  }

  Future<void> close() async {
    _stopMonitoring();
    _invalidSessionCallback = null;
    if (_ownsClient) _client.close();
  }

  bool get _isLocallyExpired {
    final expiry = _expiresAtEpochSeconds;
    if (expiry == null) return true;
    return expiry <= _now().millisecondsSinceEpoch ~/ 1000;
  }

  void _observeLifecycle() {
    if (_observingLifecycle) return;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _observingLifecycle = true;
  }

  void _stopMonitoring() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
      _observingLifecycle = false;
    }
  }

  Future<void> _onLifecycleStateChanged(AppLifecycleState state) async {
    if (!hasActiveSession) return;
    if (state == AppLifecycleState.resumed) {
      final wasInBackground = _isInBackground;
      _isInBackground = false;
      if (wasInBackground) {
        final lastActivity = _lastUserActivityAt;
        if (lastActivity != null &&
            _now().difference(lastActivity) >= _inactivityTimeout) {
          await _expireForInactivity();
          return;
        }
        _lastUserActivityAt = _now();
        _scheduleInactivityTimeout();
        await recordActivity('app_resume');
      }
      await validate();
      return;
    }

    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden) &&
        !_isInBackground) {
      _isInBackground = true;
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
      await recordActivity('app_background', details: {
        'state': state.name,
      });
    }
  }

  void _scheduleInactivityTimeout() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (!hasActiveSession || _invalidating || _isInBackground) return;
    _inactivityTimer = Timer(
      _inactivityTimeout,
      () => unawaited(_expireForInactivity()),
    );
  }

  Future<void> _expireForInactivity() {
    return _invalidate(
      'You were logged out after 5 minutes of inactivity. Please log in again.',
      eventName: 'inactivity_timeout',
      notifyServer: true,
    );
  }

  Future<void> _invalidate(
    String message, {
    required String eventName,
    bool notifyServer = false,
  }) async {
    if (_invalidating || !hasActiveSession) return;
    _invalidating = true;
    final callback = _invalidSessionCallback;
    final details = <String, Object?>{'reason': eventName};
    final token = _token;

    if (eventName == 'session_replaced') {
      await recordActivity('session_replaced', details: details);
    }

    if (notifyServer && token != null) {
      unawaited(_notifyServerLogout(token, reason: eventName));
    }

    ++_generation;
    _stopMonitoring();
    await _clearLocalSession(incrementGeneration: false);
    if (callback != null) {
      await callback(message);
    }
  }

  Future<void> _notifyServerLogout(
    String token, {
    required String reason,
  }) async {
    try {
      await _client.post(
        _endpoint('logout_session.php'),
        headers: {'Authorization': 'Bearer $token'},
        body: {'reason': reason},
      ).timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('Server inactivity logout could not be confirmed: $error');
    }
  }

  Future<void> _restoreStoredSessionIfNeeded() async {
    if (_token != null) return;
    final preferences = await _preferencesLoader();
    final token = preferences.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) return;
    _token = token;
    _role = preferences.getString(_roleKey)?.trim().toLowerCase();
    _accountSource =
        preferences.getString(_accountSourceKey)?.trim().toLowerCase();
    _userId = preferences.getString(_userIdKey)?.trim();
    _expiresAtEpochSeconds = preferences.getInt(_expiresAtKey);
  }

  Future<void> _clearLocalSession({bool incrementGeneration = true}) async {
    if (incrementGeneration) ++_generation;
    _stopMonitoring();
    _token = null;
    _role = null;
    _accountSource = null;
    _userId = null;
    _expiresAtEpochSeconds = null;
    _lastUserActivityAt = null;
    _lastSessionValidationAt = null;
    _isInBackground = false;
    final preferences = await _preferencesLoader();
    await Future.wait([
      preferences.remove(_tokenKey),
      preferences.remove(_roleKey),
      preferences.remove(_accountSourceKey),
      preferences.remove(_userIdKey),
      preferences.remove(_expiresAtKey),
    ]);
  }

  void _updateExpiryFromPayload(Map<String, dynamic> data) {
    final absolute = _parseExpiry(data['session_expires_at']);
    final relative = _nonNegativeInt(
      data['session_expires_in'] ?? data['expires_in'],
    );
    final updated = absolute ??
        (relative == null
            ? null
            : _now().millisecondsSinceEpoch ~/ 1000 + relative);
    if (updated != null) _expiresAtEpochSeconds = updated;
  }

  Uri _endpoint(String path) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final endpoint = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$base/$endpoint');
    if (!ApiConfig.usesProtectedOrLocalTransport(uri)) {
      throw const AppSessionException(
        'App sessions require HTTPS outside the local development network.',
      );
    }
    return uri;
  }

  static Map<String, dynamic>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static int? _nonNegativeInt(Object? value) {
    final parsed = int.tryParse(_string(value));
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static int? _parseExpiry(Object? value) {
    if (value is num) {
      final numeric = value.toInt();
      return numeric > 20000000000 ? numeric ~/ 1000 : numeric;
    }
    final text = _string(value);
    if (text.isEmpty) return null;
    final numeric = int.tryParse(text);
    if (numeric != null) {
      return numeric > 20000000000 ? numeric ~/ 1000 : numeric;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.toUtc().millisecondsSinceEpoch ~/ 1000;
  }
}

class _AppSessionLifecycleObserver with WidgetsBindingObserver {
  _AppSessionLifecycleObserver(this.service);

  final AppSessionService service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(service._onLifecycleStateChanged(state));
  }
}

class AppSessionActivityListener extends StatefulWidget {
  const AppSessionActivityListener({
    required this.child,
    this.service,
    super.key,
  });

  final Widget child;
  final AppSessionService? service;

  @override
  State<AppSessionActivityListener> createState() =>
      _AppSessionActivityListenerState();
}

class _AppSessionActivityListenerState
    extends State<AppSessionActivityListener> {
  AppSessionService get _service =>
      widget.service ?? AppSessionService.instance;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    _service.registerUserActivity();
    return false;
  }

  void _handlePointerEvent(PointerEvent event) {
    _service.registerUserActivity();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerEvent,
      onPointerMove: _handlePointerEvent,
      onPointerUp: _handlePointerEvent,
      onPointerHover: _handlePointerEvent,
      onPointerSignal: _handlePointerEvent,
      child: widget.child,
    );
  }
}
