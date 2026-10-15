# flutter_cors_bypass

A local development CORS proxy for Flutter Web. When a Flutter Web app calls a third-party API that doesn't send CORS headers or doesn't allow `localhost` origins, the browser blocks the response and Flutter reports `ClientException: Failed to fetch` or a CORS error in DevTools. `flutter_cors_bypass` runs locally on `localhost:8080`, forwards requests to upstream APIs, and attaches the required CORS headers so the browser stops blocking them.

> [!WARNING]
> **LOCAL DEVELOPMENT ONLY — THIS IS AN OPEN PROXY.**
> This tool forwards arbitrary HTTP requests and headers (including `Authorization`, cookies, and API keys) to any reachable host.
> It binds to `localhost` by default and must **never** be deployed to a public server, test environment, or production infrastructure. Anyone with access to the proxy can use it to relay network traffic and execute requests with your credentials.

---

## How It Works

```
Flutter App (localhost:5050)  ───>  flutter_cors_bypass (localhost:8080)  ───>  API (api.example.com)
            (Browser)                            (Dart Server)                      (Remote Backend)
```

Browser security restrictions enforce CORS only for browser-initiated requests. Server-to-server HTTP requests are not subject to CORS policies. `flutter_cors_bypass` receives your browser's request on `localhost:8080`, forwards it directly to the target API, and returns the response with permissive `Access-Control-Allow-*` headers matching your browser's origin.

---

## Installation

### Globally (Recommended)

From pub.dev:
```sh
dart pub global activate flutter_cors_bypass
```

Or from Git:
```sh
dart pub global activate --source git https://github.com/georgeikwegbu/flutter_cors_bypass.git
```

Or from a local path:
```sh
dart pub global activate --source path /path/to/flutter_cors_bypass
```

Ensure `~/.pub-cache/bin` (or `%LOCALAPPDATA%\Pub\Cache\bin` on Windows) is included in your system `PATH`. Alternatively, execute directly with:
```sh
dart pub global run flutter_cors_bypass
```

### Per Project

```sh
flutter pub add --dev flutter_cors_bypass
```

Run with:
```sh
dart run flutter_cors_bypass
```

---

## Quick Start (5 Steps)

### 1. Copy `api_url.dart`

Copy [`example/api_url.dart`](example/api_url.dart) into your Flutter project at `lib/core/api_url.dart`:

```dart
// lib/core/api_url.dart
import 'package:flutter/foundation.dart';

const String _proxyBase = String.fromEnvironment('PROXY_BASE');
const bool _useProxy = bool.fromEnvironment('USE_PROXY', defaultValue: true);
bool get _shouldProxy => kIsWeb && !kReleaseMode && _useProxy;

String get _base => _proxyBase.endsWith('/')
    ? _proxyBase.substring(0, _proxyBase.length - 1)
    : _proxyBase;

String proxied(String baseUrl) {
  if (!_shouldProxy) return baseUrl;
  final uri = Uri.parse(baseUrl);
  final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$_base/${uri.scheme}/$authority${uri.path}$query';
}

Uri apiUri(String targetUrl) {
  if (!_shouldProxy) return Uri.parse(targetUrl);
  final query = {'url': targetUrl};
  if (_base.isEmpty) {
    return Uri(path: '/proxy', queryParameters: query);
  }
  final base = Uri.parse(_base);
  return base.replace(path: '${base.path}/proxy', queryParameters: query);
}
```

### 2. Wrap API URLs

Wrap your base URL or complete endpoint URLs where your client configures them:

**For a full URL:**
```dart
// Before:
final response = await http.post(Uri.parse(url), headers: headers, body: body);

// After:
import 'package:<your_app>/core/api_url.dart';
final response = await http.post(apiUri(url), headers: headers, body: body);
```

**For an API base URL (e.g. Dio, Chopper, Retrofit):**
```dart
// Before:
const baseUrl = 'https://api.example.com';

// After:
import 'package:<your_app>/core/api_url.dart';
final baseUrl = proxied('https://api.example.com');
```

### 3. Start the Proxy (Terminal 1)

```sh
flutter_cors_bypass
```

### 4. Run Flutter Web (Terminal 2)

