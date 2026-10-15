# flutter_cors_bypass Example

This directory contains examples for using `flutter_cors_bypass`:

1. **`flutter_cors_bypass_example.dart`**: A pure Dart example demonstrating starting the proxy programmatically, generating path-style and query-style proxied URLs, and sending requests.
2. **`api_url.dart`**: The Flutter helper file that developers copy into their Flutter Web projects at `lib/core/api_url.dart`.

---

## Running the Dart Example

To run the Dart example:

```sh
dart run example/flutter_cors_bypass_example.dart
```

---

## Flutter Web Integration Example

In your Flutter project:

1. Copy [`api_url.dart`](api_url.dart) to `lib/core/api_url.dart`.
2. Wrap your base URLs or full URLs:

```dart
import 'package:<your_app>/core/api_url.dart';

// Wrapping a base URL (e.g. Dio / Chopper / Retrofit / http):
final baseUrl = proxied('https://api.example.com');
final res = await http.get(Uri.parse('$baseUrl/users?page=1'));

// Wrapping a full URL:
final res2 = await http.get(apiUri('https://api.example.com/users?page=1'));
```

3. Start the proxy in your terminal:
```sh
flutter_cors_bypass
```

4. Run your Flutter Web application in debug mode:
```sh
flutter run -d chrome --web-port 5050 --dart-define=PROXY_BASE=http://localhost:8080
```
