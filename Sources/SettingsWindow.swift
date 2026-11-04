import AppKit
import Carbon.HIToolbox

/// Hop Settings: a face on config.json and the feature switches. Every edit is written to the file
/// as you make it, so the file stays the one source of truth for people and agents alike.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let launcher: Launcher
    private var panes: [ListPane] = []
    private let general: GeneralPane

    init(launcher: Launcher) {
        self.launcher = launcher
        general = GeneralPane(launcher: launcher)
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        super.init(window: nil)

        let hotkeys = ListPane(columns: [.init(key: "combo", title: "Shortcut", width: 150, kind: .shortcut),
                                         .init(key: "action", title: "Action", width: 300, kind: .combo { [launcher] in launcher.actionNames() })],
                               note: "Click a shortcut to record a new one.")
        hotkeys.load = { [launcher] in
            launcher.config.hotkeys.map { ["combo": $0.key, "action": $0.value] }.sorted { ($0["action"]!, $0["combo"]!) < ($1["action"]!, $1["combo"]!) }
        }
        hotkeys.save = { [launcher] rows in
            Config.update("hotkeys") { _ in SettingsWindow.hotkeyChanges(rows) }
            launcher.applyConfig()
        }
        hotkeys.extra = [("Restore Defaults", { [launcher] pane in
            Config.update("hotkeys") { _ in nil }
            launcher.applyConfig()
            pane.reload()
        })]
        hotkeys.recording = { [launcher] on in if on { launcher.suspendHotkeys() } else { launcher.applyConfig() } }
        /// Writes the rows that are complete under `key`, leaving out empty fields.
        func saver(_ key: String, _ complete: @escaping ([String: String]) -> Bool) -> ([[String: String]]) -> Void {
            { [launcher] rows in
                Config.update(key) { _ in rows.filter(complete).map { $0.filter { !$0.value.isEmpty } } }
                launcher.applyConfig()
            }
        }

        let bookmarks = ListPane(columns: [.init(key: "name", title: "Name", width: 190), .init(key: "key", title: "Keyword", width: 80),
                                           .init(key: "url", title: "URL", width: 260)],
                                 note: "Put {query} in a URL to make it a search: type the keyword, a space, then what to search for.")
        bookmarks.load = { [launcher] in launcher.config.quicklinks.map { ["name": $0.name, "key": $0.key ?? "", "url": $0.url] } }
        bookmarks.save = saver("quicklinks") { !($0["name"] ?? "").isEmpty && !($0["url"] ?? "").isEmpty }
        bookmarks.extra = [("Add Current Page", { [launcher] pane in
            if Tabs.saveFront() != nil { launcher.applyConfig(); pane.reload() } else { pane.flash("No new page found in an open browser window") }
        })]

        let snippets = ListPane(columns: [.init(key: "name", title: "Name", width: 260), .init(key: "keyword", title: "Keyword", width: 120)],
                                note: "Placeholders: {date} {time} {datetime} {clipboard}", detail: "text")
        snippets.load = { [launcher] in launcher.config.snippets.map { ["name": $0.name, "keyword": $0.keyword ?? "", "text": $0.text] } }
        snippets.save = saver("snippets") { !($0["text"] ?? "").isEmpty && !(($0["name"] ?? "") + ($0["keyword"] ?? "")).isEmpty }
        snippets.extra = [("Add Clipboard", { [launcher] pane in
            if Snippet.saveClipboard() { launcher.applyConfig(); pane.reload() } else { pane.flash("The clipboard has no text") }
        })]

        panes = [hotkeys, bookmarks, snippets]
        for (vc, label, symbol) in [(general, "General", "gearshape"), (hotkeys, "Hotkeys", "keyboard"),
                                    (bookmarks, "Bookmarks", "bookmark"), (snippets, "Snippets", "text.quote")] as [(NSViewController, String, String)] {
            vc.title = label   // the window takes its title from the selected tab
            let item = NSTabViewItem(viewController: vc)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 620, height: 430))
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w
        SettingsWindow.installEditMenu()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Opens on the given tab (0 General, 1 Hotkeys, 2 Bookmarks, 3 Snippets), showing what config.json holds now.
    func present(tab: Int? = nil, activate: Bool = true) {
        general.reload()
        panes.forEach { $0.reload() }
        if let tab, let tabs = window?.contentViewController as? NSTabViewController { tabs.selectedTabViewItemIndex = tab }
        if window?.isVisible != true { window?.center() }
        if activate { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) } else { window?.orderFrontRegardless() }
    }

    func windowWillClose(_ n: Notification) { window?.makeFirstResponder(nil) }   // commits a field still being edited

    /// What to write under "hotkeys": only the differences from the defaults, so config.json stays short.
    static func hotkeyChanges(_ rows: [[String: String]]) -> [String: String] {
        let rows = rows.compactMap { r -> (combo: String, action: String, key: (Int, Int))? in
            guard let c = r["combo"], let a = r["action"]?.trimmingCharacters(in: .whitespaces), !a.isEmpty,
                  let p = HotKeys.parse(c) else { return nil }
            return (c, a, (p.key, p.mods))
        }
        var out: [String: String] = [:]
        for combo in Config.defaultHotkeys.keys {
            let p = HotKeys.parse(combo)!
            if !rows.contains(where: { $0.key == (p.key, p.mods) }) { out[combo] = "none" }   // a default you removed
        }
        for r in rows {
            let isDefault = Config.defaultHotkeys.contains { k, v in
                HotKeys.parse(k).map { ($0.key, $0.mods) == r.key } == true && v.lowercased() == r.action.lowercased()
            }
            if !isDefault { out[r.combo] = r.action }
        }
        return out
    }

    /// An accessory app has no menu bar, so text fields get ⌘C, ⌘V, ⌘Z and ⌘W only through a main menu.
    private static func installEditMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu(), edit = NSMenu(title: "Edit")
        for (title, sel, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                  ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"), ("Close", "performClose:", "w")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(sel), keyEquivalent: key))
        }
        let item = NSMenuItem()
        item.submenu = edit
        main.addItem(item)
        NSApp.mainMenu = main
    }
}

