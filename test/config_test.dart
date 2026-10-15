import 'dart:io';

import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProxyConfig', () {
    test('defaults', () {
      final config = ProxyConfig.parse([], {});
      expect(config.port, equals(8080));
      expect(config.webRoot, isNull);
      expect(config.host, equals('localhost'));
      expect(config.allowHosts, isEmpty);
      expect(config.timeoutSeconds, equals(30));
      expect(config.isHelp, isFalse);
      expect(config.isLoopbackHost, isTrue);
      expect(config.hostWarning, isNull);
    });

    test(
      '--port 9000, --port=9000, -p 9000 all work and flag beats PORT env',
      () {
        final c1 = ProxyConfig.parse(['--port', '9000'], {'PORT': '7000'});
        expect(c1.port, equals(9000));

        final c2 = ProxyConfig.parse(['--port=9000'], {'PORT': '7000'});
        expect(c2.port, equals(9000));

        final c3 = ProxyConfig.parse(['-p', '9000'], {'PORT': '7000'});
        expect(c3.port, equals(9000));

        final c4 = ProxyConfig.parse(['-p=9000'], {'PORT': '7000'});
        expect(c4.port, equals(9000));
      },
    );

    test('PORT env alone works', () {
      final config = ProxyConfig.parse([], {'PORT': '9090'});
      expect(config.port, equals(9090));
    });

    test('invalid port (0, 70000, abc) throws ConfigException', () {
      expect(
        () => ProxyConfig.parse(['--port', '0'], {}),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ProxyConfig.parse(['--port', '70000'], {}),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ProxyConfig.parse(['--port', 'abc'], {}),
        throwsA(isA<ConfigException>()),
      );
    });

    test(
      '--web-root with existing temp dir resolves to absolute normalised path',
      () {
        final tempDir = Directory.systemTemp.createTempSync('web_root_test_');
        try {
          final config = ProxyConfig.parse(['--web-root', tempDir.path], {});
          expect(config.webRoot, equals(p.normalize(p.absolute(tempDir.path))));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test('--web-root with relative path is made absolute', () {
      final relDir = Directory(
        p.join(Directory.current.path, 'rel_root_test_dir'),
      )..createSync();
      try {
        final config = ProxyConfig.parse(['-w', 'rel_root_test_dir'], {});
        expect(p.isAbsolute(config.webRoot!), isTrue);
        expect(config.webRoot, equals(p.normalize(relDir.path)));
      } finally {
        relDir.deleteSync(recursive: true);
      }
    });

    test('~ expansion uses provided HOME', () {
      final tempHome = Directory.systemTemp.createTempSync('home_test_');
      final subDir = Directory(p.join(tempHome.path, 'site'))..createSync();
      try {
        final config = ProxyConfig.parse(
          ['--web-root', '~/site'],
          {'HOME': tempHome.path},
        );
        expect(config.webRoot, equals(p.normalize(subDir.path)));
      } finally {
        tempHome.deleteSync(recursive: true);
      }
    });

    test(
      'non-existent web root throws ConfigException mentioning flutter build web --profile',
      () {
        final nonExistent = p.join(
          Directory.systemTemp.path,
          'does_not_exist_xyz123',
        );
        expect(
          () => ProxyConfig.parse(['--web-root', nonExistent], {}),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.message,
              'message',
              contains('flutter build web --profile'),
            ),
          ),
        );
      },
    );

    test(
      '--allow a.com --allow b.com,c.com and ALLOW_HOSTS produce expected list',
      () {
        final config1 = ProxyConfig.parse([
          '-a',
          'a.com',
          '--allow',
          'b.com,c.com',
        ], {});
        expect(config1.allowHosts, equals(['a.com', 'b.com', 'c.com']));

        final config2 = ProxyConfig.parse([], {'ALLOW_HOSTS': 'a.com,b.com'});
        expect(config2.allowHosts, equals(['a.com', 'b.com']));
      },
    );

    test(
      'unknown flag and missing value throw ConfigException containing usage text',
      () {
        expect(
          () => ProxyConfig.parse(['--unknown-flag'], {}),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.message,
              'message',
              contains('Usage: flutter_cors_bypass'),
            ),
          ),
        );
        expect(
          () => ProxyConfig.parse(['--port'], {}),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.message,
              'message',
              contains('Usage: flutter_cors_bypass'),
            ),
          ),
        );
        expect(
          () => ProxyConfig.parse(['unexpected_arg'], {}),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.message,
              'message',
              contains('Usage: flutter_cors_bypass'),
            ),
          ),
        );
      },
    );

    test('--help signals help', () {
      final c1 = ProxyConfig.parse(['--help'], {});
      expect(c1.isHelp, isTrue);

      final c2 = ProxyConfig.parse(['-h'], {});
      expect(c2.isHelp, isTrue);
    });

    test('timeout parsing and validation', () {
      final c1 = ProxyConfig.parse(['-t', '45'], {});
      expect(c1.timeoutSeconds, equals(45));
      expect(c1.timeout, equals(const Duration(seconds: 45)));

      final c2 = ProxyConfig.parse([], {'TIMEOUT': '60'});
      expect(c2.timeoutSeconds, equals(60));

      expect(
        () => ProxyConfig.parse(['--timeout', '0'], {}),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ProxyConfig.parse(['--timeout', '-5'], {}),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ProxyConfig.parse(['--timeout', 'invalid'], {}),
        throwsA(isA<ConfigException>()),
      );
    });

    test(
      '--host non-loopback generates warning and respects allowlist note',
      () {
        final c1 = ProxyConfig.parse(['--host', '0.0.0.0'], {});
        expect(c1.isLoopbackHost, isFalse);
        expect(
          c1.hostWarning,
          contains('WARNING: OPEN PROXY EXPOSED TO NETWORK!'),
        );
        expect(c1.hostWarning, contains('The allowlist is EMPTY'));

        final c2 = ProxyConfig.parse([
          '--host',
          '192.168.1.100',
          '-a',
          'api.test',
        ], {});
        expect(c2.isLoopbackHost, isFalse);
        expect(c2.hostWarning, contains('Allowlist: api.test'));
      },
    );
  });
}
