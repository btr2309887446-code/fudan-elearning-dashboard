import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'diag_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();

  bool _remember = false;
  bool _busy = false;
  bool _obscure = true;
  String? _captchaImage;
  bool _captchaRequired = false;
  String _stage = '';
  String? _localError;
  String? _detail;
  String _preparedFor = '';

  @override
  void initState() {
    super.initState();
    _username.text = widget.state.prefs.rememberedUsername;
    _remember = widget.state.prefs.rememberPassword;
    _restore();
  }

  Future<void> _restore() async {
    final saved = await widget.state.rememberedPassword();
    if (!mounted || saved == null) return;
    setState(() {
      _password.text = saved;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  /// 与官方登录页一致：学号失焦时先问一次要不要验证码。
  Future<void> _checkCaptcha() async {
    final name = _username.text.trim();
    if (name.isEmpty || name == _preparedFor) return;
    _preparedFor = name;
    try {
      final prep = await widget.state.prepareLogin(name);
      if (!mounted) return;
      setState(() {
        _captchaRequired = prep.captchaRequired;
        _captchaImage = prep.captchaImage;
      });
    } catch (_) {
      // 预检失败不打断用户，提交时再报错。
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _username.text.trim();
    final pwd = _password.text;

    setState(() {
      _localError = null;
      _detail = null;
    });

    if (name.isEmpty || pwd.isEmpty) {
      setState(() => _localError = '请填写学号和密码。');
      return;
    }
    if (_captchaRequired && _captcha.text.trim().isEmpty) {
      setState(() => _localError = '请输入图中验证码。');
      return;
    }

    setState(() {
      _busy = true;
      _stage = '正在验证身份…';
    });

    final ok = await widget.state.submitLogin(
      username: name,
      password: pwd,
      captchaCode: _captchaRequired ? _captcha.text.trim() : null,
      remember: _remember,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _stage = '';
      if (!ok) {
        _localError = widget.state.error;
        _detail = null;
      }
    });

    // 会话失效或需要验证码时，重新问一次状态。
    if (!ok) await _checkCaptcha();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = widget.state;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '切换明暗',
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode,
              size: 21,
            ),
            onPressed: () {
              final next = Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              state.setThemeMode(next);
            },
          ),
          Gap.hSm,
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: p.border),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(3),
                        // 用纯图形版：完整版里的「复旦 eLearning」在 42 像素下糊成一团。
                        child: Image.asset('assets/brand/mark.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 11),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('eLearning 学习看板',
                              style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
                          Text('elearning.fudan.edu.cn',
                              style: TextStyle(color: p.muted, fontSize: 11.5)),
                        ],
                      ),
                    ],
                  ),
                  Gap.xl,
                  Text('登录统一身份认证',
                      style: TextStyle(
                          color: p.text, fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                  Gap.sm,
                  Text(
                    '使用你的复旦 UIS 学号和密码登录，数据直接来自 eLearning（Canvas）官方接口。\n'
                    '密码默认不写入磁盘，也不会发送到除复旦认证服务器以外的任何地方。',
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.65),
                  ),
                  Gap.lg,

                  if (state.notice != null) _Alert(text: state.notice!, tone: 'warn'),
                  if (_localError != null) _Alert(text: _localError!, tone: 'error'),

                  TextField(
                    controller: _username,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.username],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '学号', hintText: '例如 20302010001'),
                    onEditingComplete: _checkCaptcha,
                    onTapOutside: (_) {
                      FocusScope.of(context).unfocus();
                      _checkCaptcha();
                    },
                  ),
                  Gap.md,
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: '密码',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),

                  if (_captchaRequired) ...[
                    Gap.md,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _captcha,
                            enabled: !_busy,
                            decoration: const InputDecoration(labelText: '验证码', hintText: '输入图中字符'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (_captchaImage != null)
                          GestureDetector(
                            onTap: _checkCaptcha,
                            child: Container(
                              height: 52,
                              width: 108,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: p.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.network(
                                _captchaImage!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    Center(child: Text('点此刷新', style: TextStyle(color: p.muted, fontSize: 12))),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],

                  Gap.md,
                  Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: _busy ? null : (v) => setState(() => _remember = v ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Text(
                          '记住密码（保存在系统钥匙串）',
                          style: TextStyle(color: p.textDim, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  Gap.sm,

                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                              Gap.hSm,
                              Text('请稍候…'),
                            ],
                          )
                        : const Text('登录'),
                  ),

                  if (_stage.isNotEmpty) ...[
                    Gap.md,
                    Center(child: Text(_stage, style: TextStyle(color: p.muted, fontSize: 12.5))),
                  ],

                  if (_detail != null) ...[
                    Gap.md,
                    _Alert(text: _detail!, tone: 'info'),
                  ],

                  Gap.lg,

                  // 侧载安装时没法看控制台，登录失败只能靠这个入口把过程导出。
                  const Center(child: DiagEntryLink()),

                  Gap.lg,
                  Text(
                    '提示：多次输错密码后，学校认证系统会要求验证码甚至临时锁定账号。'
                    '本应用会在提交前先向认证服务器确认是否需要验证码，尽量避免浪费尝试次数。',
                    style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({required this.text, required this.tone});

  final String text;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (tone) {
      'error' => p.bad,
      'warn' => p.warn,
      _ => p.accent,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.55)),
    );
  }
}
