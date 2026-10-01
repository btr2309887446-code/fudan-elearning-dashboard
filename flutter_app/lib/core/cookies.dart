/// 自实现的 Cookie 容器（RFC 6265 的实用子集）。
///
/// 登录链跨越 `id.fudan.edu.cn` 和 `elearning.fudan.edu.cn` 两个域，
/// 必须精确控制哪个 Cookie 发往哪里，所以不依赖任何现成的 cookie 库。

library;

import 'dart:convert';

class Cookie {
  Cookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expires,
    this.secure = false,
    this.httpOnly = false,
    this.hostOnly = true,
  });

  final String name;
  final String value;

  /// 小写主机名，不含前导点。
  final String domain;
  final String path;

  /// 过期时刻；null 表示会话 Cookie。
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;

  /// Set-Cookie 未带 Domain 属性时为 true，只对精确主机生效。
  final bool hostOnly;

  String get key => '$domain\t$path\t$name';

  bool get isExpired => expires != null && !expires!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expires': expires?.toIso8601String(),
        'secure': secure,
        'httpOnly': httpOnly,
        'hostOnly': hostOnly,
      };

  factory Cookie.fromJson(Map<String, dynamic> json) => Cookie(
        name: (json['name'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
        domain: (json['domain'] as String?) ?? '',
        path: (json['path'] as String?) ?? '/',
        expires: json['expires'] is String ? DateTime.tryParse(json['expires'] as String) : null,
        secure: json['secure'] == true,
        httpOnly: json['httpOnly'] == true,
        hostOnly: json['hostOnly'] != false,
      );
}

class CookieJar {
  final Map<String, Cookie> _cookies = {};

  static String _normaliseDomain(String raw) =>
      raw.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

  static String _defaultPath(String requestPath) {
    if (!requestPath.startsWith('/')) return '/';
    final i = requestPath.lastIndexOf('/');
    return i <= 0 ? '/' : requestPath.substring(0, i);
  }

  static bool _domainMatches(Cookie c, String host) {
    final h = host.toLowerCase();
    if (c.hostOnly) return h == c.domain;
    return h == c.domain || h.endsWith('.${c.domain}');
  }

  static bool _pathMatches(String cookiePath, String requestPath) {
    if (requestPath == cookiePath) return true;
    if (!requestPath.startsWith(cookiePath)) return false;
    if (cookiePath.endsWith('/')) return true;
    return requestPath.length > cookiePath.length &&
        requestPath[cookiePath.length] == '/';
  }

  /// 解析并保存一次响应里的全部 Set-Cookie。
  void setFromResponse(String url, Iterable<String> setCookieHeaders) {
    final uri = Uri.parse(url);
    for (final header in setCookieHeaders) {
      _setOne(uri, header);
    }
  }

  void _setOne(Uri uri, String header) {
    final segments = header.split(';');
    if (segments.isEmpty) return;
    final first = segments.removeAt(0);
    final eq = first.indexOf('=');
    if (eq < 0) return;

    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (name.isEmpty) return;

    var domain = _normaliseDomain(uri.host);
    var hostOnly = true;
    var path = _defaultPath(uri.path.isEmpty ? '/' : uri.path);
    DateTime? expires;
    var secure = false;
    var httpOnly = false;

    for (final seg in segments) {
      final i = seg.indexOf('=');
      final attr = (i < 0 ? seg : seg.substring(0, i)).trim().toLowerCase();
      final val = i < 0 ? '' : seg.substring(i + 1).trim();
      switch (attr) {
        case 'domain':
          if (val.isNotEmpty) {
            domain = _normaliseDomain(val);
            hostOnly = false;
          }
          break;
        case 'path':
          if (val.startsWith('/')) path = val;
          break;
        case 'max-age':
          final secs = int.tryParse(val);
          if (secs != null) expires = DateTime.now().add(Duration(seconds: secs));
          break;
        case 'expires':
          final t = _parseHttpDate(val);
          if (t != null) expires = t;
          break;
        case 'secure':
          secure = true;
          break;
        case 'httponly':
          httpOnly = true;
          break;
        default:
          break;
      }
    }

    final cookie = Cookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: expires,
      secure: secure,
      httpOnly: httpOnly,
      hostOnly: hostOnly,
    );

    if (cookie.isExpired) {
      _cookies.remove(cookie.key);
    } else {
      _cookies[cookie.key] = cookie;
    }
  }

  /// 解析 RFC 1123 日期（Set-Cookie 的 Expires 格式）。
  static DateTime? _parseHttpDate(String value) {
    // "Wed, 09 Jun 2021 10:18:14 GMT"
    final m = RegExp(r'^[A-Za-z]{3},\s*(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(value.trim());
    if (m == null) return null;
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  /// 构造请求用的 Cookie 头；无匹配时返回 null。
  String? cookieHeader(String url) {
    final uri = Uri.parse(url);
    final matches = <Cookie>[];

    for (final entry in _cookies.entries.toList()) {
      final c = entry.value;
      if (c.isExpired) {
        _cookies.remove(entry.key);
        continue;
      }
      if (c.secure && uri.scheme != 'https') continue;
      if (!_domainMatches(c, uri.host)) continue;
      if (!_pathMatches(c.path, uri.path.isEmpty ? '/' : uri.path)) continue;
      matches.add(c);
    }
    if (matches.isEmpty) return null;

    // RFC 6265 5.4：路径更长的排前面。
    matches.sort((a, b) => b.path.length.compareTo(a.path.length));
    return matches.map((c) => '${c.name}=${c.value}').join('; ');
  }

  List<String> names(String url) {
    final header = cookieHeader(url);
    if (header == null) return const [];
    return header.split('; ').map((p) => p.substring(0, p.indexOf('='))).toList();
  }

  bool has(String name) => _cookies.values.any((c) => c.name == name);

  void deleteByName(String name) {
    _cookies.removeWhere((_, c) => c.name == name);
  }

  void clear() => _cookies.clear();

  List<Cookie> all() => _cookies.values.toList();

  String toJsonString() => jsonEncode(all().map((c) => c.toJson()).toList());

  static CookieJar fromJsonString(String source) {
    final jar = CookieJar();
    try {
      final list = jsonDecode(source);
      if (list is List) {
        for (final raw in list) {
          if (raw is Map<String, dynamic>) {
            final c = Cookie.fromJson(raw);
            if (c.name.isNotEmpty && c.domain.isNotEmpty) jar._cookies[c.key] = c;
          }
        }
      }
    } catch (_) {
      // 损坏的缓存按空容器处理。
    }
    return jar;
  }
}
