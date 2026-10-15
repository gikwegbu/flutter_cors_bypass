// Mirrors the URL building logic in example/api_url.dart.
// Keep in sync with example/api_url.dart.

String _cleanBase(String proxyBase) => proxyBase.endsWith('/')
    ? proxyBase.substring(0, proxyBase.length - 1)
    : proxyBase;

/// Wraps an API **base URL** into a path-style proxy URL.
///
/// If [proxyBase] is empty, returns a relative path starting with `/`.
///
/// Example:
/// ```dart
/// proxiedUrl('https://api.example.com', proxyBase: 'http://localhost:8080');
/// // -> 'http://localhost:8080/https/api.example.com'
/// ```
String proxiedUrl(String baseUrl, {required String proxyBase}) {
  final base = _cleanBase(proxyBase);
  final uri = Uri.parse(baseUrl);
  final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$base/${uri.scheme}/$authority${uri.path}$query';
}

/// Wraps a complete target URL into a query-style proxy [Uri].
///
/// If [proxyBase] is empty, returns a relative URI `/proxy?url=<encoded>`.
///
/// Example:
/// ```dart
/// proxyQueryUri('https://api.example.com/users', proxyBase: 'http://localhost:8080');
/// // -> Uri.parse('http://localhost:8080/proxy?url=https%3A%2F%2Fapi.example.com%2Fusers')
/// ```
Uri proxyQueryUri(String targetUrl, {required String proxyBase}) {
  final baseStr = _cleanBase(proxyBase);
  final query = {'url': targetUrl};
  if (baseStr.isEmpty) {
    return Uri(path: '/proxy', queryParameters: query);
  }
  final base = Uri.parse(baseStr);
  return base.replace(path: '${base.path}/proxy', queryParameters: query);
}
