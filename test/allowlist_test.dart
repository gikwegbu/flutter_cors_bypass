import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:test/test.dart';

void main() {
  group('Allowlist', () {
    test('empty list allows everything', () {
      final allowlist = Allowlist([]);
      expect(allowlist.isEmpty, isTrue);
      expect(allowlist.isAllowed(Uri.parse('https://example.com')), isTrue);
      expect(
        allowlist.isAllowed(Uri.parse('http://any-domain.org:9000/api')),
        isTrue,
      );
    });

    test('exact match is case-insensitive', () {
      final allowlist = Allowlist(['Api.Example.Com']);
      expect(
        allowlist.isAllowed(Uri.parse('https://api.example.com/data')),
        isTrue,
      );
      expect(
        allowlist.isAllowed(Uri.parse('https://API.EXAMPLE.COM/data')),
        isTrue,
      );
      expect(
        allowlist.isAllowed(Uri.parse('https://other.example.com')),
        isFalse,
      );
    });

    test(
      '*.example.com matches subdomains but not example.com itself or badexample.com',
      () {
        final allowlist = Allowlist(['*.example.com']);

        // Subdomains match
        expect(
          allowlist.isAllowed(Uri.parse('https://api.example.com/v1')),
          isTrue,
        );
        expect(
          allowlist.isAllowed(Uri.parse('https://a.b.example.com/v1')),
          isTrue,
        );

        // Base domain does NOT match
        expect(
          allowlist.isAllowed(Uri.parse('https://example.com/v1')),
          isFalse,
        );

        // Suffix collision does NOT match
        expect(
          allowlist.isAllowed(Uri.parse('https://badexample.com/v1')),
          isFalse,
        );
      },
    );

    test('port-qualified entries enforce the port', () {
      final allowlist = Allowlist(['localhost:3000', 'api.test:8443']);

      expect(
        allowlist.isAllowed(Uri.parse('http://localhost:3000/v1')),
        isTrue,
      );
      expect(
        allowlist.isAllowed(Uri.parse('http://localhost:4000/v1')),
        isFalse,
      );

      expect(
        allowlist.isAllowed(Uri.parse('https://api.test:8443/call')),
        isTrue,
      );
      expect(allowlist.isAllowed(Uri.parse('https://api.test/call')), isFalse);
    });

    test('listing both base and wildcard allows both', () {
      final allowlist = Allowlist(['example.com', '*.example.com']);
      expect(allowlist.isAllowed(Uri.parse('https://example.com')), isTrue);
      expect(allowlist.isAllowed(Uri.parse('https://api.example.com')), isTrue);
      expect(allowlist.isAllowed(Uri.parse('https://another.org')), isFalse);
    });
  });
}
