import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_session_service.dart';

typedef ScreenViewRecorder = FutureOr<void> Function(
  String screen,
  String navigation,
);

class AuditTrailService {
  AuditTrailService({AppSessionService? sessionService})
      : _sessionService = sessionService ?? AppSessionService.instance;

  static final AuditTrailService instance = AuditTrailService();

  final AppSessionService _sessionService;
  Future<void> _pendingWrite = Future<void>.value();

  Future<void> recordScreenView(String screen, String navigation) {
    final safeScreen = canonicalAuditName(screen);
    final safeNavigation = canonicalAuditName(navigation);
    if (safeScreen == null || safeNavigation == null) {
      return Future<void>.value();
    }

    final completion = Completer<void>();
    _pendingWrite =
        _pendingWrite.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Previous audit event failed: $error');
    }).then((_) async {
      try {
        await _sessionService.recordActivity(
          'screen_view',
          details: {
            'screen': safeScreen,
            'navigation': safeNavigation,
          },
        );
        completion.complete();
      } catch (error, stackTrace) {
        debugPrint('Screen audit failed: $error');
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }
}

class AuditNavigatorObserver extends NavigatorObserver {
  AuditNavigatorObserver({ScreenViewRecorder? recorder})
      : _recorder = recorder ?? AuditTrailService.instance.recordScreenView;

  final ScreenViewRecorder _recorder;
  final Map<Route<dynamic>, int> _pendingRoutes = {};
  int _revision = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _scheduleVisibleRoute(route, 'push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _scheduleVisibleRoute(previousRoute, 'pop');
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _scheduleVisibleRoute(newRoute, 'replace');
    }
  }

  void _scheduleVisibleRoute(Route<dynamic> route, String navigation) {
    if (route is PopupRoute<dynamic>) return;

    final revision = ++_revision;
    _pendingRoutes[route] = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingRoutes[route] != revision) return;
      _pendingRoutes.remove(route);
      if (!route.isActive || !route.isCurrent) return;

      final screen = auditScreenNameForRoute(route);
      if (screen == null) return;

      final result = _recorder(screen, navigation);
      if (result is Future<void>) {
        unawaited(
          result.catchError((Object error, StackTrace stackTrace) {
            debugPrint('Navigation audit failed: $error');
          }),
        );
      }
    });
  }
}

String? auditScreenNameForRoute(Route<dynamic> route) {
  final routeName = canonicalAuditName(route.settings.name);
  if (routeName != null && routeName != 'root') return routeName;
  if (route is! ModalRoute<dynamic>) return routeName;

  final context = route.subtreeContext;
  if (context == null || !context.mounted) return routeName;
  String? candidate;
  void inspect(Element element) {
    if (candidate != null) return;
    final typeName = element.widget.runtimeType.toString();
    if (_looksLikeApplicationScreen(typeName)) {
      candidate = canonicalAuditName(typeName);
      return;
    }
    element.visitChildren(inspect);
  }

  inspect(context as Element);
  return candidate ?? routeName;
}

String? canonicalAuditName(Object? value) {
  var input = value?.toString().trim() ?? '';
  if (input.isEmpty) return null;
  input = input.split('?').first;
  input = input.replaceAll(RegExp(r'^/+|/+$'), '');
  if (input.isEmpty) return 'root';
  input = input
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (match) => '${match[1]}_${match[2]}',
      )
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '')
      .toLowerCase();
  if (input.isEmpty || input.length > 64) return null;
  return input;
}

bool _looksLikeApplicationScreen(String typeName) {
  if (typeName.startsWith('_') || typeName.startsWith('Audit')) return false;
  return RegExp(
    r'(?:Page|Screen|Dashboard|Home|Profile|History|TopUps|Transfer|Reports?)$',
  ).hasMatch(typeName);
}