/// Feature switches, login, theme and the files behind it all.
final class GeneralPane: NSViewController {
    private let launcher: Launcher
    private var boxes: [(Feature, NSButton)] = []
    private let login = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let preset = NSPopUpButton()
    private let appearance = NSPopUpButton()

    init(launcher: Launcher) {
        self.launcher = launcher
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let stack = NSStackView.column([], spacing: 6, insets: NSEdgeInsets(top: 20, left: 28, bottom: 20, right: 28))
        for f in Feature.allCases {
            let b = NSButton(checkboxWithTitle: f.text.title, target: self, action: #selector(toggled(_:)))
            let d = NSTextField(labelWithString: f.text.detail)
            d.textColor = .secondaryLabelColor
            d.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            stack.addArrangedSubview(NSStackView.column([b, d], spacing: 1))
            boxes.append((f, b))
        }
        login.target = self
        login.action = #selector(loginToggled)
        stack.addArrangedSubview(login)
        stack.setCustomSpacing(18, after: login)

        preset.addItems(withTitles: Theme.presets.keys.sorted().map(\.capitalized))
        appearance.addItems(withTitles: ["Auto", "Dark", "Light"])
        for p in [preset, appearance] { p.target = self; p.action = #selector(themeChanged) }
        let theme = NSStackView(views: [NSTextField(labelWithString: "Theme"), preset, NSTextField(labelWithString: "Appearance"), appearance])
        stack.addArrangedSubview(theme)
        stack.setCustomSpacing(18, after: theme)

        stack.addArrangedSubview(NSStackView(views: [button("Open config.json") { Config.edit() },
                                                     button("Open Scripts Folder") { Config.openScripts() }]))
        view = .page(stack, fill: false)   // pinned to the top, not stretched over the whole tab
    }

    func reload() {
        _ = view
        for (f, b) in boxes { b.state = f.isOn ? .on : .off }
        login.state = System.launchAtLogin ? .on : .off
        let t = rawTheme()
        preset.selectItem(withTitle: ((t["preset"] as? String) ?? "default").capitalized)
        appearance.selectItem(withTitle: ((t["appearance"] as? String) ?? "auto").capitalized)
    }

    /// The theme as written in config.json, always as an object.
    private func rawTheme() -> [String: Any] {
        switch Config.raw()?["theme"] {
        case let s as String: return ["preset": s]
        case let d as [String: Any]: return d
        default: return [:]
        }
    }

    @objc private func toggled(_ b: NSButton) {
        guard let f = boxes.first(where: { $0.1 === b })?.0 else { return }
        f.isOn = b.state == .on
        launcher.applyConfig()   // re-registers hotkeys, starts/stops the clipboard and the update checks
    }

    @objc private func loginToggled() {
        System.launchAtLogin = login.state == .on
        login.state = System.launchAtLogin ? .on : .off   // macOS may refuse until Hop is in /Applications
    }

    @objc private func themeChanged() {
        Config.update("theme") { _ in
            var t = rawTheme()
            let p = preset.titleOfSelectedItem?.lowercased() ?? "default", a = appearance.titleOfSelectedItem?.lowercased() ?? "auto"
            t["preset"] = p == "default" ? nil : p
            t["appearance"] = a == "auto" ? nil : a
            return t.count == 1 && t["preset"] != nil ? t["preset"] : t   // a bare preset stays a plain string
        }
        launcher.applyConfig()
    }

    private var handlers: [() -> Void] = []
    private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(pressed(_:)))
        b.tag = handlers.count
        handlers.append(run)
        return b
    }
    @objc private func pressed(_ b: NSButton) { handlers[b.tag]() }
}

