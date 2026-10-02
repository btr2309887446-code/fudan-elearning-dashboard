/// 视觉系统。
///
/// 与桌面端保持同一套 token：iOS 风格的浅灰底 + 纯白卡片、主色 #007AFF，
/// 深色则是纯黑底 + #1C1C1E 抬升卡片、主色 #0A84FF。
///
/// 关键在于「页面底」与「卡片」必须有明确色差——两者若同色，
/// 卡片边界只能靠描边区分，看久了很累。

library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.cardBorder,
    required this.border,
    required this.text,
    required this.textDim,
    required this.muted,
    required this.accent,
    required this.cyan,
    required this.purple,
    required this.pink,
    required this.good,
    required this.warn,
    required this.bad,
    required this.ringTrack,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;

  /// 卡片的描边。与 [border]（分隔线）分开：
  /// 深色下卡片几乎不描边，靠灰阶差分层级；浅色下才需要一条细线兜住。
  final Color cardBorder;
  final Color border;
  final Color text;
  final Color textDim;
  final Color muted;

  /// 主色。
  final Color accent;

  /// 功能色。分别承担不同类别的信息，像状态灯一样——
  /// 全用一个蓝会让整屏失去层次。
  final Color cyan;
  final Color purple;
  final Color pink;

  final Color good;
  final Color warn;
  final Color bad;
  final Color ringTrack;

  static const light = AppPalette(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F8FA),
    cardBorder: Colors.transparent,
    border: Color(0xFFE5E7EE),
    text: Color(0xFF1C1C1E),
    textDim: Color(0xFF5B6070),
    muted: Color(0xFF9298A8),
    accent: Color(0xFF007AFF),
    cyan: Color(0xFF0E9AA7),
    purple: Color(0xFF7B4FD1),
    pink: Color(0xFFD6407E),
    good: Color(0xFF34C759),
    warn: Color(0xFFFF9F0A),
    bad: Color(0xFFFF3B30),
    ringTrack: Color(0xFFE9ECF3),
  );

  static const dark = AppPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF2C2C2E),
    // 深色下几乎看不见，只用来在纯黑背景上给卡片一个极其克制的边界。
    cardBorder: Colors.transparent,
    border: Color(0xFF2E2E31),
    text: Color(0xFFF2F2F7),
    textDim: Color(0xFFA8ADBB),
    muted: Color(0xFF74747E),
    accent: Color(0xFF007AFF),
    // 深色下提饱和度，才有「荧光功能色」的味道
    cyan: Color(0xFF3DD9E8),
    purple: Color(0xFFBF7AF5),
    pink: Color(0xFFFF6FA5),
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
    Color? cardBorder,
    Color? border,
    Color? text,
    Color? textDim,
    Color? muted,
    Color? accent,
    Color? cyan,
    Color? purple,
    Color? pink,
    Color? good,
    Color? warn,
    Color? bad,
    Color? ringTrack,
  }) =>
      AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        cardBorder: cardBorder ?? this.cardBorder,
        border: border ?? this.border,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        cyan: cyan ?? this.cyan,
        purple: purple ?? this.purple,
        pink: pink ?? this.pink,
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
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      ringTrack: Color.lerp(ringTrack, other.ringTrack, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

class AppTheme {
  static ThemeData light({
    String? fontFamily,
    TargetPlatform? platform,
  }) =>
      _build(AppPalette.light, Brightness.light, fontFamily, platform);
  static ThemeData dark({
    String? fontFamily,
    TargetPlatform? platform,
  }) =>
      _build(AppPalette.dark, Brightness.dark, fontFamily, platform);

  static ThemeData _build(
    AppPalette p,
    Brightness brightness,
    String? fontFamily,
    TargetPlatform? platform,
  ) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final isIos = effectivePlatform == TargetPlatform.iOS;

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
    final textTheme = isIos
        ? (brightness == Brightness.dark
            ? Typography.whiteCupertino
            : Typography.blackCupertino)
        : null;

    final themed = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      platform: effectivePlatform,
      colorScheme: scheme,
      textTheme: textTheme,
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
        // DanXi uses the compact Cupertino navigation-bar scale rather than
        // an oversized Material headline.
        titleTextStyle:
            styled(size: 18, weight: FontWeight.w600, color: p.text),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.cardBorder),
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
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        hintStyle:
            TextStyle(color: p.muted, fontSize: 15, fontFamily: fontFamily),
        labelStyle:
            TextStyle(color: p.textDim, fontSize: 14, fontFamily: fontFamily),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: fontFamily),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        side: BorderSide(color: p.border),
        labelStyle:
            TextStyle(color: p.textDim, fontSize: 13, fontFamily: fontFamily),
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
  static const xs = SizedBox(height: 3);
  static const sm = SizedBox(height: 7);
  static const md = SizedBox(height: 12);
  // 板块之间的间距。原先 20，整屏显得松；
  // 这类工具型界面要的是「一屏看完」，所以收到 15。
  static const lg = SizedBox(height: 15);
  static const xl = SizedBox(height: 24);

  static const hXs = SizedBox(width: 3);
  static const hSm = SizedBox(width: 8);
  static const hMd = SizedBox(width: 13);
  static const hLg = SizedBox(width: 18);
}
