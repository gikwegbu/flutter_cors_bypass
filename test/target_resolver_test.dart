import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('TargetResolver - Query style', () {
    test('valid URL resolves correctly', () {
      final req = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/proxy?url=https%3A%2F%2Fapi.example.com%2Fusers',
        ),
      );
      final res = resolveTarget(req, proxyPort: 8080);
      expect(res.isSuccess, isTrue);
      expect(res.uri, equals(Uri.parse('https://api.example.com/users')));
    });

    test('URL whose own query has & survives', () {
      final target = 'https://api.example.com/users?a=1&b=2&tag=x&tag=y';
      final encoded = Uri.encodeComponent(target);
      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/proxy?url=$encoded'),
      );
      final res = resolveTarget(req, proxyPort: 8080);
      expect(res.isSuccess, isTrue);
      expect(res.uri.toString(), equals(target));
      expect(res.uri!.query, equals('a=1&b=2&tag=x&tag=y'));
    });

    test(
      'missing, empty, relative, ftp:, mailto: and hostless URLs return error',
      () {
        final cases = [
          'http://localhost:8080/proxy', // missing
          'http://localhost:8080/proxy?url=', // empty
          'http://localhost:8080/proxy?url=%2Frelative%2Fpath', // relative
          'http://localhost:8080/proxy?url=ftp%3A%2F%2Fexample.com', // ftp
          'http://localhost:8080/proxy?url=mailto%3Atest%40example.com', // mailto
          'http://localhost:8080/proxy?url=http%3A%2F%2F%2Fpath', // hostless
        ];

        for (final uriStr in cases) {
          final req = Request('GET', Uri.parse(uriStr));
          final res = resolveTarget(req, proxyPort: 8080);
          expect(res.isError, isTrue, reason: 'Expected error for $uriStr');
        }
      },
    );

    test('self-loop detection for query style', () {
      final loopCases = [
        'http://localhost:8080/proxy?url=http%3A%2F%2Flocalhost%3A8080%2Fapi',
        'http://localhost:8080/proxy?url=http%3A%2F%2F127.0.0.1%3A8080%2Fapi',
        'http://localhost:8080/proxy?url=http%3A%2F%2F0.0.0.0%3A8080%2Fapi',
        'http://localhost:8080/proxy?url=http%3A%2F%2F%5B%3A%3A1%5D%3A8080%2Fapi',
      ];

      for (final uriStr in loopCases) {
        final req = Request('GET', Uri.parse(uriStr));
        final res = resolveTarget(req, proxyPort: 8080);
        expect(res.isError, isTrue);
        expect(res.error, contains('points back to the proxy itself'));
      }

      // Same host on another port -> OK
      final okReq = Request(
        'GET',
        Uri.parse(
          'http://localhost:8080/proxy?url=http%3A%2F%2Flocalhost%3A3000%2Fapi',
        ),
      );
      final okRes = resolveTarget(okReq, proxyPort: 8080);
      expect(okRes.isSuccess, isTrue);
      expect(okRes.uri, equals(Uri.parse('http://localhost:3000/api')));
    });
  });

  group('TargetResolver - Path style', () {
    test(
      'https/api.example.com/users?a=1&b=2 preserves query and repeated keys exactly',
      () {
        final req = Request(
          'GET',
          Uri.parse(
            'http://localhost:8080/https/api.example.com/users?a=1&b=2&tag=x&tag=y',
          ),
        );
        final res = resolveTarget(req, proxyPort: 8080);
        expect(res.isSuccess, isTrue);
        expect(
          res.uri.toString(),
          equals('https://api.example.com/users?a=1&b=2&tag=x&tag=y'),
        );
        expect(res.uri!.query, equals('a=1&b=2&tag=x&tag=y'));
      },
    );

    test('http/localhost:3000/v1 keeps port', () {
      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/http/localhost:3000/v1'),
      );
      final res = resolveTarget(req, proxyPort: 8080);
      expect(res.isSuccess, isTrue);
      expect(res.uri, equals(Uri.parse('http://localhost:3000/v1')));
    });

    test('https/api.example.com resolves to path /', () {
      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/https/api.example.com'),
      );
      final res = resolveTarget(req, proxyPort: 8080);
      expect(res.isSuccess, isTrue);
      expect(res.uri, equals(Uri.parse('https://api.example.com/')));
    });

    test('percent-encoded path segments are preserved unchanged', () {
      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/https/api.example.com/files/a%2Fb'),
      );
      final res = resolveTarget(req, proxyPort: 8080);
      expect(res.isSuccess, isTrue);
      expect(res.uri.toString(), equals('https://api.example.com/files/a%2Fb'));
    });

    test('bad scheme segment is recognized as non-proxy or error', () {
      final req1 = Request(
        'GET',
        Uri.parse('http://localhost:8080/ftp/example.com/file'),
      );
      final res1 = resolveTarget(req1, proxyPort: 8080);
      expect(res1.isProxyRoute, isFalse);

      final req2 = Request(
        'GET',
        Uri.parse('http://localhost:8080/static/index.html'),
      );
      final res2 = resolveTarget(req2, proxyPort: 8080);
      expect(res2.isProxyRoute, isFalse);
    });

    test('missing host returns error', () {
      final req1 = Request('GET', Uri.parse('http://localhost:8080/https'));
      final res1 = resolveTarget(req1, proxyPort: 8080);
      expect(res1.isError, isTrue);
      expect(res1.error, contains('Missing target host'));

      final req2 = Request('GET', Uri.parse('http://localhost:8080/https/'));
      final res2 = resolveTarget(req2, proxyPort: 8080);
      expect(res2.isError, isTrue);
      expect(res2.error, contains('Missing target host'));
    });

    test('IPv6 literal hosts return error suggesting query style', () {
      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/http/[::1]:8080/api'),
      );
      final res = resolveTarget(req, proxyPort: 8080);
      expect(res.isError, isTrue);
      expect(
        res.error,
        contains('IPv6 literal hosts are not supported in path style'),
      );
      expect(res.error, contains('/proxy?url=<url>'));
    });

    test('self-loop detection for path style', () {
      final loopReq = Request(
        'GET',
        Uri.parse('http://localhost:8080/http/localhost:8080/api'),
      );
      final loopRes = resolveTarget(loopReq, proxyPort: 8080);
      expect(loopRes.isError, isTrue);
      expect(loopRes.error, contains('points back to the proxy itself'));

      // Same host on different port -> OK
      final okReq = Request(
        'GET',
        Uri.parse('http://localhost:8080/http/localhost:3000/api'),
      );
      final okRes = resolveTarget(okReq, proxyPort: 8080);
      expect(okRes.isSuccess, isTrue);
      expect(okRes.uri, equals(Uri.parse('http://localhost:3000/api')));
    });
  });
}