/// An editable table of string rows (hotkeys, bookmarks, snippets) with + and − below it and an optional
/// text box for one long field. Each edit calls `save` with every row; `save` keeps only complete ones.
final class ListPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    struct Column {
        enum Kind { case text, combo(() -> [String]), shortcut }
        let key: String, title: String, width: CGFloat
        var kind: Kind = .text
    }

    var load: () -> [[String: String]] = { [] }
    var save: ([[String: String]]) -> Void = { _ in }
    var extra: [(String, (ListPane) -> Void)] = []
    /// Called with true when a shortcut recorder starts listening and false when it stops.
    var recording: (Bool) -> Void = { _ in }

    private let columns: [Column]
    private let note: String
    private let detail: String?
    private var rows: [[String: String]] = []
    private let table = NSTableView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let text = NSTextView()

    init(columns: [Column], note: String, detail: String? = nil) {
        self.columns = columns
        self.note = note
        self.detail = detail
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        for c in columns {
            let col = NSTableColumn(identifier: .init(c.key))
            col.title = c.title
            col.width = c.width
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 24
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let plusMinus = NSSegmentedControl(images: [NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
                                                    NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!],
                                           trackingMode: .momentary, target: self, action: #selector(plusMinus(_:)))
        plusMinus.segmentStyle = .smallSquare
        var bar: [NSView] = [plusMinus]
        for (i, e) in extra.enumerated() {
            let b = NSButton(title: e.0, target: self, action: #selector(extraPressed(_:)))
            b.tag = i
            b.controlSize = .small
            bar.append(b)
        }
        let barStack = NSStackView(views: bar)
        noteLabel.stringValue = note
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        var views: [NSView] = [scroll, barStack]
        if detail != nil {
            text.isRichText = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.delegate = self
            text.isAutomaticQuoteSubstitutionEnabled = false
            text.isAutomaticDashSubstitutionEnabled = false
            text.textContainerInset = NSSize(width: 4, height: 6)
            let ts = NSScrollView()
            ts.documentView = text
            ts.hasVerticalScroller = true
            ts.borderType = .bezelBorder
            text.autoresizingMask = .width
            ts.heightAnchor.constraint(equalToConstant: 110).isActive = true
            views.append(ts)
        }
        views.append(noteLabel)
        let stack = NSStackView.column(views, spacing: 8, insets: NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20))
        for w in views where w !== barStack { w.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
        view = .page(stack, fill: true)
        showDetail()
    }

    func reload() {
        _ = view
        rows = load()
        table.reloadData()
        noteLabel.stringValue = note
        if detail != nil && !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }   // so the text box has something in it
        showDetail()
    }

    /// A short message in place of the note, for a button that had nothing to do.
    func flash(_ message: String) {
        NSSound.beep()
        noteLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self.map { $0.noteLabel.stringValue = $0.note } }
    }

    private func commit() { save(rows) }

    // MARK: table

    func numberOfRows(in t: NSTableView) -> Int { rows.count }

    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col, let i = columns.firstIndex(where: { $0.key == col.identifier.rawValue }) else { return nil }
        let c = columns[i], value = rows[row][c.key] ?? ""
        switch c.kind {
        case .shortcut:
            let r = KeyRecorder()
            r.combo = value
            r.onStart = { [weak self] in self?.recording(true) }
            r.onRecord = { [weak self, weak r] combo in
                guard let self, let r else { return }
                let at = self.table.row(for: r)
                if at >= 0 { self.rows[at][c.key] = combo; self.commit() }
            }
            r.onEnd = { [weak self] in self?.recording(false) }
            return r
        case .combo(let items):
            let box = NSComboBox()
            box.addItems(withObjectValues: items())
            box.completes = true
            box.isBordered = false
            box.drawsBackground = false
            return field(box, value, i)
        case .text:
            let f = NSTextField(string: value)
            f.isBordered = false
            f.drawsBackground = false
            return field(f, value, i)
        }
    }

    private func field(_ f: NSTextField, _ value: String, _ column: Int) -> NSTextField {
        f.stringValue = value
        f.tag = column
        f.target = self
        f.action = #selector(edited(_:))
        f.cell?.sendsActionOnEndEditing = true
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        return f
    }

    @objc private func edited(_ f: NSTextField) {
        let row = table.row(for: f)
        guard row >= 0, row < rows.count, f.tag < columns.count else { return }
        let key = columns[f.tag].key, value = f.stringValue.trimmingCharacters(in: .whitespaces)
        guard rows[row][key, default: ""] != value else { return }
        rows[row][key] = value
        commit()
    }

    func tableViewSelectionDidChange(_ n: Notification) { showDetail() }

    // MARK: detail text

    private func showDetail() {
        guard let detail else { return }
        let sel = table.selectedRowIndexes.count == 1 ? table.selectedRow : -1
        text.isEditable = sel >= 0
        text.string = sel >= 0 ? rows[sel][detail] ?? "" : ""
        text.textColor = .textColor
        text.backgroundColor = sel >= 0 ? .textBackgroundColor : .windowBackgroundColor
    }

    func textDidChange(_ n: Notification) {
        guard let detail, table.selectedRowIndexes.count == 1 else { return }
        rows[table.selectedRow][detail] = text.string
        commit()
    }

    // MARK: buttons

    @objc private func plusMinus(_ s: NSSegmentedControl) {
        view.window?.makeFirstResponder(nil)
        if s.selectedSegment == 0 {
            rows.append([:])
            let r = rows.count - 1
            table.insertRows(at: [r])
            table.selectRowIndexes([r], byExtendingSelection: false)
            table.scrollRowToVisible(r)
            if case .shortcut = columns[0].kind { (table.view(atColumn: 0, row: r, makeIfNecessary: true) as? KeyRecorder)?.start() }
            else { table.editColumn(0, row: r, with: nil, select: true) }
        } else {
            let sel = table.selectedRowIndexes
            guard !sel.isEmpty else { NSSound.beep(); return }
            for i in sel.reversed() { rows.remove(at: i) }
            table.removeRows(at: sel)
            commit()
            showDetail()
        }
    }

    @objc private func extraPressed(_ b: NSButton) {
        view.window?.makeFirstResponder(nil)
        extra[b.tag].1(self)
    }
}

