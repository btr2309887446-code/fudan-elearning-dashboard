/// 应用内诊断日志。
///
/// 为什么需要它：iPhone 上是侧载安装的（没有 Mac、没法 `flutter run`、
/// 也没装 libimobiledevice），出问题时**看不到任何控制台输出**。
/// 所以把登录链与 HTTP 请求的关键步骤记在内存里，在手机上直接看、直接复制。
///
/// 两条硬规矩：
///  1. **绝不记录密码**；ticket、cookie 只留前几位，够定位就行；
///  2. 环形缓冲，最多 [maxLines] 行，不会把内存撑爆。
library;

/// 一条日志。
class DiagEntry {
  DiagEntry(this.at, this.tag, this.message);

  final DateTime at;
  final String tag;
  final String message;

  String format() {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    final ms = at.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms [$tag] $message';
  }
}

const int maxLines = 500;

final List<DiagEntry> _entries = [];

/// 记一条。tag 用短的英文/中文词，方便 grep。
void diag(String tag, String message) {
  _entries.add(DiagEntry(DateTime.now(), tag, message));
  if (_entries.length > maxLines) {
    _entries.removeRange(0, _entries.length - maxLines);
  }
}

/// 记一条错误，带上类型名——`describeCanvasError` 有时会把类型吃掉。
void diagError(String tag, Object error, [StackTrace? stack]) {
  final type = error.runtimeType.toString();
  diag(tag, '✗ $type: $error');
  if (stack != null) {
    final first = stack.toString().split('\n').take(3).join(' | ');
    diag(tag, '  栈: $first');
  }
}

List<DiagEntry> get diagEntries => List.unmodifiable(_entries);

bool get diagEmpty => _entries.isEmpty;

void diagClear() => _entries.clear();

/// 给用户复制走的纯文本。
String diagDump({String? header}) {
  final buf = StringBuffer();
  if (header != null) buf.writeln(header);
  buf.writeln('共 ${_entries.length} 条');
  buf.writeln('─' * 40);
  for (final e in _entries) {
    buf.writeln(e.format());
  }
  return buf.toString();
}

/// 只留前 [keep] 位，用来记录 ticket / cookie 这类敏感值。
///
/// 定位问题只需要看「有没有拿到、大概长什么样」，不需要完整值。
String redact(String? value, {int keep = 8}) {
  if (value == null) return '(无)';
  if (value.isEmpty) return '(空)';
  if (value.length <= keep) return '$value…(${value.length} 字符)';
  return '${value.substring(0, keep)}…(${value.length} 字符)';
}
