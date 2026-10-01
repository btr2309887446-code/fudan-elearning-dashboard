import 'package:flutter/material.dart';

import 'core/session.dart';
import 'platform/storage.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 演示模式不碰任何平台存储，也不需要账号。
  final store = kDemoMode ? MemoryStore() : await PrefsStore.open();
  final state = AppState(
    store: store,
    secure: kDemoMode ? null : SecretStore(),
    demo: kDemoMode,
  );

  runApp(ElearningApp(state: state));
}

class ElearningApp extends StatelessWidget {
  const ElearningApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return MaterialApp(
          title: 'eLearning 看板',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: state.prefs.themeMode,
          home: _Root(state: state),
        );
      },
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({required this.state});
  final AppState state;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.boot());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (state.booting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              Gap.md,
              Text('正在启动…', style: TextStyle(color: context.palette.muted, fontSize: 13.5)),
            ],
          ),
        ),
      );
    }

    if (!state.loggedIn) return LoginScreen(state: state);
    return HomeShell(state: state);
  }
}
