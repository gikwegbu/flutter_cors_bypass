/// Host allowlist matcher for target proxy URLs.
class Allowlist {
  final List<_AllowRule> _rules;

  /// Creates an [Allowlist] from a list of host pattern strings.
  Allowlist(Iterable<String> patterns)
    : _rules = patterns
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map(_AllowRule.parse)
          .toList();

  /// Whether the allowlist is empty (allows all hosts).
  bool get isEmpty => _rules.isEmpty;

  /// Whether the allowlist is not empty.
  bool get isNotEmpty => _rules.isNotEmpty;

  /// Returns whether the given [uri] is allowed.
  bool isAllowed(Uri uri) {
    if (isEmpty) return true;
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return isHostAllowed(host, port: port);
  }

  /// Returns whether the given [host] and optional [port] is allowed.
  bool isHostAllowed(String host, {int? port}) {
    if (isEmpty) return true;
    final normalizedHost = host.toLowerCase();
    for (final rule in _rules) {
      if (rule.matches(normalizedHost, port)) {
        return true;
      }
    }
    return false;
  }
}

class _AllowRule {
  final String hostPattern;
  final int? port;
  final bool isWildcard;

  _AllowRule({
    required this.hostPattern,
    required this.port,
    required this.isWildcard,
  });

  factory _AllowRule.parse(String entry) {
    final lower = entry.toLowerCase();
    final colonIdx = lower.lastIndexOf(':');
    if (colonIdx != -1) {
      final hostPart = lower.substring(0, colonIdx);
      final portPart = int.tryParse(lower.substring(colonIdx + 1));
      if (portPart != null) {
        final isWild = hostPart.startsWith('*.');
        return _AllowRule(
          hostPattern: hostPart,
          port: portPart,
          isWildcard: isWild,
        );
      }
    }

    final isWild = lower.startsWith('*.');
    return _AllowRule(hostPattern: lower, port: null, isWildcard: isWild);
  }

  bool matches(String targetHost, int? targetPort) {
    if (port != null && targetPort != null && port != targetPort) {
      return false;
    }

    if (isWildcard) {
      final domain = hostPattern.substring(2); // e.g. "example.com"
      final suffix = '.$domain';
      return targetHost.endsWith(suffix) && targetHost != domain;
    }

    return targetHost == hostPattern;
  }
}
