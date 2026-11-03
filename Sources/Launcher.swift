import AppKit

final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        onKey?(e) == true || super.performKeyEquivalent(with: e)
    }
}

final class RowView: NSTableRowView {
    override var isEmphasized: Bool { get { false } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        Launcher.theme.selection.setFill()
        let r = min(Launcher.theme.radius * 0.6, 10)
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: r, yRadius: r).fill()
    }
}

final class Cell: NSTableCellView {
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let sub = NSTextField(labelWithString: "")
    let hint = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        sub.textColor = .secondaryLabelColor
        hint.textColor = .tertiaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .secondaryLabelColor
        for f in [title, sub] { f.lineBreakMode = .byTruncatingTail; f.maximumNumberOfLines = 1 }
        for v in [icon, title, sub, hint] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ t: Theme) {
        title.font = t.font(t.fontSize, .medium)
        sub.font = t.font(t.fontSize - 3)
        hint.font = t.font(t.fontSize - 3.5)
    }

    override func layout() {
        super.layout()
        let t = Launcher.theme, h = bounds.height
        let s = min((t.rowHeight * 0.62).rounded(), 34)
        icon.frame = NSRect(x: 10, y: (h - s) / 2, width: s, height: s)
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: bounds.width - hint.frame.width - 14, y: (h - hint.frame.height) / 2)
        let x = s + 22, w = hint.frame.minX - x - 10
        let th = (t.fontSize * 1.3).rounded(), sh = ((t.fontSize - 3) * 1.3).rounded()
        if sub.stringValue.isEmpty {
            title.frame = NSRect(x: x, y: (h - th) / 2, width: w, height: th)
        } else {
            let top = (h + th + sh) / 2
            title.frame = NSRect(x: x, y: top - th, width: w, height: th)
            sub.frame = NSRect(x: x, y: top - th - sh - 1, width: w, height: sh)
        }
        sub.isHidden = sub.stringValue.isEmpty
    }
}

