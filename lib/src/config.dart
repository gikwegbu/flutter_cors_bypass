import 'dart:io';

import 'package:path/path.dart' as p;

/// Exception thrown when configuration parsing or validation fails.
class ConfigException implements Exception {
  /// The error message.
  final String message;

  /// Whether this exception was triggered by a help request.
  final bool isHelp;

  /// Creates a [ConfigException].
  ConfigException(this.message, {this.isHelp = false});

  @override
  String toString() => message;
}

/// Configuration options for the `flutter_cors_bypass` server.
class ProxyConfig {
  /// The port the server listens on (default: 8080).
  final int port;

  /// The root directory to serve static files from, or `null` for proxy-only mode.
  final String? webRoot;

  /// The host interface to bind to (default: 'localhost').
  final String host;

  /// The list of allowed target hosts, or empty to allow all hosts.
  final List<String> allowHosts;

  /// Upstream request timeout in seconds (default: 30).
  final int timeoutSeconds;

  /// Whether help was requested via `-h` or `--help`.
  final bool isHelp;

  /// Creates a [ProxyConfig] instance.
  const ProxyConfig({
    this.port = 8080,
    this.webRoot,
    this.host = 'localhost',
    this.allowHosts = const [],
    this.timeoutSeconds = 30,
    this.isHelp = false,
  });

  /// Timeout duration for upstream requests.
  Duration get timeout => Duration(seconds: timeoutSeconds);

  /// Whether [host] is a loopback address.
  bool get isLoopbackHost =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  /// Warning message when binding to a non-loopback host.
  String? get hostWarning {
    if (isLoopbackHost) return null;
    final allowlistNote = allowHosts.isEmpty
        ? 'The allowlist is EMPTY: anyone can proxy requests to ANY host.\nIt is strongly recommended to specify allowed hosts with --allow.'
        : 'Allowlist: ${allowHosts.join(', ')}';
    return '''
================================================================================
WARNING: OPEN PROXY EXPOSED TO NETWORK!
The proxy is bound to "$host", which is not a loopback address (localhost/127.0.0.1/::1).
Anyone on your local network can reach this proxy and send requests through it,
including requests with credentials, cookies, and tokens.
$allowlistNote
================================================================================''';
  }

  /// Usage text explaining CLI flags and environment variables.
  static const String usageText = '''
flutter_cors_bypass - Local development CORS proxy for Flutter Web

Usage: flutter_cors_bypass [options]

Options:
  -p, --port <port>         Port to listen on (default: 8080, env: PORT)
  -w, --web-root <path>     Directory to serve static files from (env: WEB_ROOT)
      --host <host>         Host interface to bind to (default: localhost, env: HOST)
  -a, --allow <host>        Allowed upstream host (repeatable / comma-separated, env: ALLOW_HOSTS)
  -t, --timeout <seconds>   Upstream request timeout in seconds (default: 30, env: TIMEOUT)
  -h, --help                Show this help message''';

