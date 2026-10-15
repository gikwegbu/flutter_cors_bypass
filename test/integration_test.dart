import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer upstreamServer;
  late int upstreamPort;
  late String upstreamBase;

  late HttpServer proxyServer;
  late int proxyPort;
  late String proxyBase;

  late Directory tempWebRoot;
  late http.Client testClient;

  setUpAll(() async {
    testClient = http.Client();

    // 1. Setup Upstream Server
    final router = Router()
      ..all('/echo', (shelf.Request req) async {
        final bodyBytes = await req.read().fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        final data = {
          'method': req.method,
          'uri': req.requestedUri.toString(),
          'path': req.requestedUri.path,
          'query': req.requestedUri.query,
          'headers': req.headers,
          'body_base64': base64Encode(bodyBytes),
        };
        return shelf.Response.ok(
          jsonEncode(data),
          headers: {'content-type': 'application/json'},
        );
      })
      ..get('/binary', (shelf.Request req) {
        final bytes = Uint8List(64 * 1024);
        var seed = 42;
        for (var i = 0; i < bytes.length; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          bytes[i] = (seed >> 16) & 0xff;
        }
        return shelf.Response.ok(
          bytes,
          headers: {'content-type': 'application/octet-stream'},
        );
      })
      ..get('/gzip', (shelf.Request req) {
        final rawJson = jsonEncode({'message': 'compressed data', 'ok': true});
        final compressed = gzip.encode(utf8.encode(rawJson));
        return shelf.Response.ok(
          compressed,
          headers: {
            'content-type': 'application/json',
            'content-encoding': 'gzip',
          },
        );
      })
      ..get('/slow', (shelf.Request req) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return shelf.Response.ok('slow response');
      })
      ..get('/redirect', (shelf.Request req) {
        return shelf.Response.found(
          'http://localhost:$upstreamPort/echo?redirected=1',
        );
      })
      ..get('/status/<code|[0-9]+>', (shelf.Request req, String code) {
        final st = int.parse(code);
        return shelf.Response(st, body: 'status $st body');
      });

    upstreamServer = await shelf_io.serve(router.call, 'localhost', 0);
    upstreamPort = upstreamServer.port;
    upstreamBase = 'http://localhost:$upstreamPort';

    // 2. Setup Temp Web Root
    tempWebRoot = Directory.systemTemp.createTempSync('proxy_web_root_');
    File(
      p.join(tempWebRoot.path, 'index.html'),
    ).writeAsStringSync('<html><body>Index File</body></html>');
    File(
      p.join(tempWebRoot.path, 'main.dart.js'),
    ).writeAsStringSync('console.log("main.dart.js");');

    // 3. Setup Proxy Server with 1s timeout
    final proxyConfig = ProxyConfig(
      port: 0,
      host: 'localhost',
      webRoot: tempWebRoot.path,
      timeoutSeconds: 1,
    );

    final proxyHandler = buildHandler(config: proxyConfig, client: testClient);

    proxyServer = await shelf_io.serve(proxyHandler, 'localhost', 0);
    proxyPort = proxyServer.port;
    proxyBase = 'http://localhost:$proxyPort';
  });

  tearDownAll(() async {
    await proxyServer.close(force: true);
    await upstreamServer.close(force: true);
    testClient.close();
    tempWebRoot.deleteSync(recursive: true);
  });

  group('Integration tests (real servers, no internet)', () {
    test(
      '1. GET with ?a=1&b=2&tag=x&tag=y preserves all four parameters in order',
      () async {
        // Test both query style and path style
        final queryUrl =
            '$proxyBase/proxy?url=${Uri.encodeComponent('$upstreamBase/echo?a=1&b=2&tag=x&tag=y')}';
        final pathUrl =
            '$proxyBase/http/localhost:$upstreamPort/echo?a=1&b=2&tag=x&tag=y';

        for (final url in [queryUrl, pathUrl]) {
          final res = await testClient.get(Uri.parse(url));
          expect(res.statusCode, equals(200));
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          expect(body['query'], equals('a=1&b=2&tag=x&tag=y'));
        }
      },
    );

    test(
      '2. POST JSON with Authorization & X-Api-Key headers & host header check',
      () async {
        final queryUrl =
            '$proxyBase/proxy?url=${Uri.encodeComponent('$upstreamBase/echo')}';
        final pathUrl = '$proxyBase/http/localhost:$upstreamPort/echo';

        for (final url in [queryUrl, pathUrl]) {
          final reqBody = jsonEncode({'title': 'Integration Test'});
          final res = await testClient.post(
            Uri.parse(url),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer test-token',
              'x-api-key': 'k',
              'origin': 'http://localhost:5050',
              'referer': 'http://localhost:5050/page',
              'sec-fetch-mode': 'cors',
              'accept-encoding': 'br',
            },
            body: reqBody,
          );

          expect(res.statusCode, equals(200));
          final echo = jsonDecode(res.body) as Map<String, dynamic>;
          final headers = echo['headers'] as Map<String, dynamic>;

          // Upstream host is the upstream's host:port, not the proxy's
          expect(headers['host'], equals('localhost:$upstreamPort'));

          // Authorization and X-Api-Key kept
          expect(headers['authorization'], equals('Bearer test-token'));
          expect(headers['x-api-key'], equals('k'));

          // Forbidden headers stripped
          expect(headers.containsKey('origin'), isFalse);
          expect(headers.containsKey('referer'), isFalse);
          expect(headers.containsKey('sec-fetch-mode'), isFalse);
          expect(headers['accept-encoding'], isNot(equals('br')));

          // Body matches
          final receivedBody = utf8.decode(
            base64Decode(echo['body_base64'] as String),
          );
          expect(receivedBody, equals(reqBody));
        }
      },
    );

    test(
      '3. OPTIONS returns 204 with Origin and deduplicated Access-Control-Allow-Headers',
      () async {
        final queryUrl =
            '$proxyBase/proxy?url=${Uri.encodeComponent('$upstreamBase/echo')}';
        final pathUrl = '$proxyBase/http/localhost:$upstreamPort/echo';

        for (final url in [queryUrl, pathUrl]) {
          final req = http.Request('OPTIONS', Uri.parse(url));
          req.headers['origin'] = 'http://localhost:5050';
          req.headers['access-control-request-headers'] =
              'authorization, content-type, x-api-key';

          final streamed = await testClient.send(req);
          expect(streamed.statusCode, equals(204));
          expect(
            streamed.headers['access-control-allow-origin'],
            equals('http://localhost:5050'),
          );

          final allowedHeaders =
              streamed.headers['access-control-allow-headers']!;
          expect(allowedHeaders, contains('Authorization'));
          expect(allowedHeaders, contains('Content-Type'));
          expect(allowedHeaders, contains('x-api-key'));

          // Deduplication: Authorization appears only once
          final matches = RegExp(
            'authorization',
            caseSensitive: false,
          ).allMatches(allowedHeaders);
          expect(matches.length, equals(1));
        }
      },
    );

    test(
      '4. /binary through proxy is byte-for-byte identical to upstream bytes',
      () async {
        final directRes = await testClient.get(
          Uri.parse('$upstreamBase/binary'),
        );
        expect(directRes.statusCode, equals(200));
        final directBytes = directRes.bodyBytes;
        final directSha = sha256.convert(directBytes).toString();

        final proxiedRes = await testClient.get(
          Uri.parse('$proxyBase/http/localhost:$upstreamPort/binary'),
        );
        expect(proxiedRes.statusCode, equals(200));
        final proxiedBytes = proxiedRes.bodyBytes;
        final proxiedSha = sha256.convert(proxiedBytes).toString();

        expect(proxiedBytes.length, equals(directBytes.length));
        expect(proxiedSha, equals(directSha));
      },
    );

    test(
      '5. /gzip with Accept-Encoding: gzip, deflate, br, zstd returns readable decompressed JSON and no content-encoding',
      () async {
        final res = await testClient.get(
          Uri.parse('$proxyBase/http/localhost:$upstreamPort/gzip'),
          headers: {'accept-encoding': 'gzip, deflate, br, zstd'},
        );

        expect(res.statusCode, equals(200));
        expect(res.headers.containsKey('content-encoding'), isFalse);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        expect(json['message'], equals('compressed data'));
        expect(json['ok'], isTrue);
      },
    );

    test('6. /slow triggers 504 timeout within about 1.5s', () async {
      final sw = Stopwatch()..start();
      final res = await testClient.get(
        Uri.parse('$proxyBase/http/localhost:$upstreamPort/slow'),
      );
      sw.stop();

      expect(res.statusCode, equals(504));
      expect(res.body, contains('Upstream timed out'));
      expect(res.headers['access-control-allow-methods'], isNotNull);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('7. Target on closed port produces 502 with CORS headers', () async {
      final tempServer = await HttpServer.bind('localhost', 0);
      final closedPort = tempServer.port;
      await tempServer.close();

      final res = await testClient.get(
        Uri.parse('$proxyBase/http/localhost:$closedPort/test'),
        headers: {'origin': 'http://localhost:5050'},
      );

      expect(res.statusCode, equals(502));
      expect(
        res.headers['access-control-allow-origin'],
        equals('http://localhost:5050'),
      );
      expect(res.body, contains('Upstream request failed'));
    });

    test('8. /redirect is followed transparently by proxy', () async {
      final res = await testClient.get(
        Uri.parse('$proxyBase/http/localhost:$upstreamPort/redirect'),
      );

      expect(res.statusCode, equals(200));
      final echo = jsonDecode(res.body) as Map<String, dynamic>;
      expect(echo['query'], equals('redirected=1'));
    });

    test(
      '9. /status/404 and /status/500 passed through with CORS headers',
      () async {
        for (final code in [404, 500]) {
          final res = await testClient.get(
            Uri.parse('$proxyBase/http/localhost:$upstreamPort/status/$code'),
            headers: {'origin': 'http://localhost:5050'},
          );

          expect(res.statusCode, equals(code));
          expect(
            res.headers['access-control-allow-origin'],
            equals('http://localhost:5050'),
          );
          expect(res.body, equals('status $code body'));
        }
      },
    );

    test('10. 400 for missing target or self-loop', () async {
      final resMissing = await testClient.get(Uri.parse('$proxyBase/proxy'));
      expect(resMissing.statusCode, equals(400));

      final resSelfLoop = await testClient.get(
        Uri.parse('$proxyBase/http/localhost:$proxyPort/any'),
      );
      expect(resSelfLoop.statusCode, equals(400));
      expect(resSelfLoop.body, contains('points back to the proxy itself'));
    });

    test('11. Allowlist restricts upstream and returns 403', () async {
      final restrictedConfig = ProxyConfig(
        port: 0,
        host: 'localhost',
        allowHosts: ['example.invalid'],
      );
      final restrictedHandler = buildHandler(
        config: restrictedConfig,
        client: testClient,
      );
      final restrictedServer = await shelf_io.serve(
        restrictedHandler,
        'localhost',
        0,
      );
      try {
        final res = await testClient.get(
          Uri.parse(
            'http://localhost:${restrictedServer.port}/http/localhost:$upstreamPort/echo',
          ),
        );
        expect(res.statusCode, equals(403));
        expect(res.body, contains('not allowed'));
        expect(res.body, contains('--allow'));
      } finally {
        await restrictedServer.close(force: true);
      }
    });

    test(
      '12. proxiedUrl + /echo?a=1&b=2 delivers both parameters upstream',
      () async {
        final wrappedBase = proxiedUrl(upstreamBase, proxyBase: proxyBase);
        final fullUrl = '$wrappedBase/echo?a=1&b=2';

        final res = await testClient.get(Uri.parse(fullUrl));
        expect(res.statusCode, equals(200));
        final echo = jsonDecode(res.body) as Map<String, dynamic>;
        expect(echo['query'], equals('a=1&b=2'));
      },
    );

    test(
      '13. Static files: / -> index.html, /main.dart.js -> file, /deep/link -> SPA fallback, /missing.js -> 404',
      () async {
        final resIndex = await testClient.get(Uri.parse('$proxyBase/'));
        expect(resIndex.statusCode, equals(200));
        expect(resIndex.body, contains('Index File'));

        final resJs = await testClient.get(
          Uri.parse('$proxyBase/main.dart.js'),
        );
        expect(resJs.statusCode, equals(200));
        expect(resJs.body, contains('main.dart.js'));

        // SPA fallback on path without extension
        final resSpa = await testClient.get(Uri.parse('$proxyBase/deep/link'));
        expect(resSpa.statusCode, equals(200));
        expect(resSpa.body, contains('Index File'));

        // Missing file with extension remains 404
        final resMissing = await testClient.get(
          Uri.parse('$proxyBase/missing.js'),
        );
        expect(resMissing.statusCode, equals(404));
      },
    );

    test(
      '14. Proxy-only mode (no web root) returns 404 with No WEB_ROOT is configured',
      () async {
        final proxyOnlyConfig = ProxyConfig(
          port: 0,
          host: 'localhost',
          webRoot: null,
        );
        final proxyOnlyHandler = buildHandler(
          config: proxyOnlyConfig,
          client: testClient,
        );
        final proxyOnlyServer = await shelf_io.serve(
          proxyOnlyHandler,
          'localhost',
          0,
        );
        try {
          final res = await testClient.get(
            Uri.parse('http://localhost:${proxyOnlyServer.port}/'),
          );
          expect(res.statusCode, equals(404));
          expect(res.body, contains('No WEB_ROOT is configured'));
        } finally {
          await proxyOnlyServer.close(force: true);
        }
      },
    );
  });
}
