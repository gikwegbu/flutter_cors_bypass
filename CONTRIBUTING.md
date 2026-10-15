# Contributing to flutter_cors_bypass

First off, thank you for considering contributing to `flutter_cors_bypass`! 🎉

This is an open-source project designed to make local Flutter Web development painless when dealing with CORS restrictions. Contributions of all kinds are warmly welcomed—whether that's reporting bugs, improving documentation, submitting feature proposals, or opening pull requests.

---

## Code of Conduct

Please help us foster an open, welcoming, and inclusive environment. Be respectful, constructive, and empathetic in all interactions across issues, discussions, and pull requests.

---

## How Can I Contribute?

### 1. Reporting Bugs

Before creating an issue, please check existing issues to ensure the bug hasn't already been reported.

When opening a new issue, please include:
- A clear, descriptive title.
- Steps to reproduce the problem.
- Expected vs. actual behavior.
- Relevant log output (make sure to redact sensitive tokens, passwords, or private URLs).
- Your Dart and Flutter environment (`dart --version`, `flutter doctor -v`, OS/browser version).

### 2. Suggesting Enhancements

Feature requests and architectural proposals are welcome! Please open an issue with:
- A concise summary of the proposed feature.
- The use case or problem it solves.
- Any potential alternatives or trade-offs you have considered.

---

## Development Workflow

### Prerequisites

- [Dart SDK](https://dart.dev/get-dart) `^3.12.0` (included with recent Flutter SDK installations).
- Git.

> [!NOTE]
> `flutter_cors_bypass` is a **pure Dart package** (not a Flutter plugin). The server binary and tests run with standard `dart` commands without requiring the Flutter engine.

### Setup

1. Fork the repository on GitHub.
2. Clone your fork locally:
   ```sh
   git clone https://github.com/<your-username>/flutter_cors_bypass.git
   cd flutter_cors_bypass
   ```
3. Install dependencies:
   ```sh
   dart pub get
   ```

### Code Style & Standards

- **Formatting**: Always format your Dart code with:
  ```sh
  dart format .
  ```
  Ensure `dart format --output=none --set-exit-if-changed .` passes with zero changes.
- **Analysis**: Code must pass strict static analysis without warnings or infos:
  ```sh
  dart analyze
  ```
- **Lint rules**: Adhere to `package:lints/recommended.yaml`.

### Running Tests

All unit and integration tests are designed to run completely offline without external internet dependencies.

- Run the full test suite:
  ```sh
  dart test
  ```
- Run tests with code coverage (target is $\ge 90\%$ line coverage on `lib/`):
  ```sh
  dart test --coverage=coverage
  dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib
  ```

### Key Architectural Guidelines

When contributing code, please keep in mind:
1. **Pure Dart Library**: Do not add dependencies on `flutter` or Flutter-specific packages to `pubspec.yaml`. The client helper (`example/api_url.dart`) is intended to be copied into developer Flutter apps, not imported from `lib/`.
2. **Security & Privacy**:
   - `flutter_cors_bypass` must always default to local loopback addresses (`localhost`).
   - Never log sensitive request headers (e.g. `Authorization`, `Cookie`, or custom tokens).
3. **Byte Streaming**: Response bodies must be streamed as raw bytes to avoid corrupting binary data (e.g. images, PDFs).
4. **CORS Integrity**: Ensure error responses (4xx/5xx) and preflight requests always carry proper CORS headers.

---

## Submitting Pull Requests

1. Create a feature branch from `main`:
   ```sh
   git checkout -b feature/my-new-feature
   ```
2. Write clean, readable code and accompany any new functionality or bug fixes with tests in `test/`.
3. If applicable, update `README.md` and document your changes under `CHANGELOG.md`.
4. Verify your branch passes all checks:
   ```sh
   dart format --output=none --set-exit-if-changed .
   dart analyze
   dart test
   dart pub publish --dry-run
   ```
5. Commit your changes with clear, descriptive commit messages.
6. Push to your fork and submit a Pull Request targeting `main`.

Thank you for contributing! ❤️
