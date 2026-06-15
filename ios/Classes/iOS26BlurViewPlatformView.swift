import UIKit
import Flutter

/// Factory for creating iOS 26 native blur view platform views
class iOS26BlurViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26BlurViewPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// UIVisualEffectView whose mask layer tracks its bounds — needed so a
/// gradient (fade) mask resizes with the view, since CALayer masks don't
/// autoresize.
class FadingVisualEffectView: UIVisualEffectView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.mask?.frame = bounds
    }
}

/// Native iOS 26 blur view using UIVisualEffectView
class iOS26BlurViewPlatformView: NSObject, FlutterPlatformView {
    private var _blurView: FadingVisualEffectView
    private var _channel: FlutterMethodChannel
    private var _viewId: Int64
    private var isDark: Bool = false
    private var useGlass: Bool = false
    private var clearGlass: Bool = false
    private var fadeBottom: Bool = false
    private var cornerRadius: CGFloat = 0
    private var tintArgb: Int?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _viewId = viewId

        // Parse blur style and brightness from arguments
        var blurStyle: UIBlurEffect.Style = .systemUltraThinMaterial
        if let params = args as? [String: Any] {
            if let styleString = params["blurStyle"] as? String {
                blurStyle = iOS26BlurViewPlatformView.parseBlurStyle(styleString)
            }
            isDark = params["isDark"] as? Bool ?? false
            useGlass = params["useGlass"] as? Bool ?? false
            clearGlass = params["clearGlass"] as? Bool ?? false
            fadeBottom = params["fadeBottom"] as? Bool ?? false
            tintArgb = params["tintColor"] as? Int
            if let radius = params["cornerRadius"] as? Double {
                cornerRadius = CGFloat(radius)
            }
        }

        // Create the effect view. On iOS 26+ with useGlass, use the REAL
        // Liquid Glass (UIGlassEffect); otherwise fall back to the classic
        // frosted blur (UIBlurEffect), which also covers iOS < 26.
        if useGlass, #available(iOS 26.0, *) {
            // .clear = yuksek seffaflik (medya/foto arka plan, or. feed),
            // .regular = orta seffaflik (varsayilan, panel/buton vb.).
            let glass = UIGlassEffect(style: clearGlass ? .clear : .regular)
            glass.isInteractive = true
            // tintColor: cam'i renkli (stained glass) yapar — liquid efekt korunur.
            if let argb = tintArgb {
                glass.tintColor = UIColor(argb: argb)
            }
            _blurView = FadingVisualEffectView(effect: glass)
        } else {
            let blurEffect = UIBlurEffect(style: blurStyle)
            _blurView = FadingVisualEffectView(effect: blurEffect)
        }
        _blurView.frame = frame
        _blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Gradient fade: opak (ust) -> seffaf (alt). Maske DOGRUDAN effect
        // view'a uygulanir (superview'a degil) ki blur sample edebilsin.
        // Maske frame'i FadingVisualEffectView.layoutSubviews ile takip edilir.
        if fadeBottom {
            let gradient = CAGradientLayer()
            gradient.colors = [UIColor.white.cgColor, UIColor.clear.cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
            gradient.frame = _blurView.bounds
            _blurView.layer.mask = gradient
        }

        // Glass shape: UIGlassEffect ignores layer.cornerRadius; the rounded
        // shape (and its edge lensing) must come from cornerConfiguration.
        if useGlass, #available(iOS 26.0, *) {
            _blurView.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
        }

        // Apply Flutter's brightness override
        if #available(iOS 13.0, *) {
            _blurView.overrideUserInterfaceStyle = isDark ? .dark : .light
        }

        // Setup method channel
        _channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_blur_view_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        // Setup method channel handler
        _channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _blurView
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateBlurStyle":
            // Glass views keep their UIGlassEffect; blurStyle only drives the
            // classic UIBlurEffect fallback. Don't overwrite glass with a plain blur.
            if useGlass {
                result(nil)
                return
            }
            if let args = call.arguments as? [String: Any],
               let styleString = args["blurStyle"] as? String {
                let blurStyle = iOS26BlurViewPlatformView.parseBlurStyle(styleString)
                let blurEffect = UIBlurEffect(style: blurStyle)
                _blurView.effect = blurEffect
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            }
        case "setBrightness":
            if let args = call.arguments as? [String: Any],
               let dark = args["isDark"] as? Bool {
                isDark = dark
                if #available(iOS 13.0, *) {
                    _blurView.overrideUserInterfaceStyle = dark ? .dark : .light
                }
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Parse blur style string to UIBlurEffect.Style
    private static func parseBlurStyle(_ styleString: String) -> UIBlurEffect.Style {
        switch styleString {
        case "systemUltraThinMaterial":
            if #available(iOS 13.0, *) {
                return .systemUltraThinMaterial
            } else {
                return .light
            }
        case "systemThinMaterial":
            if #available(iOS 13.0, *) {
                return .systemThinMaterial
            } else {
                return .light
            }
        case "systemMaterial":
            if #available(iOS 13.0, *) {
                return .systemMaterial
            } else {
                return .light
            }
        case "systemThickMaterial":
            if #available(iOS 13.0, *) {
                return .systemThickMaterial
            } else {
                return .dark
            }
        case "systemChromeMaterial":
            if #available(iOS 13.0, *) {
                return .systemChromeMaterial
            } else {
                return .dark
            }
        default:
            if #available(iOS 13.0, *) {
                return .systemUltraThinMaterial
            } else {
                return .light
            }
        }
    }
}
