import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/platform_info.dart';

/// A widget that applies a platform-specific blur effect to its background
///
/// - On iOS 26+: Uses native UIVisualEffectView with systemUltraThinMaterial
/// - On iOS <26: Uses BackdropFilter with ImageFilter.blur
/// - On Android: Uses BackdropFilter with ImageFilter.blur
class AdaptiveBlurView extends StatelessWidget {
  const AdaptiveBlurView({
    super.key,
    required this.child,
    this.blurStyle = BlurStyle.systemUltraThinMaterial,
    this.borderRadius,
    this.glass = false,
    this.clearGlass = false,
    this.fadeBottom = false,
    this.fadeBottomStart = 0.0,
    this.progressiveBlur = false,
    this.tintColor,
    this.frozen = false,
  });

  /// The widget to display on top of the blur effect
  final Widget child;

  /// The blur style (iOS only)
  /// On iOS 26+, uses UIBlurEffect styles
  /// On iOS <26 and Android, uses BackdropFilter
  final BlurStyle blurStyle;

  /// Border radius for the blur view (optional)
  final BorderRadius? borderRadius;

  /// When true on iOS 26+, renders the REAL Liquid Glass (`UIGlassEffect`)
  /// instead of the classic frosted blur (`UIBlurEffect`). The rounded shape
  /// is applied natively via `cornerConfiguration` (from [borderRadius]).
  /// On iOS <26 / Android this flag has no effect (Flutter fallback is used).
  final bool glass;

  /// When true (and [glass] is true on iOS 26+), uses `UIGlassEffect.Style.clear`
  /// (high transparency, for media-rich backgrounds like a feed) instead of
  /// `.regular` (medium transparency, default). No effect on iOS <26 / Android.
  final bool clearGlass;

  /// When true on iOS 26+, applies a vertical gradient mask to the native effect
  /// view so it fades from opaque (top) to transparent (bottom). No effect on
  /// iOS <26 / Android (handle the fade with a Flutter ShaderMask there).
  final bool fadeBottom;

  /// Fraction of the height (0..1) that stays fully opaque before [fadeBottom]
  /// starts fading. 0 = linear fade from the top (default). e.g. 0.8 = top 80%
  /// solid, only the bottom edge softens (Instagram sheet-header look). iOS 26+.
  final double fadeBottomStart;

  /// When true on iOS 26+ (and not glass), renders a VARIABLE/progressive blur
  /// (stacked masked blur layers) instead of a single blur — strong blur up top,
  /// gradually ramping down over [fadeBottomStart]..1 (Instagram-style soft melt).
  /// No effect on iOS <26 / Android or glass mode.
  final bool progressiveBlur;

  /// Optional tint for the native `UIGlassEffect` (iOS 26+, when [glass] is true):
  /// colors the glass (stained-glass) while keeping the liquid effect. Use a
  /// color with alpha to control strength. No effect on iOS <26 / Android (tint
  /// the Flutter glass there via its own settings).
  final Color? tintColor;

  /// When true on iOS 26+, freezes the native effect to a static snapshot and
  /// stops the live blur recompute — used during route transitions to avoid
  /// per-frame backdrop sampling jank. No effect on iOS <26 / Android.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    // iOS 26+ uses native UIVisualEffectView
    if (PlatformInfo.isIOS && PlatformInfo.isIOSVersionInRange(26, 99)) {
      return Ios26NativeBlurView(
        blurStyle: blurStyle,
        borderRadius: borderRadius,
        glass: glass,
        clearGlass: clearGlass,
        fadeBottom: fadeBottom,
        fadeBottomStart: fadeBottomStart,
        progressiveBlur: progressiveBlur,
        tintColor: tintColor,
        frozen: frozen,
        child: child,
      );
    }

