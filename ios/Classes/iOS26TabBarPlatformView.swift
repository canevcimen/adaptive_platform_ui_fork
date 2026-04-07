import Flutter
import UIKit

class iOS26TabBarPlatformView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
    private let channel: FlutterMethodChannel
    private let container: UIView
    private var tabBarController: UITabBarController?
    private var tabBar: UITabBar? { tabBarController?.tabBar }
    private var minimizeBehavior: Int = 3 // automatic
    private var currentLabels: [String] = []
    private var currentSymbols: [String] = []
    private var currentSelectedSymbols: [String] = []
    private var currentSearchFlags: [Bool] = []
    private var currentBadgeCounts: [Int?] = []

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_tab_bar_\(viewId)",
            binaryMessenger: messenger
        )
        self.container = UIView(frame: frame)

        var labels: [String] = []
        var symbols: [String] = []
        var selectedSymbols: [String] = []
        var searchFlags: [Bool] = []
        var badgeCounts: [Int?] = []
        var spacerFlags: [Bool] = []
        var selectedIndex: Int = 0
        var isDark: Bool = false
        var tint: UIColor? = nil
        var bg: UIColor? = nil
        var minimize: Int = 3 // automatic

        var unselectedTint: UIColor? = nil

        if let dict = args as? [String: Any] {
            NSLog("📦 TabBar init dict keys: \(dict.keys)")
            NSLog("📦 selectedSfSymbols: \(dict["selectedSfSymbols"] ?? "NOT FOUND")")
            labels = (dict["labels"] as? [String]) ?? []
            symbols = (dict["sfSymbols"] as? [String]) ?? []
            selectedSymbols = (dict["selectedSfSymbols"] as? [String]) ?? []
            searchFlags = (dict["searchFlags"] as? [Bool]) ?? []
            spacerFlags = (dict["spacerFlags"] as? [Bool]) ?? []
            if let badgeData = dict["badgeCounts"] as? [NSNumber?] {
                badgeCounts = badgeData.map { $0?.intValue }
            }
            if let v = dict["selectedIndex"] as? NSNumber { selectedIndex = v.intValue }
            if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
            if let n = dict["tint"] as? NSNumber { tint = Self.colorFromARGB(n.intValue) }
            if let n = dict["unselectedItemTint"] as? NSNumber {
                unselectedTint = Self.colorFromARGB(n.intValue)
                NSLog("🎨 Parsed unselectedItemTint from dict: \(unselectedTint!)")
            }
            if let n = dict["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(n.intValue) }
            if let m = dict["minimizeBehavior"] as? NSNumber { minimize = m.intValue }
        }

        self.currentLabels = labels
        self.currentSymbols = symbols
        self.currentSelectedSymbols = selectedSymbols

        super.init()

        container.backgroundColor = .clear
        if #available(iOS 13.0, *) {
            container.overrideUserInterfaceStyle = isDark ? .dark : .light
        }


        // Use UITabBarController for proper iOS 26 Liquid Glass rendering
        let tbc = UITabBarController()
        tabBarController = tbc
        tbc.delegate = self
        tbc.view.translatesAutoresizingMaskIntoConstraints = false
        let bar = tbc.tabBar

        // iOS 26+ — native Liquid Glass with default material
        if #available(iOS 26.0, *) {
            bar.isTranslucent = true
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            NSLog("📱 iOS 26+ detected - UITabBarController with default appearance")
        }
        // iOS 13-25 - Use appearance
        else if #available(iOS 13.0, *) {
            let appearance = UITabBarAppearance()

            // Make transparent
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear

            // Set colors directly on the appearance layouts
            let unselColor = unselectedTint ?? UIColor.systemGray
            let selColor = tint ?? UIColor.systemBlue

            // Normal (unselected) items
            appearance.stackedLayoutAppearance.normal.iconColor = unselColor
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselColor]
            appearance.inlineLayoutAppearance.normal.iconColor = unselColor
            appearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselColor]
            appearance.compactInlineLayoutAppearance.normal.iconColor = unselColor
            appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselColor]

            // Selected items
            appearance.stackedLayoutAppearance.selected.iconColor = selColor
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selColor]
            appearance.inlineLayoutAppearance.selected.iconColor = selColor
            appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selColor]
            appearance.compactInlineLayoutAppearance.selected.iconColor = selColor
            appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selColor]

            bar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                bar.scrollEdgeAppearance = appearance
            }

            NSLog("🎨 iOS 13-25: Applied appearance - normal: \(unselColor), selected: \(selColor)")
        } else {
            // iOS 10-12 fallback
            bar.isTranslucent = true
            bar.backgroundImage = UIImage()
            bar.shadowImage = UIImage()
            bar.backgroundColor = .clear
        }

        // Also set direct properties as fallback
        if #available(iOS 10.0, *) {
            if let unselTint = unselectedTint {
                bar.unselectedItemTintColor = unselTint
                NSLog("✅ Direct unselectedItemTintColor: \(unselTint)")
            }
            if let tint = tint {
                bar.tintColor = tint
                NSLog("✅ Direct tintColor: \(tint)")
            }
        }

        if let bg = bg { bar.barTintColor = bg }

        // Build tab bar items
        func buildItems(_ range: Range<Int>) -> [UITabBarItem] {
            var items: [UITabBarItem] = []
            for i in range {
                let title = (i < labels.count) ? labels[i] : nil
                let isSearch = (i < searchFlags.count) && searchFlags[i]
                let badgeCount = (i < badgeCounts.count) ? badgeCounts[i] : nil

                let item: UITabBarItem

                // Use UITabBarSystemItem.search for search tabs (iOS 26+ Liquid Glass)
                if isSearch {
                    if #available(iOS 26.0, *) {
                        item = UITabBarItem(tabBarSystemItem: .search, tag: i)
                        if let title = title {
                            item.title = title
                        }

                    } else {
                        // Fallback for older iOS versions
                        let searchImage = UIImage(systemName: "magnifyingglass")
                        item = UITabBarItem(title: title, image: searchImage, selectedImage: searchImage)
                    }
                } else {
                    var image: UIImage? = nil
                    var selectedImage: UIImage? = nil

                    if i < symbols.count && !symbols[i].isEmpty {
                        let selSymbol = (i < selectedSymbols.count && !selectedSymbols[i].isEmpty) ? selectedSymbols[i] : symbols[i]
                        NSLog("🔵 Tab \(i): icon=\(symbols[i]), selectedIcon=\(selSymbol)")

                        if #available(iOS 26.0, *) {
                            if let unselTint = unselectedTint {
                                if let originalImage = Self.loadIcon(symbols[i], renderingMode: .alwaysOriginal) {
                                    image = originalImage.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                }
                            } else {
                                image = Self.loadIcon(symbols[i])
                            }
                            selectedImage = Self.loadIcon(selSymbol)
                        } else {
                            image = Self.loadIcon(symbols[i])
                            selectedImage = Self.loadIcon(selSymbol)
                        }
                    }

                    // Create item with title
                    item = UITabBarItem(title: title ?? "Tab \(i+1)", image: image, selectedImage: selectedImage)
                    item.tag = i
                }

                // Set badge value if provided
                if let count = badgeCount, count > 0 {
                    item.badgeValue = count > 99 ? "99+" : String(count)
                } else {
                    item.badgeValue = nil
                }

                items.append(item)
            }
            return items
        }

        let count = max(labels.count, symbols.count)
        let tabItems = buildItems(0..<count)

        // UITabBarController needs viewControllers — create empty VCs with tab bar items
        var viewControllers: [UIViewController] = []
        for item in tabItems {
            let vc = UIViewController()
            vc.tabBarItem = item
            vc.view.backgroundColor = .clear
            viewControllers.append(vc)
        }
        tbc.viewControllers = viewControllers

        if selectedIndex >= 0 && selectedIndex < viewControllers.count {
            tbc.selectedIndex = selectedIndex
        }

        // Only show tab bar, hide VC content area
        tbc.view.backgroundColor = .clear
        for vc in viewControllers {
            vc.view.isHidden = true
        }

        container.addSubview(tbc.view)
        NSLayoutConstraint.activate([
            tbc.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tbc.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tbc.view.topAnchor.constraint(equalTo: container.topAnchor),
            tbc.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.minimizeBehavior = minimize
        self.currentLabels = labels
        self.currentSymbols = symbols
        self.currentSearchFlags = searchFlags
        self.currentBadgeCounts = badgeCounts

        // Apply minimize behavior if available
        self.applyMinimizeBehavior()

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            self.handleMethodCall(call, result: result)
        }
    }

    private func applyMinimizeBehavior() {
        // Note: UITabBarController.tabBarMinimizeBehavior is the official iOS 26+ API
        // However, since we're using a standalone UITabBar in a platform view,
        // we need to implement custom minimize behavior
        //
        // The minimize behavior should be controlled at the Flutter level
        // by adjusting the tab bar's height/visibility based on scroll events
        //
        // This method stores the behavior preference for future use
        // The actual minimization animation should be handled by Flutter
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getIntrinsicSize":
            if let bar = self.tabBar {
                let size = bar.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                result(["width": Double(size.width), "height": Double(size.height)])
            } else {
                result(["width": Double(self.container.bounds.width), "height": 50.0])
            }

        case "setItems":
            guard let args = call.arguments as? [String: Any],
                  let labels = args["labels"] as? [String],
                  let symbols = args["sfSymbols"] as? [String] else {
                result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
                return
            }

            let selectedSymbols = (args["selectedSfSymbols"] as? [String]) ?? []
            let searchFlags = (args["searchFlags"] as? [Bool]) ?? []
            let selectedIndex = (args["selectedIndex"] as? NSNumber)?.intValue ?? 0
            var badgeCounts: [Int?] = []
            if let badgeData = args["badgeCounts"] as? [NSNumber?] {
                badgeCounts = badgeData.map { $0?.intValue }
            }

            self.currentLabels = labels
            self.currentSymbols = symbols
            self.currentSelectedSymbols = selectedSymbols
            self.currentSearchFlags = searchFlags
            self.currentBadgeCounts = badgeCounts

            let count = max(labels.count, symbols.count)

            // Reuse the same buildItems function with rendering mode logic
            let buildItems: (Range<Int>) -> [UITabBarItem] = { range in
                var items: [UITabBarItem] = []
                for i in range {
                    let title = (i < labels.count) ? labels[i] : nil
                    let isSearch = (i < searchFlags.count) && searchFlags[i]
                    let badgeCount = (i < badgeCounts.count) ? badgeCounts[i] : nil

                    let item: UITabBarItem

                    // Use UITabBarSystemItem.search for search tabs (iOS 26+ Liquid Glass)
                    if isSearch {
                        if #available(iOS 26.0, *) {
                            item = UITabBarItem(tabBarSystemItem: .search, tag: i)
                            if let title = title {
                                item.title = title
                            }

                        } else {
                            // Fallback for older iOS versions
                            let searchImage = UIImage(systemName: "magnifyingglass")
                            item = UITabBarItem(title: title, image: searchImage, selectedImage: searchImage)
                        }
                    } else {
                        var image: UIImage? = nil
                        var selectedImage: UIImage? = nil

                        if i < symbols.count && !symbols[i].isEmpty {
                            let selSymbol = (i < selectedSymbols.count && !selectedSymbols[i].isEmpty) ? selectedSymbols[i] : symbols[i]

                            if #available(iOS 26.0, *) {
                                let unselTint = self.tabBar?.unselectedItemTintColor
                                if let unselTint = unselTint {
                                    if let originalImage = Self.loadIcon(symbols[i], renderingMode: .alwaysOriginal) {
                                        image = originalImage.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                                    }
                                } else {
                                    image = Self.loadIcon(symbols[i])
                                }
                                selectedImage = Self.loadIcon(selSymbol)
                            } else {
                                image = Self.loadIcon(symbols[i])
                                selectedImage = Self.loadIcon(selSymbol)
                            }
                        }

                        // Create item with title
                        item = UITabBarItem(title: title ?? "Tab \(i+1)", image: image, selectedImage: selectedImage)
                        item.tag = i
                    }

                    // Set badge value if provided
                    if let count = badgeCount, count > 0 {
                        item.badgeValue = count > 99 ? "99+" : String(count)
                    } else {
                        item.badgeValue = nil
                    }

                    items.append(item)
                }
                return items
            }

            if let tbc = self.tabBarController {
                let tabItems = buildItems(0..<count)
                var viewControllers: [UIViewController] = []
                for item in tabItems {
                    let vc = UIViewController()
                    vc.tabBarItem = item
                    vc.view.backgroundColor = .clear
                    vc.view.isHidden = true
                    viewControllers.append(vc)
                }
                tbc.viewControllers = viewControllers
                if selectedIndex >= 0 && selectedIndex < viewControllers.count {
                    tbc.selectedIndex = selectedIndex
                }
            }
            result(nil)

        case "setSelectedIndex":
            guard let args = call.arguments as? [String: Any],
                  let idx = (args["index"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "bad_args", message: "Invalid index", details: nil))
                return
            }

            if let tbc = self.tabBarController, let vcs = tbc.viewControllers, idx >= 0, idx < vcs.count {
                tbc.selectedIndex = idx
            }
            result(nil)

        case "setStyle":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_args", message: "Missing style", details: nil))
                return
            }

            var tintColor: UIColor? = nil
            var unselectedColor: UIColor? = nil

            if let n = args["tint"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                self.tabBar?.tintColor = c
                tintColor = c
            }
            if let n = args["unselectedItemTint"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                if #available(iOS 10.0, *) {
                    self.tabBar?.unselectedItemTintColor = c
                    NSLog("✅ setStyle: unselectedItemTintColor set to \(c)")

                    // iOS 26+: Rebuild items with new unselected color
                    if #available(iOS 26.0, *) {
                        self.rebuildItemsWithCurrentColors()
                    }
                }
                unselectedColor = c
            }
            if let n = args["backgroundColor"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                self.tabBar?.barTintColor = c
            }

            result(nil)

        case "setBrightness":
            guard let args = call.arguments as? [String: Any],
                  let isDark = (args["isDark"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
                return
            }

            if #available(iOS 13.0, *) {
                self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
            }
            result(nil)

        case "setMinimizeBehavior":
            guard let args = call.arguments as? [String: Any],
                  let behavior = (args["behavior"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "bad_args", message: "Missing behavior", details: nil))
                return
            }

            self.minimizeBehavior = behavior
            self.applyMinimizeBehavior()
            result(nil)

        case "setBadgeCounts":
            guard let args = call.arguments as? [String: Any],
                  let badgeData = args["badgeCounts"] as? [NSNumber?] else {
                result(FlutterError(code: "bad_args", message: "Missing badge counts", details: nil))
                return
            }

            let badgeCounts = badgeData.map { $0?.intValue }
            self.currentBadgeCounts = badgeCounts

            // Update existing tab bar items with new badge values
            if let bar = self.tabBar, let items = bar.items {
                for (index, item) in items.enumerated() {
                    if index < badgeCounts.count {
                        let count = badgeCounts[index]
                        if let count = count, count > 0 {
                            item.badgeValue = count > 99 ? "99+" : String(count)
                        } else {
                            item.badgeValue = nil
                        }
                    }
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // iOS 26+: Rebuild tab items with current colors
    private func rebuildItemsWithCurrentColors() {
        guard let bar = self.tabBar else { return }

        let currentSelectedIndex = bar.items?.firstIndex { $0 == bar.selectedItem } ?? 0
        let unselTint = bar.unselectedItemTintColor

        // Rebuild items with new colors
        var items: [UITabBarItem] = []
        for i in 0..<currentLabels.count {
            let title = currentLabels[i]
            let isSearch = (i < currentSearchFlags.count) && currentSearchFlags[i]
            let badgeCount = (i < currentBadgeCounts.count) ? currentBadgeCounts[i] : nil

            let item: UITabBarItem

            if isSearch {
                if #available(iOS 26.0, *) {
                    item = UITabBarItem(tabBarSystemItem: .search, tag: i)
                    item.title = title
                } else {
                    let searchImage = UIImage(systemName: "magnifyingglass")
                    item = UITabBarItem(title: title, image: searchImage, selectedImage: searchImage)
                }
            } else {
                var image: UIImage? = nil
                var selectedImage: UIImage? = nil

                if i < currentSymbols.count && !currentSymbols[i].isEmpty {
                    let selSymbol = (i < currentSelectedSymbols.count && !currentSelectedSymbols[i].isEmpty) ? currentSelectedSymbols[i] : currentSymbols[i]

                    if #available(iOS 26.0, *) {
                        if let unselTint = unselTint {
                            if let originalImage = Self.loadIcon(currentSymbols[i], renderingMode: .alwaysOriginal) {
                                image = originalImage.withTintColor(unselTint, renderingMode: .alwaysOriginal)
                            }
                        } else {
                            image = Self.loadIcon(currentSymbols[i])
                        }
                        selectedImage = Self.loadIcon(selSymbol)
                    } else {
                        image = Self.loadIcon(currentSymbols[i])
                        selectedImage = Self.loadIcon(selSymbol)
                    }
                }

                item = UITabBarItem(title: title, image: image, selectedImage: selectedImage)
                item.tag = i
            }

            // Set badge value if provided
            if let count = badgeCount, count > 0 {
                item.badgeValue = count > 99 ? "99+" : String(count)
            }

            items.append(item)
        }

        if let tbc = self.tabBarController {
            var viewControllers: [UIViewController] = []
            for item in items {
                let vc = UIViewController()
                vc.tabBarItem = item
                vc.view.backgroundColor = .clear
                vc.view.isHidden = true
                viewControllers.append(vc)
            }
            tbc.viewControllers = viewControllers
            if currentSelectedIndex < viewControllers.count {
                tbc.selectedIndex = currentSelectedIndex
            }
        }
    }

    /// SF Symbol veya custom asset'ten UIImage yükler.
    /// "house.fill" gibi SF Symbol isimleri → UIImage(systemName:)
    /// "tab_home_active" gibi asset isimleri → UIImage(named:)
    private static func loadIcon(_ name: String, renderingMode: UIImage.RenderingMode = .alwaysTemplate) -> UIImage? {
        // Önce SF Symbol dene
        if let sfImage = UIImage(systemName: name) {
            return sfImage.withRenderingMode(renderingMode)
        }
        // SF Symbol bulunamazsa asset'ten yükle
        if let assetImage = UIImage(named: name) {
            return assetImage.withRenderingMode(renderingMode)
        }
        NSLog("⚠️ Icon not found: \(name)")
        return nil
    }

    func view() -> UIView { container }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let idx = tabBarController.viewControllers?.firstIndex(of: viewController) {
            channel.invokeMethod("valueChanged", arguments: ["index": idx])
        }
    }

    private static func colorFromARGB(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

class iOS26TabBarViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26TabBarPlatformView(
            frame: frame,
            viewId: viewId,
            args: args,
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
