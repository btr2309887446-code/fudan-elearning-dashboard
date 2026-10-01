/// 视觉系统。
///
/// 与桌面端保持同一套 token：iOS 风格的浅灰底 + 纯白卡片、主色 #007AFF，
/// 深色则是纯黑底 + #1C1C1E 抬升卡片、主色 #0A84FF。
///
/// 关键在于「页面底」与「卡片」必须有明确色差——两者若同色，
/// 卡片边界只能靠描边区分，看久了很累。

library;

import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textDim,
    required this.muted,
    required this.accent,
    required this.good,
    required this.warn,
    required this.bad,
    required this.ringTrack,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color textDim;
  final Color muted;
  final Color accent;
  final Color good;
  final Color warn;
  final Color bad;
  final Color ringTrack;

  static const light = AppPalette(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F8FA),
    border: Color(0xFFE5E7EE),
    text: Color(0xFF1C1C1E),
    textDim: Color(0xFF5B6070),
    muted: Color(0xFF9298A8),
    accent: Color(0xFF007AFF),
    good: Color(0xFF34C759),
    warn: Color(0xFFFF9F0A),
    bad: Color(0xFFFF3B30),
    ringTrack: Color(0xFFE9ECF3),
  );

  static const dark = AppPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF2C2C2E),
    border: Color(0xFF2E2E31),
    text: Color(0xFFF2F2F7),
    textDim: Color(0xFFA8ADBB),
    muted: Color(0xFF74747E),
    accent: Color(0xFF0A84FF),
    good: Color(0xFF30D158),
    warn: Color(0xFFFFD60A),
    bad: Color(0xFFFF453A),
    ringTrack: Color(0xFF323234),
  );

  /// 分数分档配色，全应用统一。
  Color forScore(double? score) {
    if (score == null || score.isNaN) return muted;
    if (score >= 90) return good;
    if (score >= 80) return accent;
    if (score >= 70) return const Color(0xFFFFB020);
    if (score >= 60) return const Color(0xFFFF9500);
    return bad;
  }

  static String labelForScore(double? score) {
    if (score == null || score.isNaN) return '暂无';
    if (score >= 90) return '优秀';
    if (score >= 80) return '良好';
    if (score >= 70) return '中等';
    if (score >= 60) return '及格';
    return '待提升';
  }

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? text,
    Color? textDim,
    Color? muted,
    Color? accent,
    Color? good,
    Color? warn,
    Color? bad,
    Color? ringTrack,
  }) =>
      AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        good: good ?? this.good,
        warn: warn ?? this.warn,
        bad: bad ?? this.bad,
        ringTrack: ringTrack ?? this.ringTrack,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      ringTrack: Color.lerp(ringTrack, other.ringTrack, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

class AppTheme {
  static ThemeData light({String? fontFamily}) => _build(AppPalette.light, Brightness.light, fontFamily);
  static ThemeData dark({String? fontFamily}) => _build(AppPalette.dark, Brightness.dark, fontFamily);

  static ThemeData _build(AppPalette p, Brightness brightness, String? fontFamily) {
    // 主题里显式写的 TextStyle **不会**继承 textTheme 的字体，
    // 所以要逐个带上 fontFamily，否则这些控件会退回平台默认字体。
    TextStyle styled({
      required double size,
      required FontWeight weight,
      required Color color,
      double? letterSpacing,
      double? height,
    }) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          fontFamily: fontFamily,
          letterSpacing: letterSpacing,
          height: height,
        );

    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
    ).copyWith(
      surface: p.surface,
      primary: p.accent,
      error: p.bad,
    );

    final themed = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: styled(size: 22, weight: FontWeight.w700, color: p.text, letterSpacing: -0.4),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accent.withValues(alpha: 0.14),
        elevation: 0,
        height: 62,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontFamily: fontFamily,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? p.accent : p.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected) ? p.accent : p.muted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        hintStyle: TextStyle(color: p.muted, fontSize: 15, fontFamily: fontFamily),
        labelStyle: TextStyle(color: p.textDim, fontSize: 14, fontFamily: fontFamily),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: fontFamily),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(color: p.textDim, fontSize: 13, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textDim,
        textColor: p.text,
      ),
    );

    // 正文字体必须落在 textTheme 上才会被所有 Text 继承；
    // 上面逐个写 fontFamily 只覆盖了主题自己定义的那几个控件样式。
    if (fontFamily == null) return themed;
    return themed.copyWith(
      textTheme: themed.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: themed.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }
}

/// 常用间距，避免各处硬编码。
class Gap {
  static const xs = SizedBox(height: 4);
  static const sm = SizedBox(height: 8);
  static const md = SizedBox(height: 14);
  static const lg = SizedBox(height: 20);
  static const xl = SizedBox(height: 28);

  static const hXs = SizedBox(width: 4);
  static const hSm = SizedBox(width: 8);
  static const hMd = SizedBox(width: 14);
  static const hLg = SizedBox(width: 20);
}
