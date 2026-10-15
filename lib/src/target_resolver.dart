import 'package:shelf/shelf.dart';

/// The result of resolving a target URI from a proxy request.
class TargetResult {
  /// The resolved target URI, or `null` if resolution failed or the route is not a proxy route.
  final Uri? uri;

  /// The error message if resolution failed, or `null` if successful.
  final String? error;

  /// Whether the request matched a proxy route pattern (/proxy or /http/ or /https/).
  final bool isProxyRoute;

  /// Creates a [TargetResult].
  const TargetResult({this.uri, this.error, this.isProxyRoute = true});

  /// Whether resolution succeeded.
  bool get isSuccess => uri != null && error == null;

  /// Whether resolution produced an error.
  bool get isError => error != null;

  /// Returns the target URI and error as a Dart record.
  (Uri? uri, String? error) toRecord() => (uri, error);
}

/// Resolves a target [Uri] from a shelf [Request].
TargetResult resolveTarget(
  Request request, {
  int proxyPort = 8080,
  String proxyHost = 'localhost',
}) {
  return resolveTargetUri(
    request.url,
    proxyPort: proxyPort,
    proxyHost: proxyHost,
    requestHost: request.requestedUri.host,
    requestPort: request.requestedUri.hasPort
        ? request.requestedUri.port
        : null,
  );
}

/// Resolves a target [Uri] from a request [url] [Uri].
TargetResult resolveTargetUri(
  Uri url, {
  int proxyPort = 8080,
  String proxyHost = 'localhost',
  String? requestHost,
  int? requestPort,
}) {
  var path = url.path;
  if (path.startsWith('/')) {
    path = path.substring(1);
  }

  // 1. Query style: /proxy?url=<encoded>
  if (path == 'proxy' || path.startsWith('proxy/')) {
    final urlParam = url.queryParameters['url'];
    if (urlParam == null || urlParam.trim().isEmpty) {
      return const TargetResult(
        error: 'Missing or empty "url" query parameter.',
      );
    }

    final parsed = Uri.tryParse(urlParam.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty) {
      return TargetResult(
        error:
            'Invalid target URL: "$urlParam". Must be an absolute http or https URL with a host.',
      );
    }

    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return TargetResult(
        error:
            'Unsupported scheme "$scheme". Only http and https are supported.',
      );
    }

    if (_isSelfLoop(
      parsed,
      proxyPort,
      requestHost,
      proxyHost,
      requestPort: requestPort,
    )) {
      return const TargetResult(
        error: 'Target URL points back to the proxy itself.',
      );
    }

    return TargetResult(uri: parsed);
  }

  // 2. Path style: /<scheme>/<host[:port]>/<path>?<query>
  final firstSlash = path.indexOf('/');
  if (firstSlash == -1) {
    if (path == 'http' || path == 'https') {
      return const TargetResult(
        error: 'Missing target host in path style URL.',
      );
    }
    return const TargetResult(isProxyRoute: false);
  }

  final scheme = path.substring(0, firstSlash).toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return const TargetResult(isProxyRoute: false);
  }

  final rest = path.substring(firstSlash + 1);
  if (rest.isEmpty) {
    return const TargetResult(error: 'Missing target host in path style URL.');
  }

  final secondSlash = rest.indexOf('/');
  String authority;
  String targetPath;
  if (secondSlash == -1) {
    authority = rest;
    targetPath = '/';
  } else {
    authority = rest.substring(0, secondSlash);
    targetPath = rest.substring(secondSlash);
    if (targetPath.isEmpty) {
      targetPath = '/';
    }
  }

  if (authority.contains('[') ||
      authority.contains(']') ||
      authority.contains('::') ||
      authority.startsWith(':')) {
    return const TargetResult(
      error:
          'IPv6 literal hosts are not supported in path style. Use the query style instead: /proxy?url=<url>',
    );
  }

  String host;
  int? port;
  final colonIdx = authority.lastIndexOf(':');
  if (colonIdx != -1) {
    host = authority.substring(0, colonIdx);
    final portStr = authority.substring(colonIdx + 1);
    final p = int.tryParse(portStr);
    if (p == null || p < 1 || p > 65535) {
      return TargetResult(error: 'Invalid port "$portStr" in target host.');
    }
    port = p;
  } else {
    host = authority;
    port = null;
  }

  if (host.isEmpty) {
    return const TargetResult(error: 'Missing target host in path style URL.');
  }

  final sb = StringBuffer()
    ..write(scheme)
    ..write('://')
    ..write(host);
  if (port != null) {
    sb.write(':$port');
  }
  sb.write(targetPath);
  if (url.hasQuery && url.query.isNotEmpty) {
    sb.write('?');
    sb.write(url.query);
  }

  final fullUrlStr = sb.toString();
  final targetUri = Uri.tryParse(fullUrlStr);
  if (targetUri == null) {
    return TargetResult(
      error: 'Invalid target URL constructed: "$fullUrlStr".',
    );
  }

  if (_isSelfLoop(
    targetUri,
    proxyPort,
    requestHost,
    proxyHost,
    requestPort: requestPort,
  )) {
    return const TargetResult(
      error: 'Target URL points back to the proxy itself.',
    );
  }

  return TargetResult(uri: targetUri);
}

bool _isSelfLoop(
  Uri target,
  int proxyPort,
  String? requestHost,
  String configuredHost, {
  int? requestPort,
}) {
  final targetPort = target.hasPort
      ? target.port
      : (target.scheme == 'https' ? 443 : 80);

  final isPortMatch =
      (proxyPort > 0 && targetPort == proxyPort) ||
      (requestPort != null && targetPort == requestPort);

  if (!isPortMatch) {
    return false;
  }

  final h = target.host.toLowerCase();
  final reqH = requestHost?.toLowerCase();
  final confH = configuredHost.toLowerCase();

  if (h == 'localhost' ||
      h == '0.0.0.0' ||
      h == '::1' ||
      h == '[::1]' ||
      h.startsWith('127.')) {
    return true;
  }

  if (reqH != null && h == reqH) {
    return true;
  }

  if (h == confH) {
    return true;
  }

  return false;
}