    // iOS <26 and Android use Flutter Liquid Glass effect
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          // Background blur layer
          Positioned.fill(
            child: BackdropFilter(
              filter: blurStyle.toImageFilter(),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: _getLiquidGlassGradient(context),
                ),
              ),
            ),
          ),
          // Frosted glass overlay with noise texture effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getGlassOverlayColors(context),
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Subtle inner glow for depth
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: _getBorderColor(context), width: 0.5),
              ),
            ),
          ),
          // Content on top
          child,
        ],
      ),
    );
  }

  LinearGradient _getLiquidGlassGradient(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    switch (blurStyle) {
      case BlurStyle.systemUltraThinMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.03),
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.03),
                ]
              : [
                  Colors.white.withValues(alpha: 0.25),
                  Colors.white.withValues(alpha: 0.35),
                  Colors.white.withValues(alpha: 0.25),
                ],
        );
      case BlurStyle.systemThinMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.06),
                ]
              : [
                  Colors.white.withValues(alpha: 0.4),
                  Colors.white.withValues(alpha: 0.5),
                  Colors.white.withValues(alpha: 0.4),
                ],
        );
      case BlurStyle.systemMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.1),
                ]
              : [
                  Colors.white.withValues(alpha: 0.6),
                  Colors.white.withValues(alpha: 0.7),
                  Colors.white.withValues(alpha: 0.6),
                ],
        );
      case BlurStyle.systemThickMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.13),
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.13),
                ]
              : [
                  Colors.white.withValues(alpha: 0.75),
                  Colors.white.withValues(alpha: 0.8),
                  Colors.white.withValues(alpha: 0.75),
                ],
        );
      case BlurStyle.systemChromeMaterial:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.45),
                ]
              : [
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.9),
                  Colors.white.withValues(alpha: 0.85),
                ],
        );
    }
  }

  List<Color> _getGlassOverlayColors(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    if (isDark) {
      return [
        Colors.white.withValues(alpha: 0.01),
        Colors.transparent,
        Colors.black.withValues(alpha: 0.02),
      ];
    } else {
      return [
        Colors.white.withValues(alpha: 0.15),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.08),
      ];
    }
  }

  Color _getBorderColor(BuildContext context) {
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    switch (blurStyle) {
      case BlurStyle.systemUltraThinMaterial:
      case BlurStyle.systemThinMaterial:
        return isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.5);
      case BlurStyle.systemMaterial:
      case BlurStyle.systemThickMaterial:
        return isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.6);
      case BlurStyle.systemChromeMaterial:
        return isDark
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.7);
    }
  }
}

/// Blur styles matching iOS UIBlurEffect.Style
enum BlurStyle {
  /// Ultra-thin material (iOS 26+ Liquid Glass default)
  systemUltraThinMaterial,

  /// Thin material
  systemThinMaterial,

  /// Regular material
  systemMaterial,

  /// Thick material
  systemThickMaterial,

  /// Chrome material (most opaque)
  systemChromeMaterial,
}

extension BlurStyleExtension on BlurStyle {
  /// Convert to UIBlurEffect.Style string for native iOS
  String toUIBlurEffectStyle() {
    switch (this) {
      case BlurStyle.systemUltraThinMaterial:
        return 'systemUltraThinMaterial';
      case BlurStyle.systemThinMaterial:
        return 'systemThinMaterial';
      case BlurStyle.systemMaterial:
        return 'systemMaterial';
      case BlurStyle.systemThickMaterial:
        return 'systemThickMaterial';
      case BlurStyle.systemChromeMaterial:
        return 'systemChromeMaterial';
    }
  }

  /// Convert to ImageFilter for BackdropFilter (iOS <26 and Android)
  ui.ImageFilter toImageFilter() {
    switch (this) {
      case BlurStyle.systemUltraThinMaterial:
        return ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10);
      case BlurStyle.systemThinMaterial:
        return ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15);
      case BlurStyle.systemMaterial:
        return ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20);
      case BlurStyle.systemThickMaterial:
        return ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25);
      case BlurStyle.systemChromeMaterial:
        return ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30);
    }
  }
}

/// iOS 26+ native blur view using UIVisualEffectView
class Ios26NativeBlurView extends StatefulWidget {
  const Ios26NativeBlurView({
    super.key,
    required this.child,
    required this.blurStyle,
    this.borderRadius,
    this.glass = false,
    this.clearGlass = false,
    this.fadeBottom = false,
    this.fadeBottomStart = 0.0,
    this.progressiveBlur = false,
    this.tintColor,
    this.frozen = false,
  });