  /// Parses command-line arguments and environment variables into a [ProxyConfig].
  ///
  /// Flags take precedence over environment variables, which take precedence
  /// over defaults. Throws [ConfigException] on invalid arguments or missing directories.
  static ProxyConfig parse(List<String> args, Map<String, String> environment) {
    String? portArg;
    String? webRootArg;
    String? hostArg;
    final allowFlags = <String>[];
    String? timeoutArg;

    var i = 0;
    while (i < args.length) {
      final arg = args[i];

      if (arg == '-h' || arg == '--help') {
        return const ProxyConfig(isHelp: true);
      } else if (arg == '-p' || arg == '--port') {
        if (i + 1 >= args.length) {
          throw ConfigException(
            'Missing value for option "$arg".\n\n$usageText',
          );
        }
        portArg = args[++i];
      } else if (arg.startsWith('--port=')) {
        portArg = arg.substring('--port='.length);
      } else if (arg.startsWith('-p=')) {
        portArg = arg.substring('-p='.length);
      } else if (arg == '-w' || arg == '--web-root') {
        if (i + 1 >= args.length) {
          throw ConfigException(
            'Missing value for option "$arg".\n\n$usageText',
          );
        }
        webRootArg = args[++i];
      } else if (arg.startsWith('--web-root=')) {
        webRootArg = arg.substring('--web-root='.length);
      } else if (arg.startsWith('-w=')) {
        webRootArg = arg.substring('-w='.length);
      } else if (arg == '--host') {
        if (i + 1 >= args.length) {
          throw ConfigException(
            'Missing value for option "$arg".\n\n$usageText',
          );
        }
        hostArg = args[++i];
      } else if (arg.startsWith('--host=')) {
        hostArg = arg.substring('--host='.length);
      } else if (arg == '-a' || arg == '--allow') {
        if (i + 1 >= args.length) {
          throw ConfigException(
            'Missing value for option "$arg".\n\n$usageText',
          );
        }
        allowFlags.add(args[++i]);
      } else if (arg.startsWith('--allow=')) {
        allowFlags.add(arg.substring('--allow='.length));
      } else if (arg.startsWith('-a=')) {
        allowFlags.add(arg.substring('-a='.length));
      } else if (arg == '-t' || arg == '--timeout') {
        if (i + 1 >= args.length) {
          throw ConfigException(
            'Missing value for option "$arg".\n\n$usageText',
          );
        }
        timeoutArg = args[++i];
      } else if (arg.startsWith('--timeout=')) {
        timeoutArg = arg.substring('--timeout='.length);
      } else if (arg.startsWith('-t=')) {
        timeoutArg = arg.substring('-t='.length);
      } else if (arg.startsWith('-')) {
        throw ConfigException('Unknown option "$arg".\n\n$usageText');
      } else {
        throw ConfigException('Unexpected argument "$arg".\n\n$usageText');
      }
      i++;
    }

    // Resolve port
    final rawPort = portArg ?? environment['PORT'] ?? '8080';
    final parsedPort = int.tryParse(rawPort);
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      throw ConfigException(
        'Invalid port: "$rawPort". Port must be an integer between 1 and 65535.\n\n$usageText',
      );
    }

    // Resolve timeout
    final rawTimeout = timeoutArg ?? environment['TIMEOUT'] ?? '30';
    final parsedTimeout = int.tryParse(rawTimeout);
    if (parsedTimeout == null || parsedTimeout <= 0) {
      throw ConfigException(
        'Invalid timeout: "$rawTimeout". Timeout must be a positive integer.\n\n$usageText',
      );
    }

    // Resolve host
    final host = hostArg ?? environment['HOST'] ?? 'localhost';

    // Resolve allowlist
    final allowHosts = <String>[];
    if (allowFlags.isNotEmpty) {
      for (final flag in allowFlags) {
        for (final item in flag.split(',')) {
          final trimmed = item.trim();
          if (trimmed.isNotEmpty) {
            allowHosts.add(trimmed);
          }
        }
      }
    } else if (environment.containsKey('ALLOW_HOSTS')) {
      final envAllow = environment['ALLOW_HOSTS']!;
      for (final item in envAllow.split(',')) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty) {
          allowHosts.add(trimmed);
        }
      }
    }

    // Resolve web root
    String? webRoot = webRootArg ?? environment['WEB_ROOT'];
    if (webRoot != null && webRoot.trim().isNotEmpty) {
      webRoot = webRoot.trim();
      if (webRoot.startsWith('~')) {
        final home = environment['HOME'] ?? '';
        webRoot = home.isEmpty
            ? webRoot.substring(1)
            : p.join(
                home,
                webRoot.substring(1).replaceFirst(RegExp(r'^[/\\]'), ''),
              );
      }
      final resolved = p.normalize(
        p.isAbsolute(webRoot)
            ? webRoot
            : p.join(Directory.current.path, webRoot),
      );
      if (!Directory(resolved).existsSync()) {
        throw ConfigException(
          'Web root directory does not exist: "$resolved". Try running "flutter build web --profile" first.\n\n$usageText',
        );
      }
      webRoot = resolved;
    } else {
      webRoot = null;
    }

    return ProxyConfig(
      port: parsedPort,
      webRoot: webRoot,
      host: host,
      allowHosts: List.unmodifiable(allowHosts),
      timeoutSeconds: parsedTimeout,
    );
  }
}
