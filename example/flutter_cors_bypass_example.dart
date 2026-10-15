import 'package:flutter_cors_bypass/flutter_cors_bypass.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() async {
  // 1. Configure the proxy server
  final config = ProxyConfig(
    port: 8080,
    host: 'localhost',
    timeoutSeconds: 30,
    // Optional: restrict allowed upstream hosts
    allowHosts: ['httpbin.org', 'api.example.com'],
  );

  // 2. Build the shelf handler and start the local proxy server
  final handler = buildHandler(config: config);
  final server = await shelf_io.serve(handler, config.host, config.port);
  print('CORS proxy listening on http://${config.host}:${server.port}');

  // 3. Construct proxied URLs
  // Path-style: ideal for base URLs in Dio, Chopper, Retrofit, etc.
  final baseApi = proxiedUrl(
    'https://httpbin.org',
    proxyBase: 'http://localhost:8080',
  );
  print('Proxied Base URL: $baseApi');
  print('Appended Endpoint: $baseApi/get?param=value');

  // Query-style: for one-off complete URLs
  final queryUri = proxyQueryUri(
    'https://httpbin.org/get?a=1&b=2',
    proxyBase: 'http://localhost:8080',
  );
  print('Query Style URI:  $queryUri');

  // 4. Send a proxied request
  final response = await http.get(Uri.parse('$baseApi/get?param=value'));
  print('Upstream Status:  ${response.statusCode}');
  print(
    'CORS Headers:     ${response.headers['access-control-allow-methods']}',
  );

  // Clean shutdown
  await server.close(force: true);
  print('Server cleanly stopped.');
}
