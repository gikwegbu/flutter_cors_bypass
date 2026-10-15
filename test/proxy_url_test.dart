import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:test/test.dart';

void main() {
  group('proxiedUrl', () {
    test('proxiedUrl with standard base', () {
      final result = proxiedUrl(
        'https://api.example.com',
        proxyBase: 'http://localhost:8080',
      );
      expect(result, equals('http://localhost:8080/https/api.example.com'));
    });

    test('proxiedUrl with trailing slash on proxyBase', () {
      final result = proxiedUrl(
        'https://api.example.com',
        proxyBase: 'http://localhost:8080/',
      );
      expect(result, equals('http://localhost:8080/https/api.example.com'));
    });

    test('proxiedUrl with port in target', () {
      final result = proxiedUrl(
        'http://localhost:3000',
        proxyBase: 'http://localhost:8080',
      );
      expect(result, equals('http://localhost:8080/http/localhost:3000'));
    });

    test('proxiedUrl with base path in target', () {
      final result = proxiedUrl(
        'https://api.example.com/v2',
        proxyBase: 'http://localhost:8080',
      );
      expect(result, equals('http://localhost:8080/https/api.example.com/v2'));
    });

    test('proxiedUrl with query in target', () {
      final result = proxiedUrl(
        'https://api.example.com/v2?key=val',
        proxyBase: 'http://localhost:8080',
      );
      expect(
        result,
        equals('http://localhost:8080/https/api.example.com/v2?key=val'),
      );
    });

    test('proxiedUrl with empty proxyBase returns relative path', () {
      final result = proxiedUrl('https://api.example.com', proxyBase: '');
      expect(result, equals('/https/api.example.com'));
    });
  });

  group('proxyQueryUri', () {
    test('proxyQueryUri with standard base', () {
      final uri = proxyQueryUri(
        'https://api.example.com/users',
        proxyBase: 'http://localhost:8080',
      );
      expect(uri.scheme, equals('http'));
      expect(uri.host, equals('localhost'));
      expect(uri.port, equals(8080));
      expect(uri.path, equals('/proxy'));
      expect(
        uri.queryParameters['url'],
        equals('https://api.example.com/users'),
      );
    });

    test('proxyQueryUri correctly encodes ?, &, =, spaces and #', () {
      const complexTarget =
          'https://api.example.com/search?query=hello world&filter=a=1&b=2#section';
      final uri = proxyQueryUri(
        complexTarget,
        proxyBase: 'http://localhost:8080',
      );

      // Decoding the url parameter gives back the original URL exactly
      final extracted = uri.queryParameters['url'];
      expect(extracted, equals(complexTarget));
    });

    test(
      'proxyQueryUri with empty proxyBase returns relative /proxy?url=...',
      () {
        const target = 'https://api.example.com/items?a=1';
        final uri = proxyQueryUri(target, proxyBase: '');
        expect(uri.path, equals('/proxy'));
        expect(uri.hasScheme, isFalse);
        expect(uri.queryParameters['url'], equals(target));
        expect(
          Uri.decodeComponent(uri.queryParameters['url']!),
          equals(target),
        );
      },
    );
  });
}