```sh
flutter run -d chrome --web-port 5050 --dart-define=PROXY_BASE=http://localhost:8080
```

> [!IMPORTANT]
> **On macOS, port 5000 is typically reserved by AirPlay Receiver (Control Center).**
> Attempting to run Flutter on port 5000 causes: `Failed to bind web development server ... Address already in use ... port = 5000`.
> Always use `--web-port 5050` (or another free port), or disable AirPlay Receiver in **System Settings → General → AirDrop & Handoff → AirPlay Receiver**. Check what holds the port using:
> ```sh
> lsof -nP -iTCP:5000 -sTCP:LISTEN
> ```

### 5. Verify in Browser & Proxy Log

Open your app at the **`flutter run` port** (e.g. `http://localhost:5050`), **not** at `8080`.
Inspect your browser's DevTools Network tab: calls will be directed to `http://localhost:8080/...`, and the proxy terminal will log each request:
```
POST https://api.example.com/users -> 201 (240 ms)
```

---

## Workflow A: Built App Served by Proxy (Same Origin)

When your app is compiled and served directly by `flutter_cors_bypass`, API requests and static assets share the same origin (`http://localhost:8080`), eliminating cross-origin checks completely:

```sh
flutter build web --profile
flutter_cors_bypass --web-root build/web
```

Open `http://localhost:8080`. No `--dart-define=PROXY_BASE` is needed because `proxied()` and `apiUri()` generate relative, same-origin paths (`/https/...` and `/proxy?...`).

> [!IMPORTANT]
> Always compile with `--profile` (or `--debug`). A standard `flutter build web` produces a **release** build. In release mode, `kReleaseMode` is `true`, causing the helper to bypass the proxy by design, triggering CORS errors again!

The proxy includes **SPA fallback**: any `GET` request for a route without a file extension (e.g. `/settings/profile`) automatically serves `index.html`, preserving deep links and browser refreshes.

---

## Workflow B: `flutter run` with Hot Reload (Cross-Origin)

1. **Terminal 1**: `flutter_cors_bypass`
2. **Terminal 2**: `flutter run -d chrome --web-port 5050 --dart-define=PROXY_BASE=http://localhost:8080`

> [!NOTE]
> `--dart-define` values are resolved at compile time. Whenever you add or edit `--dart-define`, **stop `flutter run` and restart it**. Hot reload and hot restart do not update compile-time constants.

### IDE Configurations

**VS Code (`.vscode/launch.json`):**
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Web (CORS proxy)",
      "request": "launch",
      "type": "dart",
      "deviceId": "chrome",
      "args": [
        "--web-port",
        "5050",
        "--dart-define=PROXY_BASE=http://localhost:8080"
      ]
    }
  ]
}
```

**Android Studio / IntelliJ:**
1. Go to **Run → Edit Configurations...**
2. Select your Flutter configuration.
3. In **Additional run args**, add:
   ```
   --web-port 5050 --dart-define=PROXY_BASE=http://localhost:8080
   ```

---

## Release Safety (`kReleaseMode`)

The client helper enforces this guard:
```dart
bool get _shouldProxy => kIsWeb && !kReleaseMode && _useProxy;
```

Because `kReleaseMode` is a compile-time constant from `package:flutter/foundation.dart`, tree-shaking completely removes the proxy code and rewrites in production release builds.

| Build Command | Mode | Uses Proxy? |
|---|---|---|
| `flutter run -d chrome ...` | debug | **Yes** (Workflow B) |
| `flutter build web --profile` | profile | **Yes** (Workflow A) |
| `flutter build web --debug` | debug | **Yes** |
| `flutter build web` (production) | release | **No**: calls real API |
| Android / iOS / desktop (any mode) | any | **No** (CORS does not exist on native platforms) |

> [!CAUTION]
> **Never deploy a debug or profile web build to a hosted test, staging, or production server.**
> Non-release builds will route API requests to proxy paths on that server and fail. Hosted environments must strictly receive release builds. To create a non-release build that calls the API directly without the proxy, pass `--dart-define=USE_PROXY=false`.

---

## `proxied()` vs `apiUri()`

| Situation | `proxied(base)` | `apiUri(url)` |
|---|---|---|
| Web, debug/profile, `PROXY_BASE` set | `$PROXY_BASE/https/host/path` | `$PROXY_BASE/proxy?url=<encoded>` |
| Web, debug/profile, `PROXY_BASE` empty | `/https/host/path` (same origin) | `/proxy?url=<encoded>` (same origin) |
| Web, **release** (`flutter build web`) | unchanged | unchanged |
| `--dart-define=USE_PROXY=false` | unchanged | unchanged |
| Android / iOS / desktop | unchanged | unchanged |

### Why `proxied()` Uses Path Style

With query style (`/proxy?url=...`), wrapping only a base URL (`/proxy?url=https%3A%2F%2Fapi.com`) and then appending `/users?a=1&b=2` produces:
```
http://localhost:8080/proxy?url=https%3A%2F%2Fapi.com/users?a=1&b=2
```
In this broken URL, `&b=2` is parsed as a query parameter for the proxy server itself, silently stripping it from the upstream request!

With path style:
```
http://localhost:8080/https/api.com/users?a=1&b=2
```
The proxied base URL is a valid URL base. Subpaths and query parameters append naturally and remain intact.

### What NOT to Wrap

Do **not** wrap:
- `launchUrl` external browser links
- Static asset URLs (`/sqlite3.wasm`, `/drift_worker.js`, images in `assets/`)
- WebSockets (`ws://` / `wss://` are not supported)
- Same-origin endpoints already hosted on your app server

