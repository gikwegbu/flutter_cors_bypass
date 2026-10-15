import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'allowlist.dart';
import 'config.dart';
import 'proxy_handler.dart';

/// Builds the shelf [Handler] according to the given [config].
Handler buildHandler({
  required ProxyConfig config,
  http.Client? client,
  void Function(String)? logger,
}) {
  final httpClient = client ?? http.Client();
  final allowlist = Allowlist(config.allowHosts);
  final proxyHandler = ProxyHandler(
    client: httpClient,
    allowlist: allowlist,
    timeout: config.timeout,
    proxyPort: config.port,
    proxyHost: config.host,
    logger: logger ?? print,
  );

  Handler? staticHandler;
  if (config.webRoot != null) {
    staticHandler = createStaticHandler(
      config.webRoot!,
      defaultDocument: 'index.html',
    );
  }

  return (Request request) async {
    var path = request.url.path;
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    final isQueryProxy = path == 'proxy' || path.startsWith('proxy/');
    final isPathProxy =
        path == 'http' ||
        path.startsWith('http/') ||
        path == 'https' ||
        path.startsWith('https/');

    if (isQueryProxy || isPathProxy) {
      return proxyHandler.handle(request);
    }

    // Static file serving or proxy-only 404
    if (config.webRoot == null) {
      return Response.notFound(
        'Not found. No WEB_ROOT is configured, so only proxy routes are served.\n\n'
        'Proxy routes:\n'
        '  Query style: http://${config.host}:${config.port}/proxy?url=<url-encoded full URL>\n'
        '  Path style:  http://${config.host}:${config.port}/https/<host>/<path>?<query>\n',
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    }

    final response = await staticHandler!(request);

    // SPA fallback: GET request returning 404 for a path without a file extension
    if (response.statusCode == 404 && request.method == 'GET') {
      final ext = p.extension(path);
      if (ext.isEmpty) {
        final indexFile = File(p.join(config.webRoot!, 'index.html'));
        if (indexFile.existsSync()) {
          return Response.ok(
            indexFile.openRead(),
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
      }
    }

    return response;
  };
}