  final Widget child;
  final BlurStyle blurStyle;
  final BorderRadius? borderRadius;
  final double fadeBottomStart;
  final bool progressiveBlur;

  /// Native UIGlassEffect tint (stained glass), iOS 26+ when [glass] is true.
  final Color? tintColor;

  /// True -> native UIGlassEffect (real Liquid Glass), shape via cornerConfiguration.
  final bool glass;

  /// True -> UIGlassEffect.Style.clear (high transparency) instead of .regular.
  final bool clearGlass;

  /// True -> vertical gradient mask on the native effect view (opaque top ->
  /// transparent bottom).
  final bool fadeBottom;

  /// True -> native effect frozen to a static snapshot (live blur paused).
  final bool frozen;

  @override
  State<Ios26NativeBlurView> createState() => Ios26NativeBlurViewState();
}

class Ios26NativeBlurViewState extends State<Ios26NativeBlurView> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  bool? _lastFrozen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  @override
  void didUpdateWidget(Ios26NativeBlurView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blurStyle != widget.blurStyle && _channel != null) {
      _updateBlurStyle();
    }
    if (oldWidget.frozen != widget.frozen) {
      _syncFrozenIfNeeded();
    }
  }

  /// Native efekti dondur/coz (transition sirasinda snapshot). Kanal henuz
  /// hazir degilse sessizce gecer; hazir olunca [onPlatformViewCreated] gonderir.
  Future<void> _syncFrozenIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    if (_lastFrozen != widget.frozen) {
      try {
        await ch.invokeMethod('setFrozen', {'frozen': widget.frozen});
        _lastFrozen = widget.frozen;
      } catch (e) {
        // Platform view henuz hazir degilse yoksay.
      }
    }
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (_lastIsDark != isDark) {
      try {
        await ch.invokeMethod('setBrightness', {'isDark': isDark});
        _lastIsDark = isDark;
      } catch (e) {
        // Ignore errors if platform view is not yet ready
      }
    }
  }

  Future<void> _updateBlurStyle() async {
    try {
      await _channel?.invokeMethod('updateBlurStyle', {
        'blurStyle': widget.blurStyle.toUIBlurEffectStyle(),
      });
    } catch (e) {
      // Ignore errors during blur style update
    }
  }

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      children: [
        // Native blur/glass view in background
        Positioned.fill(
          child: UiKitView(
            viewType: 'adaptive_platform_ui/ios26_blur_view',
            creationParams: {
              'blurStyle': widget.blurStyle.toUIBlurEffectStyle(),
              'isDark':
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark,
              'useGlass': widget.glass,
              'clearGlass': widget.clearGlass,
              'fadeBottom': widget.fadeBottom,
              'fadeStart': widget.fadeBottomStart,
              'progressiveBlur': widget.progressiveBlur,
              if (widget.tintColor != null)
                'tintColor': _colorToArgb(widget.tintColor!),
              'cornerRadius': widget.borderRadius?.topLeft.x ?? 0.0,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: (int id) {
              _channel = MethodChannel(
                'adaptive_platform_ui/ios26_blur_view_$id',
              );
              // Kanal hazir: mevcut parlaklik + frozen durumunu gonder (initial).
              _syncBrightnessIfNeeded();
              _syncFrozenIfNeeded();
            },
          ),
        ),
        // Child on top
        widget.child,
      ],
    );

    // Glass: the native UIGlassEffect shapes itself via cornerConfiguration
    // (including its edge lensing). A Flutter ClipRRect here would cut that
    // edge, so skip clipping for glass and let native own the shape.
    if (widget.glass) return stack;

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: stack,
    );
  }
}

/// Color -> ARGB int (UIColor(argb:) ile uyumlu) — native tarafa tint gondermek icin.
int _colorToArgb(Color c) {
  return (((c.a * 255.0).round() & 0xFF) << 24) |
      (((c.r * 255.0).round() & 0xFF) << 16) |
      (((c.g * 255.0).round() & 0xFF) << 8) |
      ((c.b * 255.0).round() & 0xFF);
}
