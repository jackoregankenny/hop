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

    func applicationDidFinishLaunching(_ n: Notification) {
        launcher = Launcher()
        // Hotkeys come from ~/.config/hop/config.json on top of the defaults (⌥Space, ⌘Space, snapping).
        // ⌘Space only fires once Spotlight's shortcut is turned off.
        launcher.applyConfig()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: "Hop")
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        updater.canRelaunch = { [weak self] in self?.launcher.panel.isVisible == false }
        syncUpdater()
        launcher.onOpenSettings = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.status.button?.performClick(nil) }
        }

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

        // --menu prints the settings menu and quits (for checking it without clicking).
        if CommandLine.arguments.contains("--menu") {
            menuNeedsUpdate(menu)
            func dump(_ m: NSMenu, _ indent: String) {
                for i in m.items {
                    if i.isSeparatorItem { print(indent + "──"); continue }
                    print(indent + (i.state == .on ? "✓ " : "  ") + i.title + (i.isEnabled ? "" : "  (info)"))
                    if let sub = i.submenu { sub.delegate?.menuNeedsUpdate?(sub); dump(sub, indent + "    ") }
                }
            }
            dump(menu, "")
            exit(0)
        }

        #if TESTING
        Debug.launched(launcher)   // --show, --query, --snapshot: dev builds only
        #endif
    }

    @objc func open() { launcher.show() }

    func syncUpdater() {
        if Feature.automaticUpdates.isOn { updater.startAutomatic() } else { updater.stopAutomatic() }
    }

    // MARK: settings menu, rebuilt each time it opens so it always shows the current state

    private var actions: [() -> Void] = []

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        actions = []
        let show = launcher.activeHotkeys.first { $0.action == "show" }.map { "  " + HotKeys.symbols($0.combo) } ?? ""
        add(menu, "Open Hop" + show) { [weak self] in self?.launcher.show() }
        menu.addItem(.separator())

        for f in Feature.allCases {
            add(menu, f.title, on: f.isOn, tip: f.detail) { [weak self] in
                f.isOn.toggle()
                self?.launcher.applyConfig()   // re-registers hotkeys and starts/stops the clipboard
                self?.syncUpdater()
            }
        }
        add(menu, "Launch at Login", on: System.launchAtLogin) { System.launchAtLogin.toggle() }
        menu.addItem(.separator())

        let keys = NSMenu()
        for (combo, action) in launcher.activeHotkeys.sorted(by: { $0.action < $1.action }) {
            add(keys, "\(HotKeys.symbols(combo))\t\(action == "show" ? "Open Hop" : action)", enabled: false) {}
        }
        if launcher.activeHotkeys.isEmpty { add(keys, "No hotkeys", enabled: false) {} }
        keys.addItem(.separator())
        add(keys, "Edit Hotkeys…") { Config.edit() }
        submenu(menu, "Hotkeys (\(launcher.activeHotkeys.count))", keys)

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
        add(snips, "Edit Snippets…") { Config.edit() }
        submenu(menu, "Snippets (\(launcher.config.snippets.count))", snips)

        add(menu, "Open Scripts Folder") {
            try? FileManager.default.createDirectory(atPath: Config.scriptsDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.scriptsDir))
        }
        add(menu, "Reload Config") { [weak self] in self?.launcher.applyConfig() }
        menu.addItem(.separator())
        add(menu, updater.menuTitle, enabled: updater.enabled) { [weak self] in self?.updater.check(install: true) }
        add(menu, "Quit Hop") { NSApp.terminate(nil) }
    }

    private func add(_ menu: NSMenu, _ title: String, on: Bool = false, enabled: Bool = true, tip: String? = nil,
                     _ run: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: enabled ? #selector(menuAction(_:)) : nil, keyEquivalent: "")
        item.target = self
        item.tag = actions.count
        item.state = on ? .on : .off
        item.isEnabled = enabled
        item.toolTip = tip
        actions.append(run)
        menu.addItem(item)
    }

    private func submenu(_ menu: NSMenu, _ title: String, _ sub: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
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
