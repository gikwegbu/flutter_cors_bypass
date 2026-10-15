// Mirrors the pure Dart logic in lib/src/proxy_url.dart.
// Keep in sync with lib/src/proxy_url.dart.

import 'package:flutter/foundation.dart';

/// Base URL of the local CORS proxy, e.g. `http://localhost:8080`.
///
/// Set with `--dart-define=PROXY_BASE=http://localhost:8080` when using
/// `flutter run -d chrome`. Leave it empty when the app is served by the proxy
/// itself (`flutter build web --profile`, then `--web-root`), so URLs are
/// same-origin.
const String _proxyBase = String.fromEnvironment('PROXY_BASE');

/// Whether non-release web builds route API calls through the proxy.
/// Turn it off with `--dart-define=USE_PROXY=false`.
const bool _useProxy = bool.fromEnvironment('USE_PROXY', defaultValue: true);

/// Whether URLs should be rewritten to go through the proxy.
///
/// Never in release builds: `kReleaseMode` is a compile-time constant, so in
/// `flutter build web` (release) this is always false and the proxy code is
/// removed from the output. Never on mobile or desktop, which have no CORS.
bool get _shouldProxy => kIsWeb && !kReleaseMode && _useProxy;

String get _base => _proxyBase.endsWith('/')
    ? _proxyBase.substring(0, _proxyBase.length - 1)
    : _proxyBase;

/// Wraps an API **base URL** so that paths and queries can be appended to it.
///
/// ```dart
/// final apiBase = proxied('https://api.example.com');
/// // debug web: http://localhost:8080/https/api.example.com
/// // release / mobile / desktop: https://api.example.com
/// http.get(Uri.parse('$apiBase/users?a=1&b=2'));
/// Dio(BaseOptions(baseUrl: proxied('https://api.example.com')));
/// ```
String proxied(String baseUrl) {
  if (!_shouldProxy) return baseUrl;

  final uri = Uri.parse(baseUrl);
  final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$_base/${uri.scheme}/$authority${uri.path}$query';
}

/// Wraps a **complete** URL and returns a `Uri` ready to pass to `http`.
///
/// ```dart
/// final res = await http.get(apiUri('https://api.example.com/users?page=1'));
///
/// final created = await http.post(
///   apiUri('https://api.example.com/users'),
///   headers: {
///     'Content-Type': 'application/json',
///     'Authorization': 'Bearer $token',
///   },
///   body: jsonEncode({'name': 'Ada'}),
/// );
/// ```
Uri apiUri(String targetUrl) {
  if (!_shouldProxy) return Uri.parse(targetUrl);

  final query = {'url': targetUrl};
  if (_base.isEmpty) {
    return Uri(path: '/proxy', queryParameters: query);
  }
  final base = Uri.parse(_base);
  return base.replace(path: '${base.path}/proxy', queryParameters: query);
}
