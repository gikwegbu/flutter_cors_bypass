import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('CORS', () {
    test('reflects Origin header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/proxy?url=https://api.example.com'),
        headers: {'origin': 'http://localhost:5050'},
      );

      final headers = corsHeaders(request);
      expect(
        headers['access-control-allow-origin'],
        equals('http://localhost:5050'),
      );
    });

    test('omits allow-origin when there is no Origin header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/proxy?url=https://api.example.com'),
      );

      final headers = corsHeaders(request);
      expect(headers.containsKey('access-control-allow-origin'), isFalse);
    });

    test('includes all methods, base headers, max-age, and Vary: Origin', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/proxy?url=https://api.example.com'),
      );

      final headers = corsHeaders(request);
      expect(
        headers['access-control-allow-methods'],
        equals('GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS'),
      );
      expect(headers['access-control-max-age'], equals('600'));
      expect(headers['vary'], equals('Origin'));
      expect(
        headers['access-control-allow-headers'],
        equals('Origin, Content-Type, Accept, Authorization'),
      );
    });

    test('adds requested headers and dedupes them case-insensitively', () {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:8080/proxy?url=https://api.example.com'),
        headers: {
          'origin': 'http://localhost:3000',
          'access-control-request-headers':
              'Authorization, authorization, X-Api-Key, content-type',
        },
      );

      final headers = corsHeaders(request);
      expect(
        headers['access-control-allow-headers'],
        equals('Origin, Content-Type, Accept, Authorization, X-Api-Key'),
      );
    });

    test('includes expose headers when provided', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/proxy?url=https://api.example.com'),
      );

      final headers = corsHeaders(
        request,
        exposeHeaders: ['x-total-count', 'x-request-id'],
      );
      expect(
        headers['access-control-expose-headers'],
        equals('x-total-count, x-request-id'),
      );
    });

    test(
      'preflightResponse returns 204 with empty body and CORS headers',
      () async {
        final request = Request(
          'OPTIONS',
          Uri.parse('http://localhost:8080/https/api.example.com/data'),
          headers: {
            'origin': 'http://localhost:5050',
            'access-control-request-headers': 'authorization, x-token',
          },
        );

        final response = preflightResponse(request);
        expect(response.statusCode, equals(204));
        expect(await response.readAsString(), isEmpty);
        expect(
          response.headers['access-control-allow-origin'],
          equals('http://localhost:5050'),
        );
        expect(
          response.headers['access-control-allow-headers'],
          contains('Authorization'),
        );
        expect(
          response.headers['access-control-allow-headers'],
          contains('x-token'),
        );
      },
    );
  });
}