final class Launcher: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    /// Read by rows and cells while drawing; set from config.json's "theme".
    static var theme = Theme()
    static let footerH: CGFloat = 32

    let panel: KeyPanel
    let field = NSTextField()
    let table = NSTableView()
    let scroll = NSScrollView()
    let line = NSBox()
    let root = NSView()                       // all content; sits in the glass or the blur
    private let bg = NSVisualEffectView()     // classic blur, and the fallback before macOS 26
    private var liquid: NSView?               // NSGlassEffectView on macOS 26
    private let tint = NSView()               // theme background over the classic blur
    private let glass = NSImageView()
    private let footerLine = NSBox()
    private let footerLeft = NSTextField(labelWithString: "")
    private let footerRight = NSTextField(labelWithString: "")

    let apps = Apps()
    let clipboard = Clipboard()
    let files = Files()

    let hotkeys = HotKeys()
    private(set) var config = Config()
    private var hotkeyLabels: [String: String] = [:]   // lowercased action -> "⌃⌥←"
    private(set) var activeHotkeys: [(combo: String, action: String)] = []
    var onOpenSettings: (() -> Void)?
    /// After every applyConfig, for what lives outside the launcher (the update checks).
    var onConfig: (() -> Void)?
    private var features: [Bool] = []   // the switches applyConfig last saw
    /// First launch: until the panel first closes, an empty query lists the few things worth setting up.
    var welcoming = false
    /// A version waiting to be installed, shown quietly in the footer; ⌘U calls onUpdate.
    var pendingUpdate: String? { didSet { updateFooter() } }
    var onUpdate: (() -> Void)?
    private var watch: ConfigWatch?

    var items: [Item] = []
    private var query = ""
    private var filePaths: [String] = []
    private var fxAnswer: String?
    private var pending: DispatchWorkItem?
    private var topEdge: CGFloat = 0
    private var userMoved = false
    private var menusExpanded = false

    // Sources refreshed each time the panel opens.
    private var running: [NSRunningApplication] = []
    private var scripts: [Script] = []
    private var audio: [Audio.Device] = []
    private var menus: [Menus.Entry] = []
    private var windows: [WindowList.Entry] = []
    private var tabs: [Tabs.Tab] = []
    private var tabsLoaded = false
    private var shortcuts: [String] = []
    private var shortcutsLoaded = Date.distantPast
    private var output: (title: String, lines: [String])?   // script output shown in place of results

    override init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: Launcher.theme.width, height: Launcher.theme.fieldHeight),
                         styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                         backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.onKey = { [weak self] in self?.keyEquivalent($0) ?? false }

        bg.frame = panel.contentRect(forFrameRect: panel.frame)
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.autoresizingMask = [.width, .height]
        panel.contentView = bg
        root.frame = bg.bounds
        root.autoresizingMask = [.width, .height]
        bg.addSubview(root)
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        tint.frame = root.bounds

        glass.contentTintColor = .secondaryLabelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search apps, files, settings, the web…"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self

        line.boxType = .separator
        footerLine.boxType = .separator
        footerRight.alignment = .right
        for f in [footerLeft, footerRight] { f.textColor = .secondaryLabelColor; f.lineBreakMode = .byTruncatingTail }

        let col = NSTableColumn(identifier: .init("c"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = Launcher.theme.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        for v in [tint, glass, field, line, scroll, footerLine, footerLeft, footerRight] as [NSView] { root.addSubview(v) }
        applyTheme()
        apps.refresh()
        watch = ConfigWatch { [weak self] in self?.applyConfig() }
        apps.onChange = { [weak self] in
            self?.sourcesChanged()
            self?.prewarmIcons()
        }
        DispatchQueue.global(qos: .utility).async { _ = Audio.devices() }   // warm CoreAudio before the first open
    }

    /// Names a hotkey can run, for the settings window's Action list: commands, window actions, apps,
    /// snippets, bookmarks, scripts and shortcuts (not windows, tabs or menu items, which come and go).
    func actionNames() -> [String] {
        var seen: Set<String> = ["show"], out = ["show"]
        let fleeting = ["win:", "tab:", "menu:", "audio:"]
        for n in pool().filter({ e in !fleeting.contains { e.item.id.hasPrefix($0) } }).compactMap({ $0.names.first })
        where seen.insert(n.lowercased()).inserted { out.append(n) }
        return out
    }

    /// Lets the settings window record a combo that is already a hotkey; applyConfig turns them back on.
    func suspendHotkeys() { hotkeys.removeAll() }

    /// Lowercased names a hotkey can run, for `hop --check`.
    func knownActions() -> Set<String> {
        Set(pool().compactMap { $0.names.first?.lowercased() })
            .union(["show", "clipboard history"])
    }

    private func applyTheme() {
        let t = Launcher.theme
        panel.appearance = t.nsAppearance
        if !useGlass(t) {
            if root.superview !== bg {
                root.removeFromSuperview()
                root.translatesAutoresizingMaskIntoConstraints = true   // the glass view turns this off; without it root stays 0×0
                root.frame = bg.bounds
                bg.addSubview(root)
            }
            if panel.contentView !== bg { panel.contentView = bg }
            tint.isHidden = false
            if let m = t.material { bg.material = m; bg.state = .active } else { bg.state = .inactive }
            tint.layer?.backgroundColor = t.background.flatMap(Theme.color)?.cgColor
                ?? (t.material == nil ? NSColor.windowBackgroundColor.cgColor : nil)
            bg.maskImage = Launcher.mask(radius: max(t.radius, 0.5))
        }
        glass.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: t.fontSize + 4, weight: .medium))
        field.font = t.font(t.fontSize + 8)
        for f in [footerLeft, footerRight] { f.font = t.font(t.fontSize - 3.5) }
        table.rowHeight = t.rowHeight
        table.reloadData()
        if panel.isVisible { resize() }
    }

    /// Liquid Glass: the system draws the material, shape and edge light; the theme only picks the
    /// style, corner radius and an optional tint. Returns false where it is unavailable.
    private func useGlass(_ t: Theme) -> Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *), let style = t.glass {
            let g = liquid as? NSGlassEffectView ?? NSGlassEffectView()
            g.style = style == "clear" ? .clear : .regular
            g.cornerRadius = t.radius
            g.tintColor = t.background.flatMap(Theme.color)
            if g.contentView !== root { root.removeFromSuperview(); g.contentView = root }
            if panel.contentView !== g { panel.contentView = g }
            tint.isHidden = true
            liquid = g
            return true
        }
        #endif
        return false
    }

    static func mask(radius r: CGFloat) -> NSImage {
        let d = r * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    // MARK: show / hide

    func toggle() { panel.isVisible ? hide() : show() }

    func show(query: String = "", focus: Bool = true) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        // Switches flipped outside Hop (`defaults write`, see AGENTS.md) take effect on the next open.
        if Feature.allCases.map(\.isOn) != features { applyConfig() }
        topEdge = vf.maxY - vf.height * 0.2
        loadSources()
        field.stringValue = query
        update()
        panel.setFrameOrigin(NSPoint(x: vf.midX - Launcher.theme.width / 2, y: topEdge - panel.frame.height))
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        panel.makeFirstResponder(field)
        apps.refresh()
    }

    func hide() {
        welcoming = false
        pending?.cancel()
        files.cancel()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ n: Notification) { hide() }

    /// Lays the panel out top to bottom: field, results, footer. The top edge stays put as it grows.
    private func resize() {
        let t = Launcher.theme, W = t.width, F = t.fieldHeight
        let rows = min(items.count, t.rows)
        let listH = rows == 0 ? 0 : CGFloat(rows) * (t.rowHeight + 2) + 12
        let footH = rows == 0 ? 0 : Launcher.footerH
        let h = F + listH + footH
        var f = panel.frame
        f.origin.x = f.midX - W / 2
        f.origin.y = topEdge - h
        f.size = NSSize(width: W, height: h)
        panel.setFrame(f, display: false)

        let gs = t.fontSize + 9, fh = (t.fontSize + 8) * 1.35
        glass.frame = NSRect(x: 20, y: h - F + (F - gs) / 2, width: gs, height: gs)
        field.frame = NSRect(x: 28 + gs, y: h - F + (F - fh) / 2, width: W - gs - 48, height: fh)
        line.frame = NSRect(x: 0, y: h - F, width: W, height: 1)
        scroll.frame = NSRect(x: 0, y: footH, width: W, height: listH)
        footerLine.frame = NSRect(x: 0, y: footH, width: W, height: 1)
        let lh = (t.fontSize - 3.5) * 1.4
        footerLeft.frame = NSRect(x: 16, y: (footH - lh) / 2, width: W / 2 - 16, height: lh)
        footerRight.frame = NSRect(x: W / 2, y: (footH - lh) / 2, width: W / 2 - 16, height: lh)
        for v in [line, footerLine, footerLeft, footerRight] as [NSView] { v.isHidden = rows == 0 }
        table.tableColumns.first?.width = scroll.contentSize.width - 12
        table.sizeLastColumnToFit()
        panel.display()
    }

    // MARK: config and hotkeys

    func applyConfig() {
        config = Config.load()
        sourcesChanged()
        if config.theme != Launcher.theme { Launcher.theme = config.theme; applyTheme() }
        features = Feature.allCases.map(\.isOn)
        clipboard.enabled = Feature.clipboardHistory.isOn
        hotkeys.removeAll()
        hotkeyLabels = [:]
        activeHotkeys = []
        for (combo, action) in config.hotkeys.sorted(by: { $0.key < $1.key }) {
            guard hotkeys.register(combo, { [weak self] in self?.perform(action) }) else { continue }
            hotkeyLabels[action.lowercased(), default: HotKeys.symbols(combo)] = HotKeys.symbols(combo)
            activeHotkeys.append((combo, action))
        }
        scripts = Script.load()
        onConfig?()
    }

    /// Runs a hotkey action: "show", or the title of any command, window action, script or quicklink.
    func perform(_ action: String) {
        let a = action.lowercased()
        if a == "show" { toggle(); return }
        if a == "clipboard history" { show(query: "clip "); return }
        if let entry = pool().first(where: { $0.item.title.lowercased() == a || $0.names.first?.lowercased() == a }) {
            entry.item.action()
        }
    }

    // MARK: sources loaded when the panel opens

    func loadSources() {
        sourcesChanged()
        output = nil
        tabs = []
        tabsLoaded = false
        System.background(Audio.devices) { [weak self] in self?.audio = $0; self?.sourcesChanged() }   // CoreAudio: ~100 ms cold
        scripts = Script.load()
        running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        menus = []
        windows = []
        if AXIsProcessTrusted(), let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            let pid = front.processIdentifier, name = front.localizedName ?? ""
            System.background({ (Menus.read(pid: pid, appName: name), WindowList.read()) }) { [weak self] in
                self?.menus = $0.0
                self?.windows = $0.1
                self?.arrived()
            }
        }
        if Date().timeIntervalSince(shortcutsLoaded) > 60 {
            shortcutsLoaded = Date()
            System.background(Shortcuts.list, qos: .utility) { self.shortcuts = $0; self.sourcesChanged() }
        }
    }

    /// Browser tabs cost an Apple Event round trip per browser, so they load on the first real query.
    private func loadTabsIfNeeded() {
        guard !tabsLoaded, Feature.browserTabs.isOn else { return }
        tabsLoaded = true
        System.background(Tabs.read) { [weak self] in self?.tabs = $0; self?.arrived() }
    }

    /// A source finished loading after the panel opened: rank it in with what is already showing.
    private func arrived() {
        sourcesChanged()
        if !query.isEmpty { rebuild(keepSelection: true) }
    }

    // MARK: input

    func controlTextDidChange(_ n: Notification) { update() }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.insertNewline(_:)): run(table.selectedRow, alt: false)
        case #selector(NSResponder.insertTab(_:)):
            if table.selectedRow >= 0, let fill = items[table.selectedRow].fill {
                field.stringValue = fill
                field.currentEditor()?.selectedRange = NSRange(location: (fill as NSString).length, length: 0)
                update()
            }
        case #selector(NSResponder.cancelOperation(_:)):
            if output != nil { output = nil; rebuild(keepSelection: false) }
            else if field.stringValue.isEmpty { hide() } else { field.stringValue = ""; update() }
        default: return false
        }
        return true
    }

    private func keyEquivalent(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), let ch = e.charactersIgnoringModifiers else { return false }
        if let n = Int(ch), n >= 1, n <= 9 { run(n - 1, alt: false); return true }
        if e.keyCode == 36 { run(table.selectedRow, alt: true); return true }
        if ch == "u", pendingUpdate != nil, let go = onUpdate { hide(); go(); return true }
        // There is no menu bar in an agent app, so wire the text-editing shortcuts by hand.
        let edit: [String: Selector] = [
            "a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
            "z": mods.contains(.shift) ? Selector(("redo:")) : Selector(("undo:")),
        ]
        if let sel = edit[ch.lowercased()] { return NSApp.sendAction(sel, to: nil, from: self) }
        return false
    }

    private func move(_ d: Int) {
        guard !items.isEmpty else { return }
        userMoved = true
        let r = max(0, min(items.count - 1, table.selectedRow + d))
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    @objc private func clicked() { run(table.clickedRow, alt: false) }

    private func run(_ row: Int, alt: Bool) {
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        Usage.bump(item.id, query: query)
        if item.keepOpen { item.action(); return }
        hide()
        // Let the panel go away first so window and paste actions hit the app underneath.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { (alt ? item.alt ?? item.action : item.action)() }
    }

    // MARK: results

    private func update() {
        query = field.stringValue.trimmingCharacters(in: .whitespaces)
        filePaths = []
        fxAnswer = nil
        output = nil
        menusExpanded = false
        userMoved = false
        pending?.cancel()
        files.cancel()
        rebuild(keepSelection: false)

        let q = query
        guard !q.isEmpty, !isClipQuery(q), Emoji.query(q) == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.query == q else { return }
            if q.count >= 2 { self.loadTabsIfNeeded() }
            if Feature.exchangeRates.isOn, let (v, from, to) = Units.currency(q) {
                Web.currency(v, from, to) { [weak self] s in
                    guard let self, self.query == q else { return }
                    self.fxAnswer = s
                    self.rebuild(keepSelection: true)
                }
            }
            if Feature.fileSearch.isOn && q.count >= 3 && Web.looksLikeURL(q) == nil {
                self.files.search(q) { [weak self] paths in
                    guard let self, self.query == q else { return }
                    self.filePaths = paths
                    self.rebuild(keepSelection: true)
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func isClipQuery(_ q: String) -> Bool {
        let l = q.lowercased()
        return l == "clip" || l == "cb" || l.hasPrefix("clip ") || l.hasPrefix("cb ")
    }

    private struct Bang { let name: String; let symbol: String; let url: (String) -> String; let rest: String }

    private func bang(_ q: String) -> Bang? {
        guard let sp = q.firstIndex(of: " ") else { return nil }
        let key = q[..<sp].lowercased(), rest = q[sp...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        if let b = Web.bangs.first(where: { $0.key == key }) { return Bang(name: b.name, symbol: b.symbol, url: b.url, rest: rest) }
        if let l = config.quicklinks.first(where: { $0.key == key && $0.url.contains("{query}") }) {
            return Bang(name: l.name, symbol: "link", url: { l.url.replacingOccurrences(of: "{query}", with: Web.enc($0)) }, rest: rest)
        }
        return nil
    }

    private func bangStripped(_ q: String) -> String { bang(q)?.rest ?? q }

    private func rebuild(keepSelection: Bool) {
        // Late answers (currency, files) may land above the selection; only hold it if the user arrowed to it.
        let selectedID = keepSelection && userMoved && table.selectedRow >= 0 && table.selectedRow < items.count
            ? items[table.selectedRow].id : nil
        items = compose(query)
        table.reloadData()
        let row = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        if !items.isEmpty { table.selectRowIndexes([row], byExtendingSelection: false); table.scrollRowToVisible(row) }
        updateFooter()
        resize()
    }

    private func answer(_ value: String, _ label: String, _ icon: Item.Icon) -> Item {
        Item(id: "answer", title: value, subtitle: "\(label) · ↵ copy · ⌘↵ paste", icon: icon,
             action: { [clipboard] in clipboard.copy(value) }, alt: { [clipboard] in Paste.paste(value, clipboard) })
    }

    func compose(_ q: String) -> [Item] {
        if let o = output { return outputItems(o) }
        if q.isEmpty { return welcoming ? welcomeItems() : [] }
        if isClipQuery(q) { return clipItems(q) }
        if let e = Emoji.query(q) { return emojiItems(e) }
        let l = q.lowercased()
        for p in ["quit ", "kill "] where l.hasPrefix(p) { return quitItems(String(q.dropFirst(p.count)), force: p == "kill ") }

        var out: [Item] = []
        if let b = bang(q) {
            out.append(Item(id: "bang:\(b.name)", title: b.rest, subtitle: "Search \(b.name)", icon: .symbol(b.symbol),
                            action: { Web.open(b.url(b.rest)) }))
        }
        // "port 3000" runs "What's on Port" with 3000: any leading words that match the title, then the argument.
        for s in scripts where s.argument != nil {
            var at = q.startIndex
            while let sp = q[at...].firstIndex(of: " ") {
                let head = String(q[..<sp]), arg = q[sp...].trimmingCharacters(in: .whitespaces)
                if !arg.isEmpty, let sc = Match.score(head, s.title, loose: false), sc >= 600 {
                    out.append(scriptItem(s, arg: arg))
                    break
                }
                at = q.index(after: sp)
            }
        }
        if let v = Calc.eval(q) { out.append(answer(Calc.format(v), "= \(q)", .symbol("equal.circle"))) }
        if let u = Units.convert(q) { out.append(answer(u, q, .symbol("arrow.left.arrow.right.circle"))) }
        if let fx = fxAnswer { out.append(answer(fx, "\(q) · ECB rate", .symbol("dollarsign.circle"))) }
        if let tz = Clock.zone(q) { let (t, sub) = Clock.describe(tz); out.append(answer(t, sub, .symbol("clock"))) }
        if let (t, sub) = Clock.unix(q) { out.append(answer(t, sub, .symbol("clock.arrow.circlepath"))) }
        if let n = Volume.parse(q) {
            out.append(Item(id: "volume", title: "Set volume to \(n)%", subtitle: "Sound", icon: .symbol("speaker.wave.2"),
                            action: { Volume.set(n) }))
        }
        if let w = Define.word(q), let d = Define.lookup(w) {
            out.append(Item(id: "define", title: w, subtitle: d, icon: .symbol("character.book.closed"),
                            action: { Web.open("dict://\(Web.enc(w))") }, alt: { [clipboard] in clipboard.copy(d) }))
        }
        if let url = Web.looksLikeURL(q) {
            out.append(Item(id: "url", title: "Open \(q)", subtitle: url, icon: .symbol("safari"), action: { Web.open(url) }))
        }

        let lq = q.lowercased(), usage = Usage.scorer(query: q)
        let scored = pool().compactMap { e -> (Double, Item, Bool)? in
            guard !(e.minor && q.count < 2), let s = e.score(lq) else { return nil }
            return (s + e.base + usage(e.item.id), e.item, e.minor)
        }.sorted { $0.0 > $1.0 }
        let top = scored.first?.0 ?? 0
        var ranked = scored.filter { !$0.2 || $0.0 >= top - 250 }.map { ($0.0, $0.1) }
        // Files you have opened from Hop compete on usage like everything else; the rest stay below.
        for path in filePaths {
            let u = usage(path)
            guard u > 0 else { continue }
            let name = (path as NSString).lastPathComponent
            ranked.append(((Match.score(q, name) ?? 400) - 60 + u, fileItem(path)))
        }
        ranked.sort { $0.0 > $1.0 }

        // One web row, placed by intent: first for questions or when nothing here matches well,
        // last when the query clearly means something on this Mac.
        let term = bangStripped(q)
        let google = Item(id: "google", title: term, subtitle: "Search Google", icon: .symbol("magnifyingglass"),
                          action: { Web.open(Web.google(term)) })
        let hasAnswer = out.contains { $0.id != "url" && !$0.id.hasPrefix("bang:") }
        let best = ranked.first.map(\.0) ?? (filePaths.isEmpty ? nil : 700)
        let webFirst = bang(q) == nil && Intent.webFirst(q, bestLocal: best, hasAnswer: hasAnswer)
        if webFirst { out.append(google) }

        // With a strong hit (exact, prefix, initials), drop far weaker ones such as one-letter typos.
        let floor = (ranked.first?.0 ?? 0) - 600
        var seen = Set(out.map(\.id))
        // Menu matches: the best one gets a row, the rest fold into one line that lists them all.
        var extraMenus: [Item] = []
        var menuRow: Int?
        for (score, item) in ranked where score >= floor && seen.insert(item.id).inserted {
            if item.id.hasPrefix("menu:") && !menusExpanded {
                if menuRow != nil { extraMenus.append(item); continue }
                menuRow = out.count
            }
            if out.count < (menusExpanded ? 14 : 8) { out.append(item) }
        }
        if let at = menuRow, extraMenus.count == 1 {
            out.insert(extraMenus[0], at: at + 1)   // folding one item into a row saves nothing
        } else if let at = menuRow, !extraMenus.isEmpty {
            let app = out[at].subtitle.components(separatedBy: " › ").first ?? "app"
            out.insert(Item(id: "menu-more", title: "\(extraMenus.count) more in \(app) menus",
                            subtitle: extraMenus.map(\.title).joined(separator: " · "),
                            icon: .symbol("ellipsis.circle"), keepOpen: true, action: { [weak self] in
                                guard let self else { return }
                                self.menusExpanded = true
                                self.rebuild(keepSelection: false)
                                self.table.selectRowIndexes([min(at + 1, self.items.count - 1)], byExtendingSelection: false)
                                self.updateFooter()
                            }), at: at + 1)
        }

        for path in filePaths where !seen.contains(path) { out.append(fileItem(path)) }

        if !webFirst && bang(q) == nil { out.append(google) }
        return out
    }

    /// The hotkey to tell people about: ⌥Space works from the start, ⌘Space only once Spotlight lets go of it.
    private var openCombo: String? {
        let shows = activeHotkeys.filter { $0.action == "show" }.map(\.combo)
        return shows.contains("opt+space") ? "opt+space" : shows.first
    }

    /// The setup steps that still apply, each runnable in place so the list stays open.
    private func welcomeItems() -> [Item] {
        let steps = ["Use ⌘Space for Hop", "Grant Accessibility Access", "Launch Hop at Login", "Hop Settings"]
        var items = commands().map(\.item).filter { steps.contains($0.title) }
        if config.hotkeys["cmd+space"]?.lowercased() == "show", let (why, fix) = cmdSpaceOwner() {
            items.append(Item(id: "cmd:Use ⌘Space for Hop", title: "Use ⌘Space for Hop", subtitle: why, icon: .symbol("command"), action: fix))
        }
        return items.sorted { steps.firstIndex(of: $0.title)! < steps.firstIndex(of: $1.title)! }.map { item in
            var i = item
            i.keepOpen = true
            i.action = { [weak self] in item.action(); self?.rebuild(keepSelection: false) }
            return i
        }
    }

    /// Whatever else may answer ⌘Space, and where to turn it off: a macOS shortcut, or another launcher that
    /// is running (Carbon lets two apps register the same combo, so Hop cannot tell which one wins).
    /// Hop points there rather than changing other apps' settings itself.
    private func cmdSpaceOwner() -> (String, () -> Void)? {
        let system = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        if let name = Launcher.systemCmdSpace(system as? [String: [String: Any]] ?? [:]) {
            return ("macOS uses it for \(name): turn that off in Keyboard Shortcuts", { SettingsPanes.open("com.apple.Keyboard-Settings.extension") })
        }
        let launchers = ["com.raycast.macos", "com.runningwithcrayons.Alfred", "at.obdev.LaunchBar"]
        guard let app = NSWorkspace.shared.runningApplications.first(where: { launchers.contains($0.bundleIdentifier ?? "") }),
              let name = app.localizedName else { return nil }
        return ("\(name) is running and may use it too: check \(name)'s hotkey", { app.activate() })
    }

    /// The macOS shortcut on ⌘Space, if one is on: Spotlight unless it was ever changed (no entry), or any
    /// symbolic hotkey rebound to it (parameters: character, key code 49 for Space, ⌘ = 1 << 20).
    static func systemCmdSpace(_ hotkeys: [String: [String: Any]]) -> String? {
        let names = ["64": "Spotlight", "65": "Finder search", "60": "input sources", "61": "input sources"]
        if hotkeys["64"] == nil { return "Spotlight" }
        return hotkeys.sorted { $0.key < $1.key }.first { _, e in
            let p = (e["value"] as? [String: Any])?["parameters"] as? [Int] ?? []
            return e["enabled"] as? Bool == true && p.count == 3 && p[1] == 49 && p[2] == 1 << 20
        }.map { names[$0.key] ?? "a keyboard shortcut" }
    }

    private func fileItem(_ path: String) -> Item {
        let url = URL(fileURLWithPath: path)
        return Item(id: path, title: url.lastPathComponent,
                    subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                    icon: .file(path), fill: url.lastPathComponent,
                    action: { NSWorkspace.shared.open(url) },
                    alt: { NSWorkspace.shared.activateFileViewerSelecting([url]) })
    }

    // MARK: the ranked pool: everything that is matched by name

    /// names[0] is the real name; the rest are keywords that help find it. Keyword matches count at
    /// `aliasWeight`, so even an exact keyword ("settings" on Hop Settings) lands below a word of
    /// a real name ("System Settings"). Snippet keywords and quicklink keys are triggers you chose: 1.
    private struct Entry {
        let names: [String], base: Double, item: Item, loose: Bool, aliasWeight: Double
        let keys: [Match.Key]   // names prepared once, not on every keystroke
        /// Only shown when it is close to the best match (menu items of the front app): "slack" should
        /// not list Hide Slack, Quit Slack and About Slack under the Slack app itself.
        var minor = false
        init(names: [String], base: Double, aliasWeight: Double = 0.7, item: Item, loose: Bool = false) {
            self.names = names; self.base = base; self.item = item; self.loose = loose; self.aliasWeight = aliasWeight
            keys = names.map(Match.Key.init)
        }
        /// `q` already lowercased.
        func score(_ q: String) -> Double? {
            keys.enumerated().compactMap { i, k in
                Match.score(lowered: q, k, loose: loose).map { i == 0 ? $0 : $0 * aliasWeight }
            }.max()
        }
    }

    /// Hop's own housekeeping; ranked below everything you actually came to open.
    private static let housekeeping: Set<String> = ["Hop Settings", "Edit Hop Config",
        "Save Clipboard as Snippet", "Open Scripts Folder", "Quit Hop", "Grant Accessibility Access",
        "Launch Hop at Login", "Don't Launch Hop at Login"]

    /// Everything matched by name, built once per panel open (or when a source changes) rather than
    /// on every keystroke.
    private var poolCache: [Entry]?
    private func pool() -> [Entry] {
        if let p = poolCache { return p }
        let p = buildPool()
        poolCache = p
        return p
    }
    /// Something the candidate list is built from changed.
    private func sourcesChanged() { poolCache = nil }

    private func buildPool() -> [Entry] {
        var out: [Entry] = []
        let runningPaths = Set(running.compactMap { $0.bundleURL?.path })
        var indexed = Set<String>()
        for app in apps.all {
            indexed.insert(app.path)
            out.append(Entry(names: [app.name], base: 0, item: appItem(name: app.name, path: app.path, running: runningPaths.contains(app.path)),
                             loose: true))
        }
        for app in running {   // apps run from odd places (Xcode builds, ~/Downloads) still show up
            guard let path = app.bundleURL?.path, !indexed.contains(path), let name = app.localizedName else { continue }
            out.append(Entry(names: [name], base: 0, item: appItem(name: name, path: path, running: true), loose: true))
        }
        for c in commands() {
            out.append(Entry(names: [c.title] + c.keywords, base: Launcher.housekeeping.contains(c.title) ? -90 : -20, item: c.item))
        }
        for p in SettingsPanes.all {
            out.append(Entry(names: [p.name] + p.keywords, base: -15,
                             item: Item(id: "pane:\(p.id)", title: p.name, subtitle: "System Settings",
                                        icon: .file("/System/Applications/System Settings.app"), action: { SettingsPanes.open(p.id) })))
        }
        for s in config.snippets {
            let preview = s.text.replacingOccurrences(of: "\n", with: " ⏎ ")
            out.append(Entry(names: [s.name] + (s.keyword.map { [$0] } ?? []), base: -5, aliasWeight: 1,
                             item: Item(id: "snippet:\(s.name)", title: s.name,
                                        subtitle: label("Snippet", s.name) + (s.keyword.map { " · \($0)" } ?? "") + " · " + preview,
                                        icon: .symbol("text.quote"),
                                        action: { [clipboard] in Paste.paste(s.expanded(), clipboard) },
                                        alt: { [clipboard] in clipboard.copy(s.expanded()) })))
        }
        for l in config.quicklinks {
            let hasQuery = l.url.contains("{query}")
            out.append(Entry(names: [l.name] + (l.key.map { [$0] } ?? []), base: -10, aliasWeight: 1,
                             item: Item(id: "link:\(l.name)", title: l.name,
                                        subtitle: hasQuery ? "Bookmark · type \(l.key ?? l.name) <query>" : l.url,
                                        icon: .symbol("link"), fill: hasQuery ? "\(l.key ?? l.name) " : nil,
                                        // A search waits for what to search for, from the list or a hotkey alike.
                                        action: hasQuery ? { [weak self] in self?.show(query: "\(l.key ?? l.name) ") } : { Web.open(l.url) })))
        }
        for s in scripts {
            out.append(Entry(names: [s.title], base: -10, item: scriptItem(s, arg: nil)))
        }
        for name in shortcuts {
            out.append(Entry(names: [name], base: -30, item: Item(id: "shortcut:\(name)", title: name, subtitle: label("Shortcut", name),
                                                                 icon: .file("/System/Applications/Shortcuts.app"),
                                                                 action: { Shortcuts.run(name) })))
        }
        for d in audio {
            let kind = d.output ? "Output" : "Input"
            out.append(Entry(names: [d.name, "\(kind.lowercased()) \(d.name)", d.output ? "speakers" : "microphone", "audio", "sound"],
                             base: -35, item: Item(id: "audio:\(d.output):\(d.name)", title: "\(kind): \(d.name)",
                                                   subtitle: d.current ? "Sound \(kind.lowercased()) · current" : "Switch sound \(kind.lowercased())",
                                                   icon: .symbol(d.output ? "hifispeaker" : "mic"), action: { Audio.select(d) })))
        }
        for w in windows {
            out.append(Entry(names: [w.title, "\(w.app) \(w.title)"], base: -60,
                             item: Item(id: "win:\(w.app):\(w.title)", title: w.title, subtitle: "\(w.app) window",
                                        icon: w.appPath.map { .file($0) } ?? .symbol("macwindow"), action: { WindowList.focus(w) })))
        }
        for t in tabs {
            let host = URL(string: t.url)?.host ?? t.url
            out.append(Entry(names: [t.title, host], base: -70,
                             item: Item(id: "tab:\(t.url)", title: t.title, subtitle: "\(t.browser) tab · \(host)",
                                        icon: t.appPath.map { .file($0) } ?? .symbol("globe"), action: { Tabs.focus(t) },
                                        alt: { [clipboard] in clipboard.copy(t.url) })))
        }
        for m in menus {
            // Menu items of whatever app is in front: handy, but never ahead of an app or setting,
            // and only once there are two letters to match (there can be hundreds).
            var e = Entry(names: [m.title], base: -170,
                          item: Item(id: "menu:\(m.path):\(m.title)", title: m.title, subtitle: m.path,
                                     icon: .symbol("filemenu.and.selection"), action: { Menus.press(m) }))
            e.minor = true
            out.append(e)
        }
        return out
    }

    private func label(_ kind: String, _ title: String) -> String {
        hotkeyLabels[title.lowercased()].map { "\(kind) · \($0)" } ?? kind
    }

    private func appItem(name: String, path: String, running: Bool) -> Item {
        // Just the name: where an app lives is noise here (⌘↵ still shows it in Finder).
        Item(id: path, title: name, subtitle: running ? "Running" : "", icon: .file(path), fill: name,
                    action: { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) },
                    alt: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) })
    }

    private func quitItems(_ rest: String, force: Bool) -> [Item] {
        let list = running.compactMap { app -> (Double, NSRunningApplication)? in
            guard let name = app.localizedName else { return nil }
            if rest.isEmpty { return (0, app) }
            return Match.score(rest, name).map { ($0, app) }
        }.sorted { $0.0 > $1.0 }
        return list.prefix(20).map { _, app in
            let name = app.localizedName ?? ""
            return Item(id: "quit:\(name)", title: "\(force ? "Force Quit" : "Quit") \(name)",
                        subtitle: force ? "Ends it without asking to save" : "Asks to save like ⌘Q does",
                        icon: app.bundleURL.map { .file($0.path) } ?? .symbol("xmark.circle"),
                        action: { if force { app.forceTerminate() } else { app.terminate() } })
        }
    }

    private func emojiItems(_ q: String) -> [Item] {
        Emoji.search(q).map { e, name in
            Item(id: "emoji:\(e)", title: name.capitalized, subtitle: "↵ paste · ⌘↵ copy", icon: .text(e),
                 action: { [clipboard] in Paste.paste(e, clipboard) }, alt: { [clipboard] in clipboard.copy(e) })
        }
    }

    private func clipItems(_ q: String) -> [Item] {
        let filter = q.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        guard clipboard.enabled else {
            return [Item(id: "clip-off", title: "Clipboard History is off", subtitle: "Turn it on in Hop Settings",
                         icon: .symbol("doc.on.clipboard"), action: { [weak self] in self?.onOpenSettings?() })]
        }
        let list = clipboard.items.filter { c in
            guard !filter.isEmpty else { return true }
            if case .text(let s) = c { return s.localizedCaseInsensitiveContains(filter) }
            return ["image", "picture", "screenshot", "png"].contains { $0.hasPrefix(filter.lowercased()) }
        }
        if list.isEmpty {
            return [Item(id: "clip-empty", title: "Clipboard history is empty", subtitle: "Copy some text or an image and it shows up here",
                         icon: .symbol("doc.on.clipboard"), action: {})]
        }
        let hint = AXIsProcessTrusted() ? "↵ paste · ⌘↵ copy" : "↵ copy"
        return list.prefix(50).enumerated().map { i, c in
            let (title, sub, icon): (String, String, Item.Icon) = switch c {
            case .text(let s): ((s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s).trimmingCharacters(in: .whitespaces),
                                "\(s.count) characters", .symbol("doc.on.clipboard"))
            case let .image(data, _, thumb, size): ("Image \(Int(size.width))×\(Int(size.height))",
                                                    ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file), .image(thumb))
            }
            return Item(id: "clip:\(i)", title: title, subtitle: "\(sub) · " + hint, icon: icon,
                        action: { [clipboard] in Paste.paste(c, clipboard) }, alt: { [clipboard] in clipboard.copy(c) })
        }
    }

    // MARK: scripts

    private func scriptItem(_ s: Script, arg: String?) -> Item {
        let icon: Item.Icon = s.icon.map { $0.count <= 2 ? .text($0) : .file((Config.scriptsDir as NSString).appendingPathComponent($0)) }
            ?? .symbol("terminal")
        if s.argument != nil && arg == nil {
            return Item(id: "script:\(s.path)", title: s.title, subtitle: "\(s.subtitle) · Tab, then \(s.argument ?? "argument")",
                        icon: icon, fill: s.title + " ", action: { [weak self] in
                            self?.show(query: s.title + " ")
                        })
        }
        let silent = s.mode == "silent"
        return Item(id: "script:\(s.path)", title: arg.map { "\(s.title): \($0)" } ?? s.title, subtitle: label(s.subtitle, s.title),
                    icon: icon, keepOpen: !silent, action: { [weak self] in
                        if silent { s.run(arg) { _, _ in }; return }
                        self?.output = (s.title, ["Running…"])
                        self?.rebuild(keepSelection: false)
                        s.run(arg) { out, status in
                            guard let self, self.output?.title == s.title else { return }
                            var lines = out.split(separator: "\n").map(String.init)
                            if s.mode == "compact" || s.mode == "inline" { lines = Array(lines.suffix(1)) }
                            if lines.isEmpty { lines = [status == 0 ? "Done" : "Exited with status \(status)"] }
                            self.output = (s.title, lines)
                            self.rebuild(keepSelection: false)
                        }
                    })
    }

    private func outputItems(_ o: (title: String, lines: [String])) -> [Item] {
        let all = o.lines.joined(separator: "\n")
        return o.lines.prefix(200).enumerated().map { i, line in
            Item(id: "out:\(i)", title: line, subtitle: i == 0 ? "\(o.title) · ↵ copy line · ⌘↵ copy all · esc back" : "",
                 icon: .symbol(i == 0 ? "terminal" : "text.alignleft"),
                 action: { [clipboard] in clipboard.copy(line) }, alt: { [clipboard] in clipboard.copy(all) })
        }
    }

    // MARK: built-in commands

    private func commands() -> [(title: String, keywords: [String], item: Item)] {
        func cmd(_ title: String, _ keywords: [String], _ symbol: String, _ sub: String = "Command",
                 _ action: @escaping () -> Void) -> (String, [String], Item) {
            (title, keywords, Item(id: "cmd:\(title)", title: title, subtitle: label(sub, title), icon: .symbol(symbol), action: action))
        }
        func folder(_ title: String, _ dir: FileManager.SearchPathDirectory) -> (String, [String], Item) {
            let path = System.folder(dir)
            return (title, [], Item(id: path, title: title, subtitle: (path as NSString).abbreviatingWithTildeInPath,
                                    icon: .file(path), action: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }))
        }
        let login = System.launchAtLogin
        var list = [
            cmd("Clipboard History", ["clip", "cb", "paste"], "doc.on.clipboard", "Type clip to search it") { [weak self] in
                self?.show(query: "clip ")
            },
            cmd("Search Emoji", ["emoji", ":"], "face.smiling", "Type : then a name") { [weak self] in self?.show(query: ":") },
            cmd("Toggle Mute", ["mute", "unmute", "sound off"], "speaker.slash", "Sound") {
                System.script("set volume output muted not (output muted of (get volume settings))")
            },
            cmd(System.awake ? "Stop Keeping Awake" : "Keep Awake", ["caffeinate", "awake", "no sleep", "amphetamine"],
                "cup.and.saucer", System.awake ? "On · stops when Hop quits" : "Stops the Mac and display sleeping") { System.toggleAwake() },
            cmd("Lock Screen", ["lock"], "lock") { System.lock() },
            cmd("Sleep", ["sleep"], "moon") { System.sh("/usr/bin/pmset", ["sleepnow"]) },
            cmd("Sleep Displays", ["display off", "screen off"], "display") { System.sh("/usr/bin/pmset", ["displaysleepnow"]) },
            cmd("Start Screen Saver", ["screensaver"], "sparkles.tv") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
            },
            cmd("Toggle Dark Mode", ["dark", "light", "appearance", "theme"], "circle.lefthalf.filled") {
                System.script("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            },
            cmd("Hide Other Apps", ["focus", "declutter"], "eye.slash") {
                let front = NSWorkspace.shared.frontmostApplication
                for app in NSWorkspace.shared.runningApplications where app != front && app.activationPolicy == .regular { app.hide() }
            },
            cmd("Eject All Disks", ["unmount", "eject"], "eject") {
                System.script("tell application \"Finder\" to eject (every disk whose ejectable is true)")
            },
            cmd("Restart…", ["reboot"], "arrow.clockwise", "Shows the system confirmation") {
                System.script("tell application \"loginwindow\" to «event aevtrrst»")
            },
            cmd("Shut Down…", ["power off", "shutdown"], "power", "Shows the system confirmation") {
                System.script("tell application \"loginwindow\" to «event aevtrsdn»")
            },
            cmd("Log Out…", ["logout", "sign out"], "rectangle.portrait.and.arrow.right", "Shows the system confirmation") {
                System.script("tell application \"loginwindow\" to «event aevtlogo»")
            },
            folder("Downloads", .downloadsDirectory),
            folder("Desktop", .desktopDirectory),
            folder("Documents", .documentDirectory),
            folder("Home", .userDirectory),
            cmd("Save Current Page", ["bookmark", "add bookmark", "save page", "save tab"], "bookmark", "Adds the browser's front tab to your bookmarks") {
                [weak self] in
                guard let self else { return }
                if let title = Tabs.saveFront() { self.applyConfig(); self.show(query: title) } else { NSSound.beep() }
            },
            cmd("Hop Settings", ["settings", "preferences", "turn off", "disable", "hotkeys", "bookmarks"], "switch.2",
                "Features, hotkeys, bookmarks, snippets") {
                [weak self] in self?.onOpenSettings?()
            },
            cmd("Edit Hop Config", ["hotkeys", "snippets", "config"], "gearshape", Config.path) { Config.edit() },
            cmd("Save Clipboard as Snippet", ["snippet", "new snippet"], "text.badge.plus", "Adds it to config.json") {
                [weak self] in if Snippet.saveClipboard() { self?.applyConfig() }
            },
            cmd("Open Scripts Folder", ["plugins", "extensions", "script commands"], "terminal", Config.scriptsDir) { Config.openScripts() },
            cmd(login ? "Don't Launch Hop at Login" : "Launch Hop at Login", ["startup", "login"], "power.circle") {
                System.launchAtLogin = !login
            },
            cmd("Quit Hop", ["exit"], "xmark.circle") { NSApp.terminate(nil) },
        ]
        if !AXIsProcessTrusted() {
            list.append(cmd("Grant Accessibility Access", ["permissions", "windows", "menus", "paste"], "hand.raised",
                            "Needed for menu search, window switching and paste") {
                AX.ensureTrusted()
                SettingsPanes.openAccessibilityPrivacy()
            })
        }
        return list
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ t: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RowView() }

    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let cell = t.makeView(withIdentifier: .init("cell"), owner: nil) as? Cell ?? {
            let c = Cell(); c.identifier = .init("cell"); return c
        }()
        let item = items[row]
        let kind = Launcher.describe(item).kind
        cell.title.stringValue = item.title
        // The kind is on the right; drop it from the subtitle when it would just repeat ("Command").
        var sub = item.subtitle
        if sub == kind { sub = "" } else if sub.hasPrefix(kind + " · ") { sub = String(sub.dropFirst(kind.count + 3)) }
        cell.sub.stringValue = sub
        let id = item.id
        cell.icon.image = Icons.image(item.icon) { [weak self] in self?.iconArrived(id) }
        cell.hint.stringValue = kind
        cell.apply(Launcher.theme)
        cell.needsLayout = true
        return cell
    }

    func tableViewSelectionDidChange(_ n: Notification) { updateFooter() }

    /// Every app's icon goes to the disk cache once, in the background; rows then read them in
    /// well under a millisecond. Memory only keeps icons recently shown.
    private func prewarmIcons() {
        Icons.cacheAll(apps.all.map(\.path) + ["/System/Applications/System Settings.app",
                                                "/System/Applications/Shortcuts.app"])
    }

    /// An icon finished loading in the background: put it in its row if that row is still showing.
    private func iconArrived(_ id: String) {
        guard let r = items.firstIndex(where: { $0.id == id }),
              let cell = table.view(atColumn: 0, row: r, makeIfNecessary: false) as? Cell else { return }
        cell.icon.image = Icons.image(items[r].icon)
    }

    /// What a row is and what ↵ / ⌘↵ do, derived from its id so items stay plain data.
    static func describe(_ item: Item) -> (kind: String, verb: String, alt: String?) {
        let id = item.id
        let alt = item.alt == nil ? nil : "Show in Finder"
        if id.hasPrefix("/") {
            if id.hasSuffix(".app") { return ("Application", "Open", alt) }
            var dir: ObjCBool = false
            FileManager.default.fileExists(atPath: id, isDirectory: &dir)
            return (dir.boolValue ? "Folder" : "File", "Open", alt)
        }
        let table: [(String, String, String, String?)] = [
            ("menu-more", "Menu", "Show all", nil), ("cmd:", "Command", "Run", nil), ("pane:", "System Settings", "Open", nil), ("wm:", "Window", "Move", nil),
            ("snippet:", "Snippet", "Paste", "Copy"), ("link:", "Bookmark", "Open", nil), ("script:", "Script", "Run", nil),
            ("shortcut:", "Shortcut", "Run", nil), ("audio:", "Sound", "Switch", nil),
            ("win:", "Window", "Switch to", nil), ("tab:", "Tab", "Switch to", "Copy URL"), ("menu:", "Menu", "Click", nil),
            ("answer", "Answer", "Copy", "Paste"), ("google", "Web", "Search", nil), ("bang:", "Web", "Search", nil),
            ("url", "Web", "Open", nil), ("define", "Dictionary", "Open", "Copy"), ("emoji:", "Emoji", "Paste", "Copy"),
            ("clip:", "Clipboard", "Paste", "Copy"), ("quit:", "App", "Quit", nil), ("volume", "Sound", "Set", nil),
            ("out:", "Output", "Copy line", "Copy all"),
        ]
        if let m = table.first(where: { id.hasPrefix($0.0) }) { return (m.1, m.2, item.alt == nil ? nil : m.3) }
        return ("", "Open", nil)
    }

    private func updateFooter() {
        let r = table.selectedRow
        guard r >= 0, r < items.count else { footerLeft.stringValue = ""; footerRight.stringValue = ""; return }
        let d = Launcher.describe(items[r])
        footerRight.stringValue = d.verb + "  ↵" + (d.alt.map { "     \($0)  ⌘↵" } ?? "")
        // A pending update takes the hint's place rather than a result row, so it never competes with search.
        footerLeft.textColor = pendingUpdate == nil ? .secondaryLabelColor : Launcher.theme.accent.flatMap(Theme.color) ?? .controlAccentColor
        footerLeft.stringValue = pendingUpdate.map { "Update to \($0) available  ·  ⌘U" }
            ?? (welcoming ? "Welcome to Hop  ·  \(HotKeys.symbols(openCombo ?? "opt+space")) opens it anywhere" : nil)
            ?? (items[r].fill != nil ? "Tab completes  ·  ⌘1–9 quick open" : "⌘1–9 quick open")
    }
}
