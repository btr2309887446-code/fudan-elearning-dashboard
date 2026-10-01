import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// 首页板块。顺序即默认顺序；key 存进偏好里，改动要保持兼容。
///
/// 与桌面端 `SECTIONS` 一一对应，两边的 key 必须一致。
const List<({String key, String label, IconData icon})> kSectionItems = [
  (key: 'stats', label: '数据概览', icon: Icons.insights_outlined),
  (key: 'unsubmitted', label: '未提交作业', icon: Icons.inbox_outlined),
  (key: 'soon', label: '三天内截止', icon: Icons.schedule),
  (key: 'charts', label: '得分与关注', icon: Icons.bar_chart),
  (key: 'courses', label: '课程卡片', icon: Icons.menu_book_outlined),
];

/// 设置页。
///
/// 主题切换与「首页板块」都收在这里：这些是偶尔改一次的东西，
/// 常驻主界面只会挤占视线。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final order = state.effectiveSectionOrder();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // --- 主题 ---
              const SectionHeader('外观'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '主题',
                        style: TextStyle(fontSize: 13, color: p.textDim),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _themeChip(context, '浅色', ThemeMode.light),
                        _themeChip(context, '深色', ThemeMode.dark),
                        _themeChip(context, '跟随系统', ThemeMode.system),
                      ],
                    ),
                  ],
                ),
              ),

              Gap.lg,

              // --- 显示 ---
              const SectionHeader('显示'),
              AppCard(
                // 不用 SwitchListTile：它要求自己铺在 Scaffold 背景上，
                // 放进 AppCard 会触发「水波纹可能不可见」的断言。
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('忽略未提交的作业',
                              style: TextStyle(fontSize: 14, color: p.text)),
                          const SizedBox(height: 3),
                          Text(
                            '只影响显示，不影响得分',
                            style: TextStyle(fontSize: 11.5, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.prefs.hideUnsubmitted,
                      onChanged: (v) => state.setHideUnsubmitted(v),
                    ),
                  ],
                ),
              ),

              Gap.lg,

              // --- 首页板块 ---
              const SectionHeader('首页板块'),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < order.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border),
                      _sectionRow(context, order, i),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '点名字开关板块，点 ▲▼ 调整顺序。改动会记住。',
                      style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.6),
                    ),
                  ),
                  TextButton(
                    onPressed: () => state.resetDashboardOrder(),
                    child: const Text('恢复默认顺序'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _themeChip(BuildContext context, String label, ThemeMode mode) {
    final p = context.palette;
    final on = state.prefs.themeMode == mode;
    return InkWell(
      onTap: () => state.setThemeMode(mode),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? p.accent.withValues(alpha: 0.12) : p.surface,
          border: Border.all(color: on ? p.accent : p.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: on ? p.accent : p.textDim,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _sectionRow(BuildContext context, List<String> order, int i) {
    final p = context.palette;
    final key = order[i];
    ({String key, String label, IconData icon})? meta;
    for (final s in kSectionItems) {
      if (s.key == key) {
        meta = s;
        break;
      }
    }
    if (meta == null) return const SizedBox.shrink();

    final on = state.prefs.dashboardSections[key] != false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => state.toggleDashboardSection(key),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    // 勾选框：一眼看出这个板块是开是关
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: on ? p.accent : Colors.transparent,
                        border: Border.all(color: on ? p.accent : p.muted, width: 1.5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: on
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Icon(meta.icon, size: 15, color: on ? p.accent : p.muted),
                    const SizedBox(width: 7),
                    Text(
                      meta.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: on ? p.text : p.muted,
                        fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _moveBtn(context, '▲', i > 0, () => state.moveDashboardSection(key, -1)),
          _moveBtn(context, '▼', i < order.length - 1, () => state.moveDashboardSection(key, 1)),
        ],
      ),
    );
  }

  Widget _moveBtn(BuildContext context, String label, bool enabled, VoidCallback onTap) {
    final p = context.palette;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            height: 1,
            color: (enabled ? p.textDim : p.muted).withValues(alpha: enabled ? 1 : 0.3),
          ),
        ),
      ),
    );
  }
}
