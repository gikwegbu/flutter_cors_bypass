import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'allowlist.dart';
import 'cors.dart';
import 'target_resolver.dart';

/// Handles proxying requests to upstream targets.
class ProxyHandler {
  /// The shared HTTP client.
  final http.Client client;

  /// The host allowlist.
  final Allowlist allowlist;

  /// Upstream request timeout.
  final Duration timeout;

  /// Port of the running proxy server (for self-loop detection).
  final int proxyPort;

  /// Host of the running proxy server.
  final String proxyHost;

  /// Logging sink (defaults to [print]).
  final void Function(String) logger;

  /// Creates a [ProxyHandler].
  ProxyHandler({
    required this.client,
    required this.allowlist,
    this.timeout = const Duration(seconds: 30),
    this.proxyPort = 8080,
    this.proxyHost = 'localhost',
    this.logger = print,
  });

  /// Handles an incoming proxy request.
  Future<Response> handle(Request request) async {
    final method = request.method;

    // Handle CORS preflight without contacting upstream
    if (method == 'OPTIONS') {
      final targetRes = resolveTarget(
        request,
        proxyPort: proxyPort,
        proxyHost: proxyHost,
      );
      final displayTarget = targetRes.uri?.toString() ?? request.url.toString();
      logger('OPTIONS $displayTarget -> 204 (0 ms)');
      return preflightResponse(request);
    }

    // Resolve target URL
    final targetResult = resolveTarget(
      request,
      proxyPort: proxyPort,
      proxyHost: proxyHost,
    );

    if (targetResult.isError) {
      logger('$method ${request.url} -> 400 (0 ms)');
      return Response(
        400,
        body: targetResult.error!,
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          ...corsHeaders(request),
        },
      );
    }

    final targetUri = targetResult.uri!;

    // Check host allowlist
    if (!allowlist.isAllowed(targetUri)) {
      logger('$method $targetUri -> 403 (0 ms)');
      return Response(
        403,
        body:
            'Host "${targetUri.host}" is not allowed. Use the --allow flag to allow this host.',
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          ...corsHeaders(request),
        },
      );
    }

    // Read incoming request body
    final bodyBytes = await request.read().fold<List<int>>(
      <int>[],
      (previous, element) => previous..addAll(element),
    );

    // Prepare outgoing request
    final outgoing = http.Request(method, targetUri);
    outgoing.followRedirects = true;

    // Strip forbidden request headers
    for (final entry in request.headers.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'host' ||
          lower == 'origin' ||
          lower == 'referer' ||
          lower == 'content-length' ||
          lower == 'connection' ||
          lower == 'accept-encoding' ||
          lower.startsWith('sec-fetch-')) {
        continue;
      }
      outgoing.headers[entry.key] = entry.value;
    }

    if (bodyBytes.isNotEmpty) {
      outgoing.bodyBytes = bodyBytes;
    }

    final stopwatch = Stopwatch()..start();
    http.StreamedResponse streamedResponse;

    try {
      streamedResponse = await client.send(outgoing).timeout(timeout);
      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;
      logger(
        '$method $targetUri -> ${streamedResponse.statusCode} ($durationMs ms)',
      );
    } on TimeoutException {
      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;
      logger('$method $targetUri -> 504 ($durationMs ms)');
      return Response(
        504,
        body: 'Upstream timed out after ${timeout.inSeconds}s',
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          ...corsHeaders(request),
        },
      );
    } catch (error) {
      stopwatch.stop();
      final durationMs = stopwatch.elapsedMilliseconds;
      logger('$method $targetUri -> 502 ($durationMs ms)');
      final reason = _extractShortReason(error);
      return Response(
        502,
        body: 'Upstream request failed: $reason',
        headers: {
          'content-type': 'text/plain; charset=utf-8',
          ...corsHeaders(request),
        },
      );
    }

    // Prepare response headers
    final responseHeaders = <String, String>{};
    final exposeHeadersList = <String>[];

    for (final entry in streamedResponse.headers.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'content-encoding' ||
          lower == 'content-length' ||
          lower == 'transfer-encoding' ||
          lower == 'connection' ||
          lower.startsWith('access-control-')) {
        continue;
      }
      responseHeaders[entry.key] = entry.value;
      exposeHeadersList.add(entry.key);
    }

    // Attach CORS headers
    final cors = corsHeaders(request, exposeHeaders: exposeHeadersList);
    responseHeaders.addAll(cors);

    return Response(
      streamedResponse.statusCode,
      body: streamedResponse.stream,
      headers: responseHeaders,
    );
  }

  String _extractShortReason(Object error) {
    if (error is SocketException) {
      if (error.message.isNotEmpty) return error.message;
      if (error.osError != null && error.osError!.message.isNotEmpty) {
        return error.osError!.message;
      }
    }
    if (error is http.ClientException) {
      if (error.message.isNotEmpty) return error.message;
    }
    final s = error.toString();
    return s.length > 200 ? s.substring(0, 200) : s;
  }
}
