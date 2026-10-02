/// 作业详情。
///
/// 与桌面端的详情浮层对应：完整说明、提交状态、成绩，
/// 外加一段 100 字以内简介（配了大模型就由模型压缩，否则截取原文）。
///
/// 说明按纯文本渲染并保留段落，不用 WebView 塞远端 HTML——
/// 富文本排版与附件留一个「在浏览器中打开」的出口就够了。
library;

import 'package:flutter/material.dart';

import '../core/endpoints.dart';
import '../core/summary.dart';
import '../core/types.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../core/ignored.dart';
import 'format.dart';
import 'widgets.dart';

class AssignmentDetailScreen extends StatefulWidget {
  const AssignmentDetailScreen(
      {super.key, required this.state, required this.row});

  final AppState state;
  final AssignmentRow row;

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  bool _loading = true;
  String _description = '';
  String _summary = '';
  String _source = 'none';
  String? _summaryError;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final row = widget.row;
    final r = await widget.state.loadAssignmentDetail(
      courseId: row.courseId,
      assignmentId: row.id,
      name: row.name,
      excerptHint: row.descriptionExcerpt,
    );
    if (!mounted) return;
    setState(() {
      _description = r.description;
      _summary = r.summary;
      _source = r.source;
      _summaryError = r.error;
      _loadError = r.descriptionError;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final row = widget.row;
    final rel = dueRelative(row.dueAt, isCompleted(row));
    final state = submissionState(row);
    final plain = htmlToPlainText(_description);
    final paragraphs =
        plain.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final links = extractHtmlLinks(_description).where((link) {
      final uri = Uri.tryParse(link.url);
      return uri != null &&
          (uri.scheme.isEmpty || uri.scheme == 'http' || uri.scheme == 'https');
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('作业详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                      height: 1.35),
                ),
                const SizedBox(height: 5),
                Text(
                  '${row.courseName}${row.groupName.isNotEmpty ? ' · ${row.groupName}' : ''}',
                  style: TextStyle(fontSize: 12.5, color: p.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    StatusTag(label: state.label, tone: state.tone),
                    InfoChip(formatDate(row.dueAt)),
                    if (rel.text.isNotEmpty)
                      InfoChip(rel.text,
                          tone: rel.tone == DueTone.overdue ? p.bad : p.warn),
                    if (row.pointsPossible != null)
                      InfoChip('满分 ${formatScoreCompact(row.pointsPossible)}'),
                    if (row.score != null)
                      InfoChip(
                        '得分 ${formatScoreCompact(row.score)}'
                        '${row.percent != null ? '（${row.percent!.round()}%）' : ''}',
                        tone: p.good,
                      ),
                    if (row.submittedAt != null)
                      InfoChip('提交于 ${formatDate(row.submittedAt)}'),
                    if (row.gradedAt != null)
                      InfoChip('批改于 ${formatDate(row.gradedAt)}'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // --- 简介 ---
          // 只有真的走了大模型才显示这一块。
          // 没接大模型时截取前 100 字，和下面「作业说明」的原文是同一份内容，
          // 再摆一个框只是重复；正文本来就短的（source='none'）同理。
          if (_source == 'llm') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.10),
                border: Border.all(color: p.accent.withValues(alpha: 0.28)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 15, color: p.accent),
                      const SizedBox(width: 6),
                      Text(
                        'AI 摘要',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loading
                        ? '正在生成简介…'
                        : (_summary.isNotEmpty ? _summary : '这条作业没有文字说明。'),
                    style: TextStyle(fontSize: 14, height: 1.6, color: p.text),
                  ),
                ],
              ),
            ),
          ],

          // 配了大模型但这次没成功：摘要框不出现，但得说一声，
          // 否则用户只会觉得「怎么没摘要」而不知道是调用失败了。
          if (_source != 'llm' && _summaryError != null) ...[
            Text(
              '$_summaryError（本次未生成摘要，下面是原文）',
              style: TextStyle(fontSize: 12, color: p.warn),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 18),

          SectionHeader(
            '作业说明',
            trailing: (!_loading && plain.isNotEmpty)
                ? Text('${plain.length} 字',
                    style: TextStyle(fontSize: 12, color: p.muted))
                : null,
          ),
          const SizedBox(height: 8),

          if (_loading)
            Text('正在读取作业说明…', style: TextStyle(fontSize: 13, color: p.muted))
          else if (paragraphs.isEmpty)
            Text('这条作业没有附说明。', style: TextStyle(fontSize: 13, color: p.muted))
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Text(
                        line,
                        style: TextStyle(
                            fontSize: 13.5, height: 1.75, color: p.textDim),
                      ),
                    ),
                ],
              ),
            ),

          if (_loadError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: p.warn.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.warn.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '完整说明获取失败（$_loadError），当前显示本地摘录。',
                      style: TextStyle(fontSize: 12.5, color: p.warn),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ],

          if (links.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionHeader(
              '说明中的链接',
              icon: Icons.link,
              trailing: Text(
                '${links.length} 个',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < links.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: p.border),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.link, size: 18, color: p.accent),
                      title: Text(
                        links[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text, fontSize: 13),
                      ),
                      subtitle: Text(
                        links[i].url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 10.5),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 17),
                      onTap: () {
                        final uri = Uri.parse(canvasBase).resolve(links[i].url);
                        if (uri.scheme == 'http' || uri.scheme == 'https') {
                          widget.state.openUrl(uri.toString());
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          SectionHeader(
            '提交时间线',
            icon: Icons.history,
            iconColor: p.accent,
          ),
          AppCard(
            child: Column(
              children: [
                _TimelineEntry(
                  icon: Icons.event_available,
                  title: '截止时间',
                  value: formatDate(row.dueAt),
                  color: rel.tone == DueTone.overdue ? p.bad : p.muted,
                ),
                if (row.submittedAt != null)
                  _TimelineEntry(
                    icon: Icons.upload_file,
                    title: row.late ? '已提交（迟交）' : '已提交',
                    value: formatDate(row.submittedAt),
                    color: row.late ? p.warn : p.accent,
                  ),
                if (row.gradedAt != null || row.score != null)
                  _TimelineEntry(
                    icon: Icons.grading,
                    title: '已批改',
                    value: row.gradedAt == null
                        ? '已有成绩：${formatScoreCompact(row.score)}'
                        : '${formatDate(row.gradedAt)} · ${formatScoreCompact(row.score)}',
                    color: p.good,
                  ),
              ],
            ),
          ),

          // 有些作业本质上不用交（签到、选做、老师明说不用交的），
          // 但 Canvas 仍算它们 unsubmitted，于是永远挂在未交清单里。
          // 这里让用户手动摘掉——只影响显示，不改得分。
          AnimatedBuilder(
            animation: widget.state,
            builder: (context, _) {
              final ignored = isIgnored(
                widget.state.ignoredSet,
                row.courseId,
                row.id,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => widget.state
                        .toggleIgnoredAssignment(row.courseId, row.id),
                    icon: Icon(
                        ignored ? Icons.check_circle : Icons.inbox_outlined,
                        size: 17),
                    label: Text(ignored ? '已标记无需提交' : '标记为无需提交'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: ignored ? p.accent : p.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ignored
                        ? '已从未交清单与缺交统计里移除。再点一次可恢复。'
                        : '签到、选做、老师明说不用交的作业可以标记，标记后不再出现在未交清单里。',
                    style:
                        TextStyle(fontSize: 11.5, color: p.muted, height: 1.6),
                  ),
                ],
              );
            },
          ),

          if (row.htmlUrl != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => widget.state.openUrl(row.htmlUrl!),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('在浏览器中打开（富文本、附件与提交入口）'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(title, style: TextStyle(color: p.textDim, fontSize: 12.5)),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