**Do** wrap every external HTTP request: file uploads (`http.MultipartRequest`), authentication and refresh token requests, and secondary third-party APIs.

---

## Server Options

| Setting | Flags | Env Var | Default |
|---|---|---|---|
| Port | `-p`, `--port` | `PORT` | `8080` |
| Web root | `-w`, `--web-root` | `WEB_ROOT` | none (proxy-only mode) |
| Bind host | `--host` | `HOST` | `localhost` |
| Allowlist | `-a`, `--allow` (repeatable, comma-separated) | `ALLOW_HOSTS` (comma-separated) | empty (all hosts allowed) |
| Timeout | `-t`, `--timeout` (seconds) | `TIMEOUT` | `30` |
| Help | `-h`, `--help` | | |

### Examples

```sh
# Custom port
flutter_cors_bypass --port 9000

# Restrict allowed upstream hosts (wildcards supported)
flutter_cors_bypass --allow api.example.com --allow *.example.org

# Environment variables
PORT=9000 WEB_ROOT=build/web flutter_cors_bypass
```

> [!CAUTION]
> If `--host` is set to a non-loopback interface (e.g. `0.0.0.0` or `192.168.1.50`), your proxy becomes accessible to other machines on your local network. This is useful for testing mobile devices on your Wi-Fi, but you should **always** pair it with `--allow` to limit exposed upstream targets.

---

## What the Proxy Does

- **Request header filtering:** Strips `host`, `origin`, `referer`, `content-length`, `connection`, `accept-encoding`, and all `sec-fetch-*` headers before relaying.
  - Stripping `host` allows the client to automatically set the target's actual host name.
  - Stripping `accept-encoding` prevents browsers from advertising unsupported compression formats (`br`, `zstd`), allowing Dart to decompress `gzip` transparently.
  - Preserves `Authorization`, `Content-Type`, `Accept`, `Cookie`, and custom headers like `X-Api-Key`.
- **Response header filtering:** Strips `content-encoding`, `content-length`, `transfer-encoding`, `connection`, and upstream `access-control-*` headers.
- **Byte streaming:** Streams bodies directly without string conversion, ensuring binary payloads (images, PDFs, binary buffers) remain byte-for-byte identical.
- **Redirects:** Follows HTTP redirects upstream (`followRedirects = true`) so browsers never encounter cross-origin `Location` redirects.
- **CORS handling:**
  - Reflects the incoming `Origin` header (does not use `*`).
  - Preflight `OPTIONS` requests receive immediate `204 No Content` responses with CORS headers.
  - Exposes upstream response headers via `Access-Control-Expose-Headers`.
- **Timeouts & errors:**
  - Returns **504** on timeouts (`Upstream timed out after Ns`).
  - Returns **502** on DNS or connection errors (`Upstream request failed: <reason>`).
  - Returns **400** on invalid URLs, empty hosts, or self-loops (pointing back to the proxy).
  - Returns **403** when target host is blocked by `--allow`.
  - Attaches full CORS headers to all 4xx and 5xx responses so the browser displays real errors instead of generic CORS blocks.
