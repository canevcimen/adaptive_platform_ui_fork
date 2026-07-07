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

/// Blur view'i barindiran container. Ilk gercek layout'tan (ekranda + gecerli
/// bounds) sonra [onReady]'i bir sonraki runloop'ta cagirir — boylece freeze
/// kararini veren taraf, blur view ekranda olusmadan dondurup bos snapshot
/// uretmesin (defense-in-depth).
final class BlurContainerView: UIView {
    var onReady: (() -> Void)?
    private var _notified = false

    override func layoutSubviews() {
        super.layoutSubviews()
        // Gradient fade maskesi (varsa) container ile birlikte boyutlanir.
        layer.mask?.frame = bounds
        if !_notified, window != nil, bounds.width > 0, bounds.height > 0 {
            _notified = true
            // Bir sonraki runloop: effect view backdrop'u ornekleyecek zamani bulur.
            DispatchQueue.main.async { [weak self] in self?.onReady?() }
        }
    }
}

/// Stacked UIVisualEffectView'lerle DEGISKEN (progressive) blur — Instagram sheet
/// basligindaki "asagi dogru kademeli erime". Tek UIBlurEffect sabit guctedir; bu
/// yuzden ayni blur'u N katman halinde ust uste koyar, her katmana KAYDIRILMIS
/// gradient maske uygular: ust bolge [0..bandStart] tum katmanlarla TAM blur; alt
/// band [bandStart..1] icinde katmanlar SIRAYLA soner -> blur VE frost tonu birlikte
/// kademeli azalir, icerik yumusakca netlesir (alpha sicramasi yok).
final class ProgressiveBlurView: UIView {
    private var blurLayers: [UIVisualEffectView] = []
    private let style: UIBlurEffect.Style
    private let bandStart: CGFloat

    init(style: UIBlurEffect.Style, layerCount: Int, bandStart: CGFloat) {
        self.style = style
        self.bandStart = max(0.0, min(0.95, bandStart))
        super.init(frame: .zero)
        for _ in 0..<max(2, layerCount) {
            let v = UIVisualEffectView(effect: UIBlurEffect(style: style))
            v.isUserInteractionEnabled = false
            addSubview(v)
            blurLayers.append(v)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let n = CGFloat(blurLayers.count)
        let seg = (1.0 - bandStart) / n
        for (i, v) in blurLayers.enumerated() {
            v.frame = bounds
            // Katman i: [0..solidEnd] opak, [solidEnd..clearAt] soner. i arttikca
            // band asagi iner -> ustte tum katmanlar ortusur (max blur), bandStart
            // altinda katmanlar birer birer cikar -> blur kademeli azalir.
            let solidEnd = bandStart + CGFloat(i) * seg
            let clearAt = bandStart + CGFloat(i + 1) * seg
            let mask = (v.layer.mask as? CAGradientLayer) ?? CAGradientLayer()
            mask.frame = bounds
            mask.startPoint = CGPoint(x: 0.5, y: 0.0)
            mask.endPoint = CGPoint(x: 0.5, y: 1.0)
            mask.colors = [
                UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor,
            ]
            mask.locations = [
                NSNumber(value: 0.0),
                NSNumber(value: Double(solidEnd)),
                NSNumber(value: Double(clearAt)),
            ]
            v.layer.mask = mask
        }
    }

    func setEffectsEnabled(_ enabled: Bool) {
        for v in blurLayers {
            v.effect = enabled ? UIBlurEffect(style: style) : nil
        }
    }

    func setBrightness(dark: Bool) {
        if #available(iOS 13.0, *) {
            for v in blurLayers {
                v.overrideUserInterfaceStyle = dark ? .dark : .light
            }
        }
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
    // fadeBottom gradient'inin opak kaldigi ust oran (0..1). 0 -> tepeden lineer
    // soner (varsayilan/feed). >0 -> ust bu orana kadar TAM opak, sadece alt kenar
    // soner (Instagram sheet basligi gibi solid bar).
    private var fadeStart: Double = 0
    private var cornerRadius: CGFloat = 0
    private var tintArgb: Int?
    // Interactive basma glow'u view.tintColor'i kullanir (UIKit default:
    // systemBlue). Dart 'interactiveTintColor' ile ezilir (or. notr beyaz).
    // tintArgb'den farkli: cami BOYAMAZ, yalniz dokunma parlamasini renklendirir.
    // NOT: cihazda glow renginin tintColor'la ezilemedigi goruldu — rengi
    // garanti kontrol icin 'interactiveGlass' ile kapatip feedback'i Flutter'a ver.
    private var interactiveTintArgb: Int?
    // UIGlassEffect.isInteractive: sistemin dokunma shimmer/glow'u. false ->
    // cam statik kalir, basma feedback'ini Flutter tarafi (InkWell) verir.
    private var interactiveGlass: Bool = true

    // Snapshot-freeze: route transition sirasinda canli blur'u durdurup o anki
    // gorunumun statik snapshot'ini gosterir (her kare backdrop ornekleme maliyeti
    // kalkar -> push slide jank'i olcumu). _container blur + snapshot'i barindirir.
    private let _container = BlurContainerView()
    private var _savedEffect: UIVisualEffect?
    private var _snapshot: UIView?
    private var _frozen = false
    // Ilk gercek layout/render tamamlandi mi — render olmadan freeze edilip bos
    // snapshot uretilmesini onler (cagiranin zamanlamasindan bagimsiz koruma).
    private var _hasRendered = false

    // Progressive (degisken) blur modu: tek _blurView yerine katmanli
    // ProgressiveBlurView kullanilir (Instagram tarzi kademeli erime). Yalniz
    // !useGlass + progressiveBlur=true iken. nil ise klasik tek-katman blur.
    private var progressiveBlur: Bool = false
    private var _progressive: ProgressiveBlurView?

    // Freeze/brightness icin aktif effect view (progressive ise o, degilse _blurView).
    private var _activeEffectView: UIView { _progressive ?? _blurView }

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
            fadeStart = params["fadeStart"] as? Double ?? 0
            progressiveBlur = params["progressiveBlur"] as? Bool ?? false
            tintArgb = params["tintColor"] as? Int
            interactiveTintArgb = params["interactiveTintColor"] as? Int
            interactiveGlass = params["interactiveGlass"] as? Bool ?? true
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
            glass.isInteractive = interactiveGlass
            // tintColor: cam'i renkli (stained glass) yapar — liquid efekt korunur.
            if let argb = tintArgb {
                glass.tintColor = UIColor(argb: argb)
            }
            _blurView = FadingVisualEffectView(effect: glass)
        } else {
            let blurEffect = UIBlurEffect(style: blurStyle)
            _blurView = FadingVisualEffectView(effect: blurEffect)
        }
        // Interactive glow rengi (yalniz glass modda anlamli; blur modda zararsiz).
        if useGlass, let argb = interactiveTintArgb {
            _blurView.tintColor = UIColor(argb: argb)
        }
        _blurView.frame = frame
        _blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

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

