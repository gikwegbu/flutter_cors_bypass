import 'package:shelf/shelf.dart';

/// Builds the CORS headers to attach to every proxy response.
///
/// If the request specifies an `Origin` header, it is reflected in
/// `Access-Control-Allow-Origin`. If no `Origin` is present, that header is omitted.
///
/// Deduplicates requested headers case-insensitively.
Map<String, String> corsHeaders(
  Request request, {
  Iterable<String>? exposeHeaders,
}) {
  final headers = <String, String>{
    'access-control-allow-methods':
        'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS',
    'access-control-max-age': '600',
    'vary': 'Origin',
  };

  final origin = request.headers['origin'];
  if (origin != null && origin.isNotEmpty) {
    headers['access-control-allow-origin'] = origin;
  }

  // Base allowed headers
  final allowHeadersMap = <String, String>{
    'origin': 'Origin',
    'content-type': 'Content-Type',
    'accept': 'Accept',
    'authorization': 'Authorization',
  };

  final requestHeaders = request.headers['access-control-request-headers'];
  if (requestHeaders != null && requestHeaders.isNotEmpty) {
    for (final item in requestHeaders.split(',')) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) {
        final lower = trimmed.toLowerCase();
        if (!allowHeadersMap.containsKey(lower)) {
          allowHeadersMap[lower] = trimmed;
        }
      }
    }
  }

  headers['access-control-allow-headers'] = allowHeadersMap.values.join(', ');

  if (exposeHeaders != null && exposeHeaders.isNotEmpty) {
    headers['access-control-expose-headers'] = exposeHeaders.join(', ');
  }

  return headers;
}

/// Returns a 204 preflight response with CORS headers and an empty body.
Response preflightResponse(Request request) {
  return Response(204, headers: corsHeaders(request));
}
