import 'package:flutter/material.dart';

const _seed = Color(0xFF0E7C66);

/// Colors that carry meaning beyond Material's scheme. Status colors are
/// reserved for status and always appear with an icon and a label.
@immutable
class RunwayColors extends ThemeExtension<RunwayColors> {
  final Color good;
  final Color warning;
  final Color critical;

  /// Readable text on top of each status color.
  final Color onGood;
  final Color onWarning;
  final Color onCritical;

  /// Income amounts ("+RM 1,500.00").
  final Color incomeText;

  /// Chart marks and chrome.
  final Color series;
  final Color grid;
  final Color axis;
  final Color muted;

  const RunwayColors({
    required this.good,
    required this.warning,
    required this.critical,
    required this.onGood,
    required this.onWarning,
    required this.onCritical,
    required this.incomeText,
    required this.series,
    required this.grid,
    required this.axis,
    required this.muted,
  });

  static const light = RunwayColors(
    good: Color(0xFF0CA30C),
    warning: Color(0xFFFAB219),
    critical: Color(0xFFD03B3B),
    onGood: Colors.white,
    onWarning: Color(0xFF0B0B0B),
    onCritical: Colors.white,
    incomeText: Color(0xFF006300),
    series: Color(0xFF2A78D6),
    grid: Color(0xFFE1E0D9),
    axis: Color(0xFFC3C2B7),
    muted: Color(0xFF6E6C66),
  );

  static const dark = RunwayColors(
    good: Color(0xFF0CA30C),
    warning: Color(0xFFFAB219),
    critical: Color(0xFFD03B3B),
    onGood: Colors.white,
    onWarning: Color(0xFF0B0B0B),
    onCritical: Colors.white,
    incomeText: Color(0xFF3FC23F),
    series: Color(0xFF3987E5),
    grid: Color(0xFF2C2C2A),
    axis: Color(0xFF383835),
    muted: Color(0xFF9A988F),
  );

  @override
  RunwayColors copyWith() => this;

  @override
  RunwayColors lerp(RunwayColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension RunwayTheme on BuildContext {
  RunwayColors get runway => Theme.of(this).extension<RunwayColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
  );
  return base.copyWith(
    extensions: [
      brightness == Brightness.light ? RunwayColors.light : RunwayColors.dark,
    ],
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