/// Click, then press a key combination. Esc cancels. Needs a modifier unless the key is F1–F6, so a
/// plain letter never ends up swallowed everywhere.
final class KeyRecorder: NSButton {
    var combo = "" { didSet { refresh() } }
    var onStart: (() -> Void)?
    var onRecord: ((String) -> Void)?
    var onEnd: (() -> Void)?
    private var listening = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .inline
        controlSize = .small
        target = self
        action = #selector(start)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    @objc func start() {
        guard !listening else { return }
        listening = true
        refresh()
        window?.makeFirstResponder(self)
        onStart?()   // global hotkeys pause, or they would catch the combo before this sees it
    }

    private func stop() {
        guard listening else { return }
        listening = false
        refresh()
        onEnd?()
    }

    private func refresh() { title = listening ? "Type shortcut…" : combo.isEmpty ? "Record Shortcut" : HotKeys.symbols(combo) }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard listening, window?.firstResponder === self else { return super.performKeyEquivalent(with: e) }
        keyDown(with: e)
        return true
    }

    override func keyDown(with e: NSEvent) {
        guard listening else { return super.keyDown(with: e) }
        let f = e.modifierFlags.intersection([.control, .option, .shift, .command])
        if Int(e.keyCode) == kVK_Escape && f.isEmpty { stop(); return }
        guard let key = HotKeys.name(forKeyCode: Int(e.keyCode)), !f.isEmpty || key.hasPrefix("f") && key.count == 2 else {
            NSSound.beep(); return
        }
        let mods = [(NSEvent.ModifierFlags.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd")]
            .filter { f.contains($0.0) }.map(\.1)
        listening = false
        combo = (mods + [key]).joined(separator: "+")
        onRecord?(combo)
        onEnd?()
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return super.resignFirstResponder()
    }
}

extension NSStackView {
    /// A vertical stack, left-aligned.
    static func column(_ views: [NSView], spacing: CGFloat, insets: NSEdgeInsets = NSEdgeInsets()) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        s.edgeInsets = insets
        return s
    }
}

extension NSView {
    /// A settings tab holding `content` along its top and sides; `fill` stretches it to the bottom too.
    static func page(_ content: NSView, fill: Bool) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 400))
        content.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(content)
        let bottom = fill ? content.bottomAnchor.constraint(equalTo: v.bottomAnchor) : content.bottomAnchor.constraint(lessThanOrEqualTo: v.bottomAnchor)
        NSLayoutConstraint.activate([content.topAnchor.constraint(equalTo: v.topAnchor), content.leadingAnchor.constraint(equalTo: v.leadingAnchor),
                                     content.trailingAnchor.constraint(equalTo: v.trailingAnchor), bottom])
        return v
    }
}
