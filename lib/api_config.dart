class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.254.107/edupay',
  );

  static bool usesProtectedOrLocalTransport(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return true;
    if (scheme != 'http') return false;

    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }

    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static String url(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final trimmed = path.startsWith('/') ? path.substring(1) : path;
    return '$base/$trimmed';
  }
}
