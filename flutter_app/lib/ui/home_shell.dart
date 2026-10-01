import 'package:flutter/material.dart';

import '../core/types.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'assignment_detail_screen.dart';
import 'course_detail_screen.dart';
import 'overview_tab.dart';
import 'settings_screen.dart';
import 'timeline_tab.dart';

/// 学期筛选；`null` 表示匹配 Canvas 未给学期的课程。
typedef TermFilter = Object?; // 'all' | int | null

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  TermFilter _term = 'all';
  bool _termTouched = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    super.dispose();
  }

  /// 默认停在正在上的那个学期，但绝不覆盖用户自己的选择。
  void _onStateChanged() {
    final terms = state.snapshot?.terms ?? const <TermGroup>[];
    if (terms.isEmpty) return;
    if (_termTouched && _term != 'all' && terms.any((t) => t.id == _term)) return;

    final current = terms.firstWhere((t) => t.isCurrent, orElse: () => terms.first);
    if (_term != current.id) {
      // 在帧回调里改状态，避免在 build 期间触发重建。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _term = current.id);
      });
    }
  }

  List<CourseSummary> get _scopedCourses {
    final all = state.snapshot?.courses ?? const <CourseSummary>[];
    if (_term == 'all') return all;
    return all.where((c) => c.termId == _term).toList();
  }

  List<AssignmentRow> get _scopedAssignments {
    final all = state.snapshot?.assignments ?? const <AssignmentRow>[];
    if (_term == 'all') return all;
    final ids = _scopedCourses.map((c) => c.id).toSet();
    return all.where((a) => ids.contains(a.courseId)).toList();
  }

  String get _termName {
    if (_term == 'all') return '全部学期';
    final terms = state.snapshot?.terms ?? const <TermGroup>[];
    for (final t in terms) {
      if (t.id == _term) return t.name;
    }
    return '全部学期';
  }

  /// 打开作业详情。以前是直接跳浏览器，等于把人赶出应用。
  void _openAssignment(AssignmentRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssignmentDetailScreen(state: state, row: row),
      ),
    );
  }

  void _openCourse(int id) {
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          state: state,
          snapshot: snapshot,
          courseId: id,
          hideUnsubmitted: state.prefs.hideUnsubmitted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final snapshot = state.snapshot;
    final courses = _scopedCourses;
    final assignments = _scopedAssignments;

    // iPad 横屏与 macOS 窗口都够宽，底部导航会显得很远；
    // 760 以下是手机（竖屏），沿用底部导航。
    final wide = MediaQuery.sizeOf(context).width >= 760;
    // NavigationRail 的标签样式是显式 TextStyle，不会继承 textTheme 的字体，
    // 所以要主动把主题里的字族取出来带上（否则中文会渲染成占位方框）。
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? '学习总览' : '作业与截止'),
        actions: [
          if (state.busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 22),
            onPressed: state.busy ? null : () => state.refresh(force: true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 21),
            onSelected: (v) async {
              switch (v) {
                case 'hide':
                  await state.setHideUnsubmitted(!state.prefs.hideUnsubmitted);
                case 'settings':
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
                  );
                case 'logout':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('退出登录'),
                      content: const Text('将清除本机保存的登录状态与缓存数据。'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
                      ],
                    ),
                  );
                  if (ok == true) await state.logout();
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'hide',
                checked: state.prefs.hideUnsubmitted,
                child: const Text('忽略未提交的作业'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('设置（外观、首页板块）'),
              ),
              const PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
        ],
      ),
      body: snapshot == null
          ? Center(
              child: Text('还没有数据', style: TextStyle(color: p.muted, fontSize: 14)),
            )
          : Row(
              children: [
                if (wide) ...[
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: p.surface,
                    indicatorColor: p.accent.withValues(alpha: 0.14),
                    selectedIconTheme: IconThemeData(color: p.accent, size: 24),
                    unselectedIconTheme: IconThemeData(color: p.muted, size: 23),
                    selectedLabelTextStyle: TextStyle(
                      color: p.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: fontFamily,
                    ),
                    unselectedLabelTextStyle:
                        TextStyle(color: p.muted, fontSize: 12, fontFamily: fontFamily),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: Text('总览'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.checklist_outlined),
                        selectedIcon: Icon(Icons.checklist),
                        label: Text('作业与截止'),
                      ),
                    ],
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: p.border),
                ],
                Expanded(
                  child: Center(
                    // 窗口拉得很宽时不让卡片无限拉伸，否则一行只有几个字，很难读。
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        children: [
                          _TermSelector(
                            terms: snapshot.terms,
                            selected: _term,
                            totalCourses: snapshot.courses.length,
                            onSelect: (v) => setState(() {
                              _termTouched = true;
                              _term = v;
                            }),
                          ),
                          Expanded(
                            child: IndexedStack(
                              index: _tab,
                              children: [
                                OverviewTab(
                                  courses: courses,
                                  assignments: assignments,
                                  todo: snapshot.todo,
                                  termName: _termName,
                                  hideUnsubmitted: state.prefs.hideUnsubmitted,
                                  sections: state.prefs.dashboardSections,
                                  sectionOrder: state.effectiveSectionOrder(),
                                  ignoredSet: state.ignoredSet,
                                  onOpenAssignment: _openAssignment,
                                  onSelectCourse: _openCourse,
                                ),
                                TimelineTab(
                                  courses: courses,
                                  assignments: assignments,
                                  todo: snapshot.todo,
                                  hideUnsubmitted: state.prefs.hideUnsubmitted,
                                  onSelectCourse: _openCourse,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: (wide || snapshot == null)
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: '总览',
                ),
                NavigationDestination(
                  icon: Icon(Icons.checklist_outlined),
                  selectedIcon: Icon(Icons.checklist),
                  label: '作业与截止',
                ),
              ],
            ),
    );
  }
}

/// 学期选择器（横向滚动的小片）。
class _TermSelector extends StatelessWidget {
  const _TermSelector({
    required this.terms,
    required this.selected,
    required this.totalCourses,
    required this.onSelect,
  });

  final List<TermGroup> terms;
  final TermFilter selected;
  final int totalCourses;
  final ValueChanged<TermFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (terms.isEmpty) return const SizedBox.shrink();

    Widget chip(String label, TermFilter value, {bool isCurrent = false, int? count}) {
      final active = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(value),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? p.accent.withValues(alpha: 0.12) : p.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? p.accent.withValues(alpha: 0.45) : p.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCurrent) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: p.good, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? p.accent : p.textDim,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text('$count', style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            chip('全部学期', 'all', count: totalCourses),
            for (final t in terms)
              chip(t.name, t.id, isCurrent: t.isCurrent, count: t.courseCount),
          ],
        ),
      ),
    );
  }
}
