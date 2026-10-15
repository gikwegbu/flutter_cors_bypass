import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('ProxyHandler unit tests', () {
    test('400 for invalid target without calling upstream', () async {
      var upstreamCalled = false;
      final mockClient = MockClient((request) async {
        upstreamCalled = true;
        return http.Response('ok', 200);
      });

      final handler = ProxyHandler(
        client: mockClient,
        allowlist: Allowlist([]),
        proxyPort: 8080,
      );

      final badRequests = [
        Request('GET', Uri.parse('http://localhost:8080/proxy')), // missing url
        Request(
          'GET',
          Uri.parse('http://localhost:8080/proxy?url=ftp://foo'),
        ), // bad scheme
        Request(
          'GET',
          Uri.parse(
            'http://localhost:8080/proxy?url=http://localhost:8080/api',
          ),
        ), // self loop
        Request('GET', Uri.parse('http://localhost:8080/http')), // missing host
      ];

      for (final req in badRequests) {
        final res = await handler.handle(req);
        expect(res.statusCode, equals(400));
        expect(res.headers['access-control-allow-methods'], isNotNull);
      }

      expect(upstreamCalled, isFalse);
    });

    test('403 for host not on allowlist without calling upstream', () async {
      var upstreamCalled = false;
      final mockClient = MockClient((request) async {
        upstreamCalled = true;
        return http.Response('ok', 200);
      });

      final handler = ProxyHandler(
        client: mockClient,
        allowlist: Allowlist(['api.example.com']),
        proxyPort: 8080,
      );

      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/https/forbidden.example.com/api'),
      );

      final res = await handler.handle(req);
      expect(res.statusCode, equals(403));
      final body = await res.readAsString();
      expect(body, contains('forbidden.example.com'));
      expect(body, contains('--allow'));
      expect(res.headers['access-control-allow-methods'], isNotNull);
      expect(upstreamCalled, isFalse);
    });

    test('OPTIONS returns 204 without calling upstream', () async {
      var upstreamCalled = false;
      final mockClient = MockClient((request) async {
        upstreamCalled = true;
        return http.Response('ok', 200);
      });

      final handler = ProxyHandler(
        client: mockClient,
        allowlist: Allowlist([]),
        proxyPort: 8080,
      );

      final req = Request(
        'OPTIONS',
        Uri.parse('http://localhost:8080/https/api.example.com/users'),
        headers: {
          'origin': 'http://localhost:5050',
          'access-control-request-headers': 'authorization, content-type',
        },
      );

      final res = await handler.handle(req);
      expect(res.statusCode, equals(204));
      expect(await res.readAsString(), isEmpty);
      expect(
        res.headers['access-control-allow-origin'],
        equals('http://localhost:5050'),
      );
      expect(
        res.headers['access-control-allow-headers'],
        contains('Authorization'),
      );
      expect(upstreamCalled, isFalse);
    });

    test(
      'forwards method, URL, body, strips forbidden headers and keeps allowed headers',
      () async {
        http.BaseRequest? capturedRequest;
        List<int>? capturedBody;

        final mockClient = MockClient.streaming((req, bodyStream) async {
          capturedRequest = req;
          capturedBody = await bodyStream.toBytes();
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"ok":true}')),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final handler = ProxyHandler(
          client: mockClient,
          allowlist: Allowlist([]),
          proxyPort: 8080,
        );

        final bodyToSend = utf8.encode('{"name":"Ada"}');
        final req = Request(
          'POST',
          Uri.parse(
            'http://localhost:8080/https/api.example.com/users?team=dart',
          ),
          body: bodyToSend,
          headers: {
            'host': 'localhost:8080',
            'origin': 'http://localhost:5050',
            'referer': 'http://localhost:5050/app',
            'content-length': bodyToSend.length.toString(),
            'connection': 'keep-alive',
            'accept-encoding': 'gzip, deflate, br, zstd',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
            'authorization': 'Bearer secret-token-xyz',
            'content-type': 'application/json',
            'accept': 'application/json',
            'cookie': 'session_id=12345',
            'x-api-key': 'key-abc-987',
          },
        );

        final res = await handler.handle(req);
        expect(res.statusCode, equals(200));

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.method, equals('POST'));
        expect(
          capturedRequest!.url,
          equals(Uri.parse('https://api.example.com/users?team=dart')),
        );
        expect(capturedBody, equals(bodyToSend));

        final sentHeaders = capturedRequest!.headers;
        // Stripped headers
        expect(sentHeaders.containsKey('origin'), isFalse);
        expect(sentHeaders.containsKey('referer'), isFalse);
        expect(sentHeaders.containsKey('connection'), isFalse);
        expect(sentHeaders.containsKey('accept-encoding'), isFalse);
        expect(sentHeaders.containsKey('sec-fetch-dest'), isFalse);
        expect(sentHeaders.containsKey('sec-fetch-mode'), isFalse);
        expect(sentHeaders.containsKey('sec-fetch-site'), isFalse);

        // Kept headers
        expect(sentHeaders['authorization'], equals('Bearer secret-token-xyz'));
        expect(sentHeaders['content-type'], equals('application/json'));
        expect(sentHeaders['accept'], equals('application/json'));
        expect(sentHeaders['cookie'], equals('session_id=12345'));
        expect(sentHeaders['x-api-key'], equals('key-abc-987'));
      },
    );

    test(
      'response headers stripped, custom headers exposed, binary body preserved exactly',
      () async {
        final binaryPayload = Uint8List.fromList([
          0x00,
          0x12,
          0x7F,
          0x80,
          0xFE,
          0xFF,
        ]);

        final mockClient = MockClient.streaming((req, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(binaryPayload),
            201,
            headers: {
              'content-encoding': 'gzip',
              'content-length': binaryPayload.length.toString(),
              'transfer-encoding': 'chunked',
              'connection': 'keep-alive',
              'access-control-allow-origin': '*',
              'access-control-allow-methods': 'GET',
              'x-total-count': '42',
              'x-request-id': 'req-999',
            },
          );
        });

        final handler = ProxyHandler(
          client: mockClient,
          allowlist: Allowlist([]),
          proxyPort: 8080,
        );

        final req = Request(
          'GET',
          Uri.parse('http://localhost:8080/https/api.example.com/image.png'),
          headers: {'origin': 'http://localhost:5050'},
        );

        final res = await handler.handle(req);
        expect(res.statusCode, equals(201));

        // Stripped headers
        expect(res.headers.containsKey('content-encoding'), isFalse);
        expect(res.headers.containsKey('content-length'), isFalse);
        expect(res.headers.containsKey('transfer-encoding'), isFalse);
        expect(res.headers.containsKey('connection'), isFalse);

        // Proxy CORS headers replaced upstream access-control-*
        expect(
          res.headers['access-control-allow-origin'],
          equals('http://localhost:5050'),
        );

        // Upstream custom headers kept
        expect(res.headers['x-total-count'], equals('42'));
        expect(res.headers['x-request-id'], equals('req-999'));

        // Expose headers contains upstream headers
        final exposed = res.headers['access-control-expose-headers']!;
        expect(exposed, contains('x-total-count'));
        expect(exposed, contains('x-request-id'));

        // Binary body arrives byte-for-byte identical
        final bodyBytes = await res.read().fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        expect(bodyBytes, equals(binaryPayload));
      },
    );

    test('ClientException produces 502 with CORS headers', () async {
      final mockClient = MockClient((req) async {
        throw http.ClientException('DNS lookup failed for host');
      });

      final handler = ProxyHandler(
        client: mockClient,
        allowlist: Allowlist([]),
        proxyPort: 8080,
      );

      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/https/api.example.com/data'),
        headers: {'origin': 'http://localhost:5050'},
      );

      final res = await handler.handle(req);
      expect(res.statusCode, equals(502));
      expect(
        res.headers['access-control-allow-origin'],
        equals('http://localhost:5050'),
      );
      final body = await res.readAsString();
      expect(
        body,
        contains('Upstream request failed: DNS lookup failed for host'),
      );
    });

    test('timeout produces 504 with CORS headers', () async {
      final mockClient = MockClient((req) async {
        await Completer<void>().future; // Never completes
        return http.Response('ok', 200);
      });

      final handler = ProxyHandler(
        client: mockClient,
        allowlist: Allowlist([]),
        timeout: const Duration(milliseconds: 50),
        proxyPort: 8080,
      );

      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/https/api.example.com/slow'),
        headers: {'origin': 'http://localhost:5050'},
      );

      final res = await handler.handle(req);
      expect(res.statusCode, equals(504));
      expect(
        res.headers['access-control-allow-origin'],
        equals('http://localhost:5050'),
      );
      final body = await res.readAsString();
      expect(body, contains('Upstream timed out'));
    });

    test(
      'logger receives exactly one line per request and never contains Authorization value',
      () async {
        final logLines = <String>[];
        final mockClient = MockClient((req) async {
          return http.Response('echo', 200);
        });

        final handler = ProxyHandler(
          client: mockClient,
          allowlist: Allowlist([]),
          proxyPort: 8080,
          logger: logLines.add,
        );

        const secretToken = 'ultra-secret-bearer-token-12345';
        final req = Request(
          'GET',
          Uri.parse('http://localhost:8080/https/api.example.com/v1/user'),
          headers: {'authorization': 'Bearer $secretToken'},
        );

        final res = await handler.handle(req);
        expect(res.statusCode, equals(200));

        expect(logLines.length, equals(1));
        final logLine = logLines.single;
        expect(
          logLine,
          matches(r'^GET https://api\.example\.com/v1/user -> 200 \(\d+ ms\)$'),
        );
        expect(logLine.contains(secretToken), isFalse);
      },
    );
  });
}
