import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diag.dart';
import '../theme.dart';

/// 诊断日志页。
///
/// 存在的理由：iPhone 上是侧载安装的，出了登录问题既没有控制台也没有 Mac，
/// 唯一的办法是让 app 把过程记下来、显示出来、能复制走。
///
/// 顶部的「复制全部」是为了让用户直接把文本贴进聊天窗口，
/// 不用截图、不用连电脑。
class DiagScreen extends StatefulWidget {
  const DiagScreen({super.key});

  @override
  State<DiagScreen> createState() => _DiagScreenState();
}

class _DiagScreenState extends State<DiagScreen> {
  String _note = '';

  Future<void> _copyAll() async {
    final text = diagDump(
      header: '复旦大学 eLearning 看板 · 诊断日志\n'
          '（把这个整段发给开发者即可；里面不含密码）',
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _note = '已复制 ${diagEntries.length} 条到剪贴板');
  }

  void _clear() {
    setState(() {
      diagClear();
      _note = '已清空。重新复现一次问题，日志会重新记录。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final entries = diagEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined, size: 21),
            onPressed: entries.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline, size: 21),
            onPressed: entries.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: p.accent.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登录出问题时怎么办',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  '先点右上角清空，回到登录页重新输一次学号密码复现问题，'
                  '再回来点「复制全部」把内容发出来。',
                  style: TextStyle(fontSize: 11.5, color: p.textDim, height: 1.6),
                ),
                if (_note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_note, style: TextStyle(fontSize: 11.5, color: p.accent)),
                ],
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      '还没有记录。\n去登录一次，这里就会有内容。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p.muted, height: 1.8),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final isError = e.message.contains('✗');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          e.format(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.5,
                            color: isError ? p.bad : p.textDim,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 登录页底部的一行小入口。
class DiagEntryLink extends StatelessWidget {
  const DiagEntryLink({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DiagScreen()),
        );
      },
      icon: Icon(Icons.terminal, size: 15, color: dark ? p.muted : p.muted),
      label: Text(
        diagEmpty ? '登录不上？查看诊断日志' : '诊断日志（${diagEntries.length} 条）',
        style: TextStyle(fontSize: 12, color: p.muted),
      ),
    );
  }
}