        // Blur view'i bir container'a koy: freeze'de uzerine statik snapshot
        // eklenir (UIVisualEffectView'a dogrudan subview eklenmez, contentView
        // gerekir; container bu sorunu temizce cozer).
        _container.frame = frame
        // Gradient fade CONTAINER'a uygulanir: effect view'in kendi layer.mask'i
        // UIGlassEffect'te calismiyor; plain UIView olan container'i maskelemek hem
        // blur hem glass'i (ve freeze snapshot'ini) guvenle alta dogru saydamlastirir.
        if fadeBottom {
            let gradient = CAGradientLayer()
            if fadeStart > 0 {
                gradient.colors = [
                    UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor,
                ]
                gradient.locations = [
                    NSNumber(value: 0.0), NSNumber(value: fadeStart), NSNumber(value: 1.0),
                ]
            } else {
                // Tepeden lineer soner (liquid ust tam -> alta dogru erir).
                gradient.colors = [UIColor.white.cgColor, UIColor.clear.cgColor]
            }
            gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
            gradient.frame = _container.bounds
            _container.layer.mask = gradient
        }
        if progressiveBlur, !useGlass {
            // Progressive (degisken) blur: Instagram tarzi kademeli erime. Per-katman
            // base ULTRA-THIN (acik); N katman ust uste binince ust bolge orta-guclu
            // frost olur, alt band'de katmanlar sirayla cikar -> yumusak ramp.
            // bandStart: fadeStart (yoksa 0.6). Bunlar gorsel tuning knob'lari.
            let pv = ProgressiveBlurView(
                style: .systemUltraThinMaterial,
                layerCount: 4,
                bandStart: CGFloat(fadeStart > 0 ? fadeStart : 0.6)
            )
            pv.frame = _container.bounds
            pv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            pv.setBrightness(dark: isDark)
            _container.addSubview(pv)
            _progressive = pv
        } else {
            _blurView.frame = _container.bounds
            _blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            _container.addSubview(_blurView)
            _savedEffect = _blurView.effect
        }
        _container.onReady = { [weak self] in self?._hasRendered = true }

        // Setup method channel handler
        _channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _container
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
                if let pv = _progressive {
                    pv.setBrightness(dark: dark)
                } else if #available(iOS 13.0, *) {
                    _blurView.overrideUserInterfaceStyle = dark ? .dark : .light
                }
            }
            result(nil)
        case "setFrozen":
            if let args = call.arguments as? [String: Any],
               let frozen = args["frozen"] as? Bool {
                applyFrozen(frozen)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Transition sirasinda (frozen=true) canli blur'u durdurup o anki gorunumun
    /// statik snapshot'ini gosterir; bitince (false) canli efekti geri verir.
    /// Amac: slide boyunca her kare backdrop yeniden ornekleme maliyetini kaldirip
    /// platform view'i ucuz statik bir katmana indirgemek.
    private func applyFrozen(_ frozen: Bool) {
        if frozen {
            if _snapshot != nil { return } // zaten dondurulmus
            // Guvenlik: view henuz ekranda render etmediyse dondurma -> bos snapshot
            // riskini sifirlar (defense-in-depth).
            guard _hasRendered, _activeEffectView.window != nil else { return }
            guard let snap = _activeEffectView.snapshotView(afterScreenUpdates: false)
            else { return }
            snap.frame = _container.bounds
            snap.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            _container.addSubview(snap)
            _snapshot = snap
            // Canli efekti durdur (pahali kisim) — progressive ise tum katmanlar.
            UIView.performWithoutAnimation {
                if let pv = _progressive {
                    pv.setEffectsEnabled(false)
                } else {
                    _blurView.effect = nil
                }
            }
        } else {
            guard let snap = _snapshot else { return } // zaten canli
            _snapshot = nil
            // Canli efekti geri ver; backdrop 1-2 karede yerlesir. Snapshot'i kisa
            // fade ile kaldir -> snapshot'tan canliya yumusak gecis (pop-in yok).
            UIView.performWithoutAnimation {
                if let pv = _progressive {
                    pv.setEffectsEnabled(true)
                } else {
                    _blurView.effect = _savedEffect
                }
            }
            UIView.animate(withDuration: 0.18, animations: {
                snap.alpha = 0
            }, completion: { _ in
                snap.removeFromSuperview()
            })
        }
        _frozen = frozen
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
