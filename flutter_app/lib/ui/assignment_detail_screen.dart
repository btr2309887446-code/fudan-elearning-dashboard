/// 作业详情。
///
/// 与桌面端的详情浮层对应：完整说明、提交状态、成绩，
/// 外加一段 100 字以内简介（配了大模型就由模型压缩，否则截取原文）。
///
/// 说明按纯文本渲染并保留段落，不用 WebView 塞远端 HTML——
/// 富文本排版与附件留一个「在浏览器中打开」的出口就够了。
library;

import 'package:flutter/material.dart';

import '../core/summary.dart';
import '../core/types.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'format.dart';
import 'widgets.dart';

class AssignmentDetailScreen extends StatefulWidget {
  const AssignmentDetailScreen({super.key, required this.state, required this.row});

  final AppState state;
  final AssignmentRow row;

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  bool _loading = true;
  String _description = '';
  String _summary = '';
  String _source = 'fallback';
  String? _summaryError;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    final paragraphs = plain.split('\n').where((l) => l.trim().isNotEmpty).toList();

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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text, height: 1.35),
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
                      InfoChip(rel.text, tone: rel.tone == DueTone.overdue ? p.bad : p.warn),
                    if (row.pointsPossible != null)
                      InfoChip('满分 ${formatScoreCompact(row.pointsPossible)}'),
                    if (row.score != null)
                      InfoChip(
                        '得分 ${formatScoreCompact(row.score)}'
                        '${row.percent != null ? '（${row.percent!.round()}%）' : ''}',
                        tone: p.good,
                      ),
                    if (row.submittedAt != null) InfoChip('提交于 ${formatDate(row.submittedAt)}'),
                    if (row.gradedAt != null) InfoChip('批改于 ${formatDate(row.gradedAt)}'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // --- 简介 ---
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
                    Icon(_source == 'llm' ? Icons.auto_awesome : Icons.article_outlined,
                        size: 15, color: p.accent),
                    const SizedBox(width: 6),
                    Text(
                      _source == 'llm' ? 'AI 摘要' : '原文截取',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accent),
                    ),
                    const SizedBox(width: 8),
                    if (_source == 'fallback' && _summaryError == null)
                      Expanded(
                        child: Text(
                          '未接入大模型，直接取描述前 100 字',
                          style: TextStyle(fontSize: 11.5, color: p.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _loading ? '正在生成简介…' : (_summary.isNotEmpty ? _summary : '这条作业没有文字说明。'),
                  style: TextStyle(fontSize: 14, height: 1.6, color: p.text),
                ),
                if (_summaryError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$_summaryError（已降级为截取原文）',
                    style: TextStyle(fontSize: 11.5, color: p.warn),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          SectionHeader(
            '作业说明',
            trailing: (!_loading && plain.isNotEmpty)
                ? Text('${plain.length} 字', style: TextStyle(fontSize: 12, color: p.muted))
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
                        style: TextStyle(fontSize: 13.5, height: 1.75, color: p.textDim),
                      ),
                    ),
                ],
              ),
            ),

          if (_loadError != null) ...[
            const SizedBox(height: 12),
            Text(
              '完整说明获取失败（$_loadError），上面显示的是本地缓存的摘录。',
              style: TextStyle(fontSize: 12.5, color: p.warn),
            ),
          ],

          if (row.htmlUrl != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => widget.state.openUrl(row.htmlUrl!),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: const Text('在浏览器中打开（富文本、附件与提交入口）'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ],
        ],
      ),
    );
  }
}