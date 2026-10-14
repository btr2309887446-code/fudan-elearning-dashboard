import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/summary.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../diag_screen.dart';
import '../login_screen.dart';
import 'components.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IosScrollPage(
      title: '我的',
      scrollKey: const PageStorageKey('ios-profile'),
      children: [
        Text(
          state.snapshot?.profile.name ?? '复旦同学',
          style: TextStyle(
            fontSize: 24,
            color: p.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          state.demo ? '演示模式 · 不保存账号信息' : '复旦统一身份认证',
          style: TextStyle(fontSize: 15, color: p.textDim),
        ),
        const IosSection('作业提醒'),
        IosGroup(
          children: [
            CupertinoListTile(
              title: const Text('每日截止提醒'),
              subtitle: const Text('当前学期 · 北京时间'),
              trailing: CupertinoSwitch(
                value: state.prefs.remindersEnabled,
                onChanged: (value) => state.setRemindersEnabled(value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '当天 08:00 汇总提醒。08:00 及以前截止的作业，在前一天 20:00 提醒。\n'
                '提醒依据上次同步的内容，提交作业或老师修改截止后，请再次同步。',
                style: TextStyle(fontSize: 15, color: p.textDim, height: 1.5),
              ),
            ),
            if (state.reminderNotice != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.reminderNotice!,
                  style: TextStyle(fontSize: 15, color: p.textDim),
                ),
              ),
            if (state.reminderPermissionDenied)
              CupertinoListTile(
                title: const Text('打开 iPhone 通知设置'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => state.openUrl('app-settings:'),
              ),
          ],
        ),
        const IosSection('外观与同步'),
        IosGroup(
          children: [
            CupertinoListTile(
              title: const Text('外观'),
              additionalInfo: Text(switch (state.prefs.themeMode) {
                ThemeMode.system => '跟随系统',
                ThemeMode.light => '浅色',
                ThemeMode.dark => '深色',
              }),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final mode = await iosChoice(context, '外观', const {
                  ThemeMode.system: '跟随系统',
                  ThemeMode.light: '浅色',
                  ThemeMode.dark: '深色',
                }, selected: state.prefs.themeMode);
                if (mode != null) await state.setThemeMode(mode);
              },
            ),
            CupertinoListTile(
              title: const Text('同步范围'),
              additionalInfo: Text(
                state.prefs.refreshScope == 'all' ? '全部学期' : '当前学期',
              ),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final scope = await iosChoice(context, '同步范围', const {
                  'current': '当前学期',
                  'all': '全部学期',
                }, selected: state.prefs.refreshScope);
                if (scope != null) await state.setRefreshScope(scope);
              },
            ),
            CupertinoListTile(
              title: Text(state.busy ? '正在同步…' : '立即同步'),
              trailing: state.busy
                  ? const CupertinoActivityIndicator()
                  : const Icon(CupertinoIcons.arrow_clockwise, size: 20),
              onTap: state.busy ? null : () => state.refresh(force: true),
            ),
            if (state.error != null || state.notice != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.error ?? state.notice!,
                  style: TextStyle(fontSize: 15, color: p.textDim),
                ),
              ),
            if (!state.loggedIn)
              CupertinoListTile(
                title: const Text('重新登录'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => LoginScreen(
                      state: state,
                      onSuccess: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const IosSection('作业摘要与帮助'),
        IosGroup(
          children: [
            CupertinoListTile(
              title: const Text('作业摘要配置'),
              subtitle: Text(state.prefs.llm.enabled ? '已开启' : '未开启，仍可查看作业原文'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => SummarySettingsPage(state: state),
                ),
              ),
            ),
            CupertinoListTile(
              title: const Text('诊断日志'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(builder: (_) => const DiagScreen()),
              ),
            ),
            CupertinoListTile(
              title: const Text('使用帮助'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => state.openUrl(
                'https://github.com/btr2309887446-code/fudan-elearning-dashboard/blob/master/flutter_app/README.md',
              ),
            ),
          ],
        ),
        if (!state.demo) ...[
          const SizedBox(height: 24),
          IosGroup(
            children: [
              CupertinoListTile(
                title: Text('退出登录', style: TextStyle(color: p.bad)),
                onTap: () async {
                  if (await iosConfirm(
                    context,
                    '退出登录？',
                    '将清除本机登录状态、缓存数据和已安排的作业提醒。',
                    confirm: '退出',
                    destructive: true,
                  )) {
                    await state.logout();
                  }
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '非官方校园工具 · 成绩来自 eLearning\n系统日历导出为单向添加，不自动更新或删除。',
          style: TextStyle(fontSize: 13, color: p.textDim, height: 1.5),
        ),
      ],
    );
  }
}

class SummarySettingsPage extends StatefulWidget {
  const SummarySettingsPage({super.key, required this.state});
  final AppState state;
  @override
  State<SummarySettingsPage> createState() => _SummarySettingsPageState();
}

class _SummarySettingsPageState extends State<SummarySettingsPage> {
  late final _url = TextEditingController(text: widget.state.prefs.llm.baseUrl);
  late final _model = TextEditingController(text: widget.state.prefs.llm.model);
  late final _key = TextEditingController(text: widget.state.prefs.llm.apiKey);
  late bool _enabled = widget.state.prefs.llm.enabled;
  bool _saving = false;
  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (_enabled &&
        (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            _model.text.trim().isEmpty ||
            _key.text.trim().isEmpty)) {
      await iosMessage(context, '开启摘要时，请填写 HTTPS 接口地址、模型名称和密钥。');
      return;
    }
    setState(() => _saving = true);
    await widget.state.setLlm(
      LlmConfig(
        baseUrl: _url.text.trim(),
        model: _model.text.trim(),
        apiKey: _key.text.trim(),
        enabled: _enabled,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: context.palette.background,
    navigationBar: CupertinoNavigationBar(
      middle: const Text('作业摘要配置'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _saving ? null : _save,
        child: const Text('保存'),
      ),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IosGroup(
            children: [
              CupertinoListTile(
                title: const Text('启用 AI 摘要'),
                trailing: CupertinoSwitch(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ),
            ],
          ),
          const IosSection('接口地址'),
          CupertinoTextField(
            controller: _url,
            placeholder: 'https://…/v1',
            autocorrect: false,
            keyboardType: TextInputType.url,
            padding: const EdgeInsets.all(14),
          ),
          const IosSection('模型名称'),
          CupertinoTextField(
            controller: _model,
            autocorrect: false,
            padding: const EdgeInsets.all(14),
          ),
          const IosSection('接口密钥'),
          CupertinoTextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            padding: const EdgeInsets.all(14),
          ),
          const SizedBox(height: 20),
          Text(
            '使用已有的兼容接口配置。保存不会发起请求；查看较长作业说明时才会生成摘要。',
            style: TextStyle(
              fontSize: 15,
              color: context.palette.textDim,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