- **Logging:** Logs one line per proxied request in the format: `METHOD <target URL> -> <status> (<duration> ms)`. Headers and authentication secrets are **never** logged.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| CORS error, and DevTools shows the request going straight to the real API URL | The call isn't wrapped with `apiUri()`/`proxied()`, or the app was built without `PROXY_BASE` | Wrap it. Stop and restart `flutter run` with `--dart-define=PROXY_BASE=http://localhost:8080` |
| `ClientException: Failed to fetch`, and the URL is `http://localhost:8080/...` | The proxy isn't running | Start `flutter_cors_bypass` in another terminal and retry. No app restart needed |
| `Failed to bind web development server ... port = 5000` | macOS AirPlay Receiver (or another process) owns the port | `--web-port 5050`, or check with `lsof -nP -iTCP:5000 -sTCP:LISTEN` |
| Proxy prints `Could not listen on localhost:8080` | Another proxy instance or app is on 8080 | Stop it, or `--port 8081` with `PROXY_BASE=http://localhost:8081` |
| Browser shows `Not found. No WEB_ROOT is configured...` | You opened `localhost:8080` while using workflow B | Open the `flutter run` port instead. For workflow A, add `--web-root` |
| Workflow A: CORS errors, and requests go to the real API | Built with plain `flutter build web` (release), which bypasses the proxy by design | Rebuild with `flutter build web --profile` |
| Requests go to `localhost:<flutter port>/proxy?...` or `/https/...` and return 404 | App built without `PROXY_BASE`, so the helper made relative URLs | Restart `flutter run` with the `--dart-define` |
| Proxy logs `-> 403` | Host isn't in `--allow` | Add it to the allowlist |
| Proxy logs `-> 502` / `-> 504` | Upstream unreachable / slower than the timeout | Check network or VPN, try the URL with `curl`, raise `--timeout` |
| Proxy logs `-> 4xx/5xx` from the API | That's the API's own answer, passed through | Debug as a normal API error |
| Query parameters missing upstream when wrapping a base URL | Using `apiUri(base)` + appended path (query style) | Use `proxied(base)` for base URLs |

### Health Checks via `curl`

Verify both URL styles directly from the command line:

**Query style:**
```sh
curl -i -H "Origin: http://localhost:5050" "http://localhost:8080/proxy?url=https%3A%2F%2Fhttpbin.org%2Fget%3Fa%3D1%26b%3D2"
# Expected: HTTP/1.1 200 OK and access-control-allow-origin: http://localhost:5050
```

**Path style:**
```sh
curl -i -H "Origin: http://localhost:5050" "http://localhost:8080/https/httpbin.org/get?a=1&b=2"
# Expected: HTTP/1.1 200 OK and access-control-allow-origin: http://localhost:5050
```

---

## Setup Checklist

Before reporting issues, verify:
- \[ \] Helper `api_url.dart` copied to `lib/core/api_url.dart`.
- \[ \] API base URLs wrapped with `proxied()` and full URLs with `apiUri()`.
- \[ \] Proxy running on `localhost:8080`.
- \[ \] Flutter app launched with `--dart-define=PROXY_BASE=http://localhost:8080`.
- \[ \] `flutter run` completely stopped and restarted after modifying `--dart-define`.
- \[ \] Flutter web port is free (e.g. port 5050, avoiding macOS AirPlay on port 5000).
- \[ \] Build is non-release (e.g. debug or `--profile`).
- \[ \] Browser DevTools confirms requests hit `http://localhost:8080/...`.
- \[ \] Proxy terminal displays corresponding request logs.

---

## Development

```sh
# Install dependencies
dart pub get

# Static analysis
dart analyze

# Run tests
dart test

# Run tests with code coverage
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib
```

---

## Contributing

`flutter_cors_bypass` is open source, and contributions are warmly welcome! Whether you are reporting an issue, proposing enhancements, or submitting a pull request, please review our [Contributing Guidelines](CONTRIBUTING.md) (or [contributors_guideline.md](contributors_guideline.md)) to get started.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
