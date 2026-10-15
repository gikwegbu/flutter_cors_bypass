## 1.0.1 - 2026-10-15

- Added canonical `example/flutter_cors_bypass_example.dart` showcasing programmatic server configuration, shelf handler mounting, and path/query proxy URL generation.
- Added `example/README.md` with usage instructions and Flutter Web integration snippets.
- Added open-source `CONTRIBUTING.md` guidelines (and `contributors_guideline.md`).
- Added Contributing section to `README.md`.
- Escaped task list markdown brackets in `README.md` to prevent dartdoc unresolved reference warnings.
- Achieved perfect 160/160 pub points on pub.dev's `pana` package analysis.

## 1.0.0 - 2026-10-15

### What Was Done
Initial release of **`flutter_cors_bypass`**, a standalone local CORS proxy and companion client helper designed for Flutter Web local development.

- **Dual-Mode Proxy Addressing**:
  - **Path Style** (`/<scheme>/<host[:port]>/<path>?<query>`): Allows wrapping API base URLs (e.g., `proxied('https://api.example.com')`) so that subpaths and query parameters can be naturally appended by API clients (such as Dio, Retrofit, Chopper, or `package:http`) without losing secondary query parameters.
  - **Query Style** (`/proxy?url=<url-encoded URL>`): Direct forwarding for full, one-off URLs (`apiUri('https://api.example.com/users?id=1')`).
- **Selective Header & Stream Management**:
  - Strips hop-by-hop and browser-specific headers before relaying upstream: `host` (allowing the HTTP client to set the upstream host correctly), `origin`, `referer`, `connection`, `content-length`, `accept-encoding` (preventing brotli/zstd compression issues and enabling transparent gzip), and `sec-fetch-*`.
  - Preserves client credentials and authentication: `Authorization`, `Cookie`, `Content-Type`, `Accept`, and custom API headers (e.g., `X-Api-Key`).
  - Strips conflicting upstream response headers: `content-encoding`, `content-length`, `transfer-encoding`, `connection`, and upstream `access-control-*` headers.
  - Passes request and response bodies as pure byte streams, guaranteeing byte-for-byte fidelity for binary responses (such as PNG/JPEG images, PDFs, and octet streams).
- **CORS Handling & Error Resilience**:
  - Dynamically reflects incoming `Origin` headers (never wildcard `*`).
  - Preflight `OPTIONS` requests receive immediate `204 No Content` responses without calling the upstream.
  - Upstream response headers are exposed to the browser via `Access-Control-Expose-Headers`.
  - Upstream timeouts (default 30s) yield `504 Gateway Timeout`.
  - Network and connection failures yield `502 Bad Gateway`.
  - All 4xx and 5xx responses carry complete CORS headers so browsers display actionable errors in DevTools rather than generic `ClientException: Failed to fetch`.
  - Self-loop detection prevents accidental proxy recursion.
- **Static File Serving & SPA Fallback**:
  - Optional `--web-root` / `WEB_ROOT` mode to serve pre-built Flutter web applications directly alongside proxy endpoints.
  - Built-in Single Page Application (SPA) routing fallback: deep links and routes without a file extension automatically fall back to serving `index.html`.
- **Host Security & Allowlist**:
  - Defaults to local loopback binding (`localhost`) for security.
  - Optional `--allow` / `ALLOW_HOSTS` configuration supporting exact matching and wildcards (e.g. `*.example.com`).
  - Emits security warnings if bound to an external network interface.
- **Client Helper (`example/api_url.dart`)**:
  - Pure Flutter utility providing `proxied()` and `apiUri()`.
  - Compile-time release safety: automatically disabled in release mode (`kReleaseMode`) and on native platforms (iOS, Android, macOS, Windows, Linux) where CORS is not enforced.

---

### How It Works

1. **Local Proxy Server**:
   During local development, `flutter_cors_bypass` runs locally (by default on `http://localhost:8080`).

2. **Request Interception & Rewriting**:
   In Flutter Web debug or profile mode, `proxied(baseUrl)` rewrites API requests to route through the local proxy:
   ```
   https://api.example.com/v1/users?page=1
   ──> http://localhost:8080/https/api.example.com/v1/users?page=1
   ```

3. **Server-to-Server Relaying**:
   The browser initiates a same-origin or localhost request to `flutter_cors_bypass`. The proxy forwards the request server-to-server to the upstream API. Since CORS is purely a browser-enforced security mechanism, the remote API server communicates directly with the proxy without CORS limitations.

4. **Response Delivery**:
   The proxy receives the upstream response and returns it to your browser with permissive `Access-Control-Allow-Origin` and `Access-Control-Allow-Methods` headers, satisfying browser security checks and eliminating CORS errors.

5. **Release Zero-Cost Abstraction**:
   In production release builds (`flutter build web`), `kReleaseMode` is `true`. The client helper conditionally evaluates `_shouldProxy` to `false` at compile-time, ensuring release builds communicate directly with the production API with zero proxy overhead.
