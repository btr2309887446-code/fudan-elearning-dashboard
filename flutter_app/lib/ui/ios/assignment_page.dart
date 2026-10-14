import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/endpoints.dart';
import '../../core/clock.dart';
import '../../core/summary.dart';
import '../../core/tasks.dart';
import '../../platform/calendar_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../format.dart';
import 'components.dart';

class IosAssignmentPage extends StatefulWidget {
  const IosAssignmentPage({
    super.key,
    required this.state,
    required this.task,
    required this.calendar,
    this.embedded = false,
  });
  final AppState state;
  final LearningTask task;
  final CalendarService calendar;
  final bool embedded;
  @override
  State<IosAssignmentPage> createState() => _IosAssignmentPageState();
}

class _IosAssignmentPageState extends State<IosAssignmentPage> {
  bool _loading = true;
  bool _exporting = false;
  String _description = '';
  String _summary = '';
  String? _descriptionError;
  String? _summaryError;
  bool _llm = false;
  LearningTask get task => widget.state.tasks.firstWhere(
    (task) => task.key == widget.task.key,
    orElse: () => widget.task,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = task.assignment;
    if (row == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _descriptionError = null;
    });
    final result = await widget.state.loadAssignmentDetail(
      courseId: row.courseId,
      assignmentId: row.id,
      name: row.name,
      excerptHint: row.descriptionExcerpt,
    );
    if (!mounted) return;
    setState(() {
      _description = htmlToPlainText(result.description);
      _summary = result.summary;
      _llm = result.source == 'llm';
      _descriptionError = result.descriptionError;
      _summaryError = result.error;
      _loading = false;
      _links = extractHtmlLinks(result.description).where((link) {
        final uri = Uri.tryParse(link.url);
        return uri != null &&
            (uri.scheme.isEmpty ||
                uri.scheme == 'https' ||
                uri.scheme == 'http');
      }).toList();
    });
  }

  List<({String label, String url})> _links = [];

  Future<void> _addCalendar() async {
    final current = task;
    final previous = widget.state.prefs.calendarExports[current.key];
    if (previous != null) {
      final changed = previous != current.dueAt?.toIso8601String();
      if (!await iosConfirm(
        context,
        changed ? '截止时间已变化' : '再次添加到日历？',
        changed
            ? '系统日历中的旧事件不会自动更新。请在日历中删除旧事件后重新添加。'
            : '此作业已添加过。再次保存会创建另一条日历事件。',
        confirm: '继续添加',
      )) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _exporting = true);
    final result = await widget.calendar.add(current);
    if (!mounted) return;
    if (result == CalendarResult.saved) {
      await widget.state.recordCalendarExport(current);
    }
    if (!mounted) return;
    setState(() => _exporting = false);
    if (result == CalendarResult.denied ||
        result == CalendarResult.unavailable) {
      await iosMessage(
        context,
        result == CalendarResult.denied
            ? '日历权限未开启。请在 iPhone 设置中允许访问日历后重试。'
            : '暂时无法打开系统日历，请稍后重试。',
      );
    } else if (result == CalendarResult.saved && widget.state.demo) {
      await iosMessage(context, '演示已完成，没有创建真实日历事件。');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final current = task;
      final p = context.palette;
      final row = current.assignment;
      final exported = widget.state.prefs.calendarExports[current.key];
      final changed =
          exported != null && exported != current.dueAt?.toIso8601String();
      final snapshot = widget.state.snapshot;
      final inCurrentTerm =
          snapshot != null &&
          snapshot.courses.any(
            (course) =>
                course.id == current.courseId &&
                course.termId == defaultTermId(snapshot),
          );
      final eligible =
          current.status == TaskStatus.pending &&
          current.dueAt != null &&
          inCurrentTerm;
      final reminderOn =
          widget.state.prefs.remindersEnabled &&
          !widget.state.prefs.mutedTasks.contains(current.key);
      return CupertinoPageScaffold(
        backgroundColor: p.background,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('作业详情'),
          automaticallyImplyLeading: !widget.embedded,
          backgroundColor: p.background,
          border: null,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  key: PageStorageKey('assignment:${current.key}'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Text(
                      current.title,
                      style: TextStyle(
                        fontSize: 24,
                        color: p.text,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current.courseName,
                      style: TextStyle(fontSize: 15, color: p.textDim),
                    ),
                    const SizedBox(height: 20),
                    IosGroup(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.status == TaskStatus.ignored
                                    ? '无需提交'
                                    : row == null
                                    ? '未提交'
                                    : submissionState(row).label,
                                style: TextStyle(
                                  fontSize: 17,
                                  color:
                                      current.status == TaskStatus.pending &&
                                          current.bucket(appNow()) ==
                                              TaskBucket.overdue
                                      ? p.bad
                                      : p.text,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                deadlineLabel(current, absolute: true),
                                style: TextStyle(
                                  fontSize: 20,
                                  color: p.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '北京时间',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: p.textDim,
                                ),
                              ),
                              if (row?.score != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    '得分 ${formatScoreCompact(row!.score)} / ${formatScoreCompact(row.pointsPossible)}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: p.text,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_llm) ...[
                      const IosSection('AI 摘要'),
                      _textPanel(context, _summary),
                    ],
                    const IosSection('作业说明'),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CupertinoActivityIndicator(),
                      )
                    else
                      _textPanel(
                        context,
                        _description.isEmpty
                            ? '这项作业没有文字说明，请前往 eLearning 查看附件或提交要求。'
                            : _description,
                      ),
                    if (_descriptionError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '完整说明暂时无法读取，当前显示缓存摘录。',
                        style: TextStyle(fontSize: 15, color: p.textDim),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          onPressed: _loading ? null : _load,
                          child: const Text('重试'),
                        ),
                      ),
                    ],
                    if (_summaryError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '摘要暂时不可用，请以作业原文为准。',
                          style: TextStyle(fontSize: 13, color: p.textDim),
                        ),
                      ),
                    if (_links.isNotEmpty) ...[
                      const IosSection('链接与附件入口'),
                      IosGroup(
                        children: [
                          for (final link in _links)
                            CupertinoButton(
                              padding: const EdgeInsets.all(16),
                              onPressed: () => widget.state.openUrl(
                                Uri.parse(
                                  canvasBase,
                                ).resolve(link.url).toString(),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  link.label,
                                  style: const TextStyle(fontSize: 17),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const IosSection('提醒与日历'),
                    IosGroup(
                      children: [
                        if (eligible)
                          CupertinoListTile(
                            title: const Text('此作业提醒'),
                            subtitle: Text(
                              widget.state.prefs.remindersEnabled
                                  ? '包含在截止日的汇总提醒中'
                                  : '开启后将允许当前学期作业提醒',
                            ),
                            trailing: CupertinoSwitch(
                              value: reminderOn,
                              onChanged: (value) async {
                                if (!widget.state.prefs.remindersEnabled &&
                                    value) {
                                  await widget.state.setRemindersEnabled(true);
                                  if (!widget.state.prefs.remindersEnabled) {
                                    if (context.mounted) {
                                      await iosMessage(
                                        context,
                                        widget.state.reminderNotice ??
                                            '提醒没有开启。',
                                      );
                                    }
                                    return;
                                  }
                                  if (widget.state.prefs.mutedTasks.contains(
                                    current.key,
                                  )) {
                                    await widget.state.toggleTaskReminder(
                                      current.key,
                                    );
                                  }
                                } else {
                                  await widget.state.toggleTaskReminder(
                                    current.key,
                                  );
                                }
                              },
                            ),
                          ),
                        CupertinoListTile(
                          title: Text(
                            _exporting
                                ? '正在打开日历…'
                                : changed
                                ? '截止已变化，重新添加'
                                : exported != null
                                ? '已添加到系统日历'
                                : '添加到系统日历',
                          ),
                          subtitle: const Text('单向添加，截止变化后需重新添加'),
                          leading: const Icon(
                            CupertinoIcons.calendar_badge_plus,
                          ),
                          trailing: const CupertinoListTileChevron(),
                          onTap: _exporting || current.dueAt == null
                              ? null
                              : _addCalendar,
                        ),
                        if (row != null)
                          CupertinoListTile(
                            title: const Text('无需提交'),
                            subtitle: const Text('从待交任务和提醒中移除，不影响成绩'),
                            trailing: CupertinoSwitch(
                              value: current.status == TaskStatus.ignored,
                              onChanged: (_) =>
                                  widget.state.toggleIgnoredAssignment(
                                    row.courseId,
                                    row.id,
                                  ),
                            ),
                          ),
                      ],
                    ),
                    if (current.dueAt == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '没有截止时间的作业无法安排提醒或导出日历。',
                          style: TextStyle(fontSize: 13, color: p.textDim),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.border)),
                ),
                child: CupertinoButton.filled(
                  onPressed: current.url == null
                      ? null
                      : () => widget.state.openUrl(current.url!),
                  child: const Text(
                    '前往 eLearning',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _textPanel(BuildContext context, String text) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: SelectableText(
      text,
      style: TextStyle(fontSize: 17, color: context.palette.text, height: 1.6),
    ),
  );
}
