import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/types.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'assignment_detail_screen.dart';
import 'course_detail_screen.dart';
import 'overview_detail_screen.dart';
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
    if (_termTouched && _term != 'all' && terms.any((t) => t.id == _term)) {
      return;
    }

    final current =
        terms.firstWhere((t) => t.isCurrent, orElse: () => terms.first);
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
      _detailRoute(
        builder: (_) => AssignmentDetailScreen(state: state, row: row),
      ),
    );
  }

  void _openCourse(int id) {
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    Navigator.of(context).push(
      _detailRoute(
        builder: (_) => CourseDetailScreen(
          state: state,
          snapshot: snapshot,
          courseId: id,
          hideUnsubmitted: state.prefs.hideUnsubmitted,
          onOpenAssignment: _openAssignment,
        ),
      ),
    );
  }

  void _openMetric(OverviewDetailKind kind) {
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    final courseIds = _scopedCourses.map((course) => course.id).toSet();
    final todo = snapshot.todo
        .where((entry) =>
            entry.courseId == null || courseIds.contains(entry.courseId))
        .toList();
    Navigator.of(context).push(
      _detailRoute(
        builder: (_) => OverviewDetailScreen(
          kind: kind,
          courses: _scopedCourses,
          assignments: _scopedAssignments,
          todo: todo,
          ignoredSet: state.ignoredSet,
          onOpenCourse: _openCourse,
          onOpenAssignment: _openAssignment,
          onOpenUrl: state.openUrl,
        ),
      ),
    );
  }

  PageRoute<void> _detailRoute({required WidgetBuilder builder}) {
    // DanXi keeps detail pages in the native iOS navigation rhythm. Android
    // and desktop retain Material's familiar transition.
    if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS) {
      return CupertinoPageRoute<void>(builder: builder);
    }
    return MaterialPageRoute<void>(builder: builder);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final snapshot = state.snapshot;
    final courses = _scopedCourses;
    final assignments = _scopedAssignments;

    // iPad 也沿用 iOS 的悬浮毛玻璃底栏；Windows / Android 的宽屏
    // 才切换为侧栏，避免 iPad 上底部导航突然消失。
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final wide = !isIos && MediaQuery.sizeOf(context).width >= 760;
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
                child: SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2)),
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
                    MaterialPageRoute(
                        builder: (_) => SettingsScreen(state: state)),
                  );
                case 'logout':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('退出登录'),
                      content: const Text('将清除本机保存的登录状态与缓存数据。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('退出')),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (snapshot == null)
            Center(
              child:
                  Text('还没有数据', style: TextStyle(color: p.muted, fontSize: 14)),
            )
          else
            Row(
              children: [
                if (wide) ...[
                  Container(
                    width: MediaQuery.sizeOf(context).width >= 1120 ? 238 : 204,
                    color: p.surface,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/brand/mark.png',
                                width: 34,
                                height: 34,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'eLearning',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: p.border),
                        Expanded(
                          child: NavigationRail(
                            selectedIndex: _tab,
                            onDestinationSelected: (i) =>
                                setState(() => _tab = i),
                            extended: MediaQuery.sizeOf(context).width >= 1120,
                            minExtendedWidth: 218,
                            minWidth: 76,
                            groupAlignment: -0.88,
                            labelType: MediaQuery.sizeOf(context).width >= 1120
                                ? NavigationRailLabelType.none
                                : NavigationRailLabelType.all,
                            backgroundColor: Colors.transparent,
                            indicatorColor: p.accent.withValues(alpha: 0.14),
                            selectedIconTheme:
                                IconThemeData(color: p.accent, size: 23),
                            unselectedIconTheme:
                                IconThemeData(color: p.muted, size: 22),
                            selectedLabelTextStyle: TextStyle(
                              color: p.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: fontFamily,
                            ),
                            unselectedLabelTextStyle: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                fontFamily: fontFamily),
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
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                          child: _RailProfile(
                            name: snapshot.profile.name,
                            termName: _termName,
                          ),
                        ),
                      ],
                    ),
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
                                  reusedCourseCount: snapshot.reusedCourseCount,
                                  onOpenAssignment: _openAssignment,
                                  onSelectCourse: _openCourse,
                                  onOpenMetric: _openMetric,
                                  onRefresh: state.busy
                                      ? null
                                      : () => state.refresh(force: true),
                                  profileName: snapshot.profile.name,
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
          if (!wide && snapshot != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _GlassDock(
                    index: _tab,
                    onSelect: (i) => setState(() => _tab = i),
                    items: const [
                      (
                        icon: Icons.dashboard_outlined,
                        active: Icons.dashboard,
                        label: '总览'
                      ),
                      (
                        icon: Icons.checklist_outlined,
                        active: Icons.checklist,
                        label: '作业与截止'
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailProfile extends StatelessWidget {
  const _RailProfile({required this.name, required this.termName});

  final String name;
  final String termName;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: p.accent.withValues(alpha: 0.14),
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1),
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '未登录用户' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  termName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 悬浮毛玻璃底栏。
///
/// 照着旦挞（DanXi）那种做法：不贴屏幕边缘、四角圆润、背后透出内容的模糊，
/// 选中的那一项是嵌在胶囊里的小药丸，而不是 Material 那种整条高亮。
///
/// 用 [BackdropFilter] 而不是半透明纯色——后者在内容滚动时看得出是块死板色块，
/// 前者才有「玻璃」的感觉。
class _GlassDock extends StatelessWidget {
  const _GlassDock({
    required this.index,
    required this.onSelect,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<({IconData icon, IconData active, String label})> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.58 : 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            // Keep the backdrop filter as the first visual layer. A nearly
            // opaque child would hide the content behind the dock entirely.
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            blendMode: BlendMode.srcOver,
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.08),
                          const Color(0xFF5B5B61).withValues(alpha: 0.18),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.62),
                          const Color(0xFFE3E6ED).withValues(alpha: 0.46),
                        ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.24 : 0.55),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(child: _dockItem(context, i)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dockItem(BuildContext context, int i) {
    final p = context.palette;
    final on = i == index;
    final it = items[i];

    return Semantics(
      button: true,
      selected: on,
      label: it.label,
      child: InkWell(
        onTap: () => onSelect(i),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              // 选中的是嵌在胶囊里的小药丸，不是整条高亮
              color: on ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  on ? it.active : it.icon,
                  size: 19,
                  color: on ? p.accent : p.muted,
                ),
                const SizedBox(width: 7),
                // 文字始终显示，不搞「选中才展开」那一套。
                // 试过只给选中项显示文字（iOS 常见做法），结果是未选中的
                // 页面在界面上完全没有文字入口，可发现性太差。
                Flexible(
                  child: Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? p.accent : p.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

    Widget chip(String label, TermFilter value,
        {bool isCurrent = false, int? count}) {
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
                      decoration:
                          BoxDecoration(color: p.good, shape: BoxShape.circle),
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
                    Text('$count',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
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
