import AppKit

#if TESTING
Debug.early()   // --selftest, --probe: dev builds only (tests/Debug.swift)
#endif

// --update-now checks GitHub Releases and installs over this copy without restarting (for testing updates).
if CommandLine.arguments.contains("--update-now") {
    let u = Updater(app: "Hop")
    print("current:", u.current, "· repo:", u.repo.isEmpty ? "none" : u.repo)
    var finished = false
    u.check(install: true, relaunch: false) { finished = true }
    while !finished && RunLoop.main.run(mode: .default, before: .distantFuture) {}
    print("result:", u.state, "·", u.menuTitle)
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var launcher: Launcher!
    var status: NSStatusItem!
    let updater = Updater(app: "Hop")
    lazy var settings = SettingsWindow(launcher: launcher)

    func applicationDidFinishLaunching(_ n: Notification) {
        launcher = Launcher()
        launcher.onConfig = { [weak self] in self?.syncUpdater() }
        // Hotkeys come from ~/.config/hop/config.json on top of the defaults (⌥Space, ⌘Space).
        // ⌘Space only fires once Spotlight's shortcut is turned off.
        launcher.applyConfig()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        updater.onChange = { [weak self] in self?.showUpdate() }
        launcher.onUpdate = { [weak self] in self?.updater.check(install: true) }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: launcher.panel,
                                               queue: .main) { [weak self] _ in self?.glint(atMostEvery: 300) }
        showUpdate()
        launcher.onOpenSettings = { [weak self] in self?.settings.present() }

        // --check validates config.json for people and agents: exit 0 when valid, 1 with errors.
        if CommandLine.arguments.contains("--check") {
            launcher.apps.refreshNow()
            let text = FileManager.default.contents(atPath: Config.path).map { String(decoding: $0, as: UTF8.self) }
            let r = ConfigCheck.run(text: text, known: launcher.knownActions())
            print(Config.path)
            for e in r.errors { print("error: " + e) }
            for w in r.warnings { print("warning: " + w) }
            print(r.errors.isEmpty ? "ok: \(r.summary)" + (r.warnings.isEmpty ? "" : " (\(r.warnings.count) warnings)") : "\(r.errors.count) errors")
            exit(r.errors.isEmpty ? 0 : 1)
        }

        // --menu prints the menu-bar menu, feature switches and hotkeys, and quits (for checking without clicking).
        if CommandLine.arguments.contains("--menu") {
            menuNeedsUpdate(menu)
            func dump(_ m: NSMenu, _ indent: String) {
                for i in m.items {
                    if i.isSeparatorItem { print(indent + "──"); continue }
                    print(indent + "  " + i.title + (i.isEnabled ? "" : "  (info)"))
                    if let sub = i.submenu { sub.delegate?.menuNeedsUpdate?(sub); dump(sub, indent + "    ") }
                }
            }
            dump(menu, "")
            print("\nFeatures (Settings › General):")
            for f in Feature.allCases { print((f.isOn ? "  ✓ " : "    ") + f.text.title) }
            print("    Launch at Login: \(System.launchAtLogin ? "on" : "off")")
            print("\nHotkeys (\(launcher.activeHotkeys.count) registered):")
            for (combo, action) in launcher.activeHotkeys.sorted(by: { $0.action < $1.action }) {
                print("  \(HotKeys.symbols(combo))\t\(action == "show" ? "Open Hop" : action)")
            }
            exit(0)
        }

        #if TESTING
        Debug.launched(launcher, settings: settings)   // --show, --query, --snapshot: dev builds only
        #endif
    }

    @objc func open() { launcher.show() }

    func syncUpdater() {
        if Feature.updateChecks.isOn { updater.startChecking() } else { updater.stopChecking() }
    }

    // MARK: update cue: a dot on the menu-bar icon while an update waits, and a short glint now and then

    private let icon = NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: "Hop")
    /// The icon with a small dot at its top-right. Still a template, so it follows the menu bar's colour; padded only
    /// vertically, so the bolt neither moves nor shrinks when the dot appears.
    private lazy var badged: NSImage? = icon.map { base in
        let img = NSImage(size: NSSize(width: base.size.width, height: base.size.height + 4), flipped: false) { r in
            base.draw(in: r.insetBy(dx: 0, dy: 2))
            let d: CGFloat = 4.5, dot = NSRect(x: r.maxX - d, y: r.maxY - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.25, dy: -1.25)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Hop, update available"
        return img
    }
    private var announced: String?
    private var lastGlint = Date.distantPast

    private func showUpdate() {
        let v = updater.pending
        launcher.pendingUpdate = v
        status.button?.image = v == nil ? icon : badged
        if let v, v != announced { announced = v; glint(atMostEvery: 0) }
    }

    /// One light sweep across the icon, in the accent colour and masked to its shape. Core Animation runs it in
    /// the render server and the layer removes itself when done, so nothing ticks between glints.
    private func glint(atMostEvery seconds: TimeInterval) {
        guard updater.pending != nil, Date().timeIntervalSince(lastGlint) >= seconds,
              let b = status.button, let img = b.image else { return }
        lastGlint = Date()
        b.wantsLayer = true
        guard let host = b.layer else { return }
        let scale = b.window?.backingScaleFactor ?? 2
        let mask = CALayer()
        mask.frame = b.bounds
        mask.contentsGravity = .center
        mask.contentsScale = scale
        mask.contents = img.layerContents(forContentsScale: scale)
        let g = CAGradientLayer()
        g.frame = b.bounds
        g.mask = mask
        let c = NSColor.controlAccentColor
        g.colors = [c.withAlphaComponent(0).cgColor, c.cgColor, NSColor.white.cgColor, c.cgColor, c.withAlphaComponent(0).cgColor]
        g.startPoint = CGPoint(x: 0, y: 0.3)
        g.endPoint = CGPoint(x: 1, y: 0.7)
        g.locations = [1, 1.1, 1.15, 1.2, 1.3]   // the end state: band past the right edge, nothing visible
        let a = CABasicAnimation(keyPath: "locations")
        a.fromValue = [-0.3, -0.2, -0.15, -0.1, 0]
        a.duration = 1.2
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { g.removeFromSuperlayer() }
        host.addSublayer(g)
        g.add(a, forKey: "glint")
        CATransaction.commit()
    }

    // MARK: settings menu, rebuilt each time it opens so it always shows the current state

    private var actions: [() -> Void] = []

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        actions = []
        let show = launcher.activeHotkeys.first { $0.action == "show" }.map { "  " + HotKeys.symbols($0.combo) } ?? ""
        add(menu, "Open Hop" + show) { [weak self] in self?.launcher.show() }
        add(menu, "Settings…", key: ",") { [weak self] in self?.settings.present() }
        menu.addItem(.separator())

        let snips = NSMenu()
        for sn in launcher.config.snippets {
            add(snips, sn.name + (sn.keyword.map { "\t\($0)" } ?? ""), tip: sn.text) { [weak self] in
                guard let self else { return }
                Paste.paste(sn.expanded(), self.launcher.clipboard)
            }
        }
        if launcher.config.snippets.isEmpty { add(snips, "No snippets yet", enabled: false) {} }
        snips.addItem(.separator())
        add(snips, "Save Clipboard as Snippet") { [weak self] in if Snippet.saveClipboard() { self?.launcher.applyConfig() } }
        add(snips, "Edit Snippets…") { [weak self] in self?.settings.present(tab: 3) }
        let snipsItem = NSMenuItem(title: "Snippets (\(launcher.config.snippets.count))", action: nil, keyEquivalent: "")
        snipsItem.submenu = snips
        menu.addItem(snipsItem)
        add(menu, "Save Current Page as Bookmark") { [weak self] in
            if Tabs.saveFront() != nil { self?.launcher.applyConfig() } else { NSSound.beep() }
        }
        menu.addItem(.separator())
        // Installs only from here or ⌘U in the panel; otherwise this just checks.
        add(menu, updater.menuTitle, enabled: updater.enabled) { [weak self] in
            guard let u = self?.updater else { return }
            u.check(install: u.pending != nil)
        }
        add(menu, "Quit Hop") { NSApp.terminate(nil) }
    }

    private func add(_ menu: NSMenu, _ title: String, enabled: Bool = true, tip: String? = nil, key: String = "",
                     _ run: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: enabled ? #selector(menuAction(_:)) : nil, keyEquivalent: key)
        item.target = self
        item.tag = actions.count
        item.isEnabled = enabled
        item.toolTip = tip
        actions.append(run)
        menu.addItem(item)
    }

    @objc private func menuAction(_ item: NSMenuItem) {
        guard item.tag < actions.count else { return }
        let run = actions[item.tag]
        // Let the menu close first so pastes land in the app underneath.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: run)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
