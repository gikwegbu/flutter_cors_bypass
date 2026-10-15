import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';

Future<void> main(List<String> args) async {
  ProxyConfig config;
  try {
    config = ProxyConfig.parse(args, Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }

  if (config.isHelp) {
    stdout.writeln(ProxyConfig.usageText);
    exit(0);
  }

  final client = http.Client();
  final handler = buildHandler(config: config, client: client);

  HttpServer server;
  try {
    server = await shelf_io.serve(handler, config.host, config.port);
  } on SocketException catch (e) {
    client.close();
    final reason = e.message.isNotEmpty
        ? e.message
        : (e.osError?.message ?? e.toString());
    stderr.writeln(
      'Could not listen on ${config.host}:${config.port}: $reason. '
      'Is another instance running? Try --port <other>.',
    );
    exit(1);
  }

  // Network exposure warning if non-loopback
  final warning = config.hostWarning;
  if (warning != null) {
    stdout.writeln(warning);
  }

  final staticStatus =
      config.webRoot ??
      'disabled (set --web-root or WEB_ROOT to serve a Flutter build)';
  final allowStatus = config.allowHosts.isEmpty
      ? 'all hosts'
      : config.allowHosts.join(', ');

  stdout.writeln(
    '''flutter_cors_bypass (LOCAL DEVELOPMENT ONLY - this is an open proxy, don't say I didn't warnya 😂)
Listening on http://${config.host}:${config.port}
Query style: http://${config.host}:${config.port}/proxy?url=<url-encoded URL>
Path style:  http://${config.host}:${config.port}/https/<host>/<path>
Static:      $staticStatus
Allowlist:   $allowStatus
Press Ctrl+C to stop.''',
  );

  var isShuttingDown = false;
  Future<void> shutdown() async {
    if (isShuttingDown) return;
    isShuttingDown = true;
    stdout.writeln('\nShutting down flutter_cors_bypass...');
    await server.close(force: true);
    client.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }
}
