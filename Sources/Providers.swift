import AppKit
import ServiceManagement

struct Item {
    enum Icon { case file(String), symbol(String), text(String) }
    var id: String
    var title: String
    var subtitle = ""
    var icon: Icon = .symbol("circle")
    var fill: String? = nil            // what Tab puts in the field
    var keepOpen = false               // runs without closing the panel (scripts that print output)
    var action: () -> Void
    var alt: (() -> Void)? = nil        // ⌘↵
}

/// Icons, loaded off the main thread. NSWorkspace hands back lazy images whose real decoding
/// happens at first draw (18 ms each when macOS's own cache is cold), so file icons are fetched
/// *and drawn* into a small bitmap on a background queue; rows show them as they arrive.
enum Icons {
    private static var cache: [String: NSImage] = [:]          // main thread only
    private static var waiting: [String: [() -> Void]] = [:]   // main thread only
    private static var loading = Set<String>()                 // main thread only
    private static let urgent = DispatchQueue(label: "hop.icons", qos: .userInitiated)
    private static let idle = DispatchQueue(label: "hop.icons.prewarm", qos: .utility)
    static let points: CGFloat = 36                            // the largest a row draws them

    /// The icon if it is ready; otherwise nil, with `ready` called on the main thread once it is.
    static func image(_ icon: Item.Icon, ready: (() -> Void)? = nil) -> NSImage? {
        switch icon {
        case .file(let path):
            if let img = cache[path] { return img }
            if let ready { waiting[path, default: []].append(ready) }
            load(path, on: urgent)
            return nil
        case .symbol(let name):
            if let img = cache["s:" + name] { return img }
            let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            cache["s:" + name] = img
            return img
        case .text(let t):
            if let img = cache["t:" + t] { return img }
            let img = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { r in
                let s = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: 22)])
                let sz = s.size()
                s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2))
                return true
            }
            cache["t:" + t] = img
            return img
        }
    }

    /// Loads icons ahead of time at low priority, so they are ready before anyone types.
    static func prewarm(_ paths: [String]) {
        for p in paths where cache[p] == nil { load(p, on: idle) }
    }

    private static func load(_ path: String, on queue: DispatchQueue) {
        guard loading.insert(path).inserted else { return }
        queue.async {
            let img = render(path)
            DispatchQueue.main.async {
                cache[path] = img
                loading.remove(path)
                waiting.removeValue(forKey: path)?.forEach { $0() }
            }
        }
    }

    /// Draws the icon once into a 2x bitmap, so later draws are a plain image copy.
    private static func render(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let px = Int(points * 2)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return icon }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return icon }
        return NSImage(cgImage: cg, size: NSSize(width: points, height: points))
    }
}

enum Web {
    static let urlSafe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: urlSafe) ?? s }
    static func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    static func google(_ q: String) -> String { "https://www.google.com/search?q=\(enc(q))" }
    static func x(_ q: String) -> String { "https://x.com/search?q=\(enc(q))" }

    // "yt lofi" -> YouTube search for "lofi"
    static let bangs: [(key: String, name: String, symbol: String, url: (String) -> String)] = [
        ("g", "Google", "magnifyingglass", google),
        ("x", "X", "at", x),
        ("yt", "YouTube", "play.rectangle", { "https://www.youtube.com/results?search_query=\(enc($0))" }),
        ("gh", "GitHub", "chevron.left.forwardslash.chevron.right", { "https://github.com/search?q=\(enc($0))" }),
        ("wiki", "Wikipedia", "book", { "https://en.wikipedia.org/w/index.php?search=\(enc($0))" }),
        ("maps", "Maps", "map", { "https://maps.apple.com/?q=\(enc($0))" }),
        ("ddg", "DuckDuckGo", "magnifyingglass", { "https://duckduckgo.com/?q=\(enc($0))" }),
        ("r", "Reddit", "bubble.left.and.bubble.right", { "https://www.reddit.com/search/?q=\(enc($0))" }),
    ]

    static func looksLikeURL(_ q: String) -> String? {
        if q.contains(" ") || !q.contains(".") { return nil }
        if q.hasPrefix("http://") || q.hasPrefix("https://") { return q }
        let host = q.split(separator: "/").first.map(String.init) ?? q
        guard let tld = host.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              host.split(separator: ".").count >= 2 else { return nil }
        return "https://\(q)"
    }

    private static var rates: [String: [String: Double]] = [:]
    static func currency(_ amount: Double, _ from: String, _ to: String, _ done: @escaping (String?) -> Void) {
        let finish: ([String: Double]) -> Void = { r in
            done(r[to].map { "\(Calc.format((amount * $0 * 100).rounded() / 100)) \(to)" })
        }
        if let r = rates[from] { finish(r); return }
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=\(from)") else { return done(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let r = obj?["rates"] as? [String: Double] ?? [:]
            DispatchQueue.main.async {
                if !r.isEmpty { rates[from] = r }
                finish(r)
            }
        }.resume()
    }
}

final class Apps {
    struct App: Equatable { let name: String; let path: String }
    private(set) var all: [App] = []
    var onChange: (() -> Void)?

    /// Synchronous scan, for command-line checks.
    func refreshNow() { set(Apps.scan()) }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let found = Apps.scan()
            DispatchQueue.main.async { self.set(found) }
        }
    }

    private func set(_ found: [App]) {
        guard found != all else { return }
        all = found
        onChange?()
    }

    static func scan() -> [App] {
        do {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser.path
            let roots = ["/Applications", "/System/Applications", "\(home)/Applications",
                         "/System/Library/CoreServices/Applications"]
            var seen = Set<String>(), found: [App] = []
            func add(_ path: String) {
                guard seen.insert(path).inserted else { return }
                var name = fm.displayName(atPath: path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                found.append(App(name: name, path: path))
            }
            for root in roots {
                for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !entry.hasPrefix(".") {
                    let path = "\(root)/\(entry)"
                    if entry.hasSuffix(".app") { add(path); continue }
                    // One level of folders, e.g. /Applications/Utilities or vendor folders.
                    for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where sub.hasSuffix(".app") {
                        add("\(path)/\(sub)")
                    }
                }
            }
            add("/System/Library/CoreServices/Finder.app")
            return found
        }
    }
}

final class Clipboard {
    private(set) var items: [String] = []      // in memory only, never written to disk
    private var change = NSPasteboard.general.changeCount
    private var timer: Timer?
    private static let skip: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType"),
        .init("com.agilebits.onepassword"),
    ]

    /// Off means no polling at all and nothing remembered.
    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            timer?.invalidate()
            timer = nil
            items = []
            guard enabled else { return }
            change = NSPasteboard.general.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.poll() }
            timer?.tolerance = 0.4
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != change else { return }
        change = pb.changeCount
        if let types = pb.types, types.contains(where: Clipboard.skip.contains) { return }
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 100 { items.removeLast() }
    }

    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

/// Spotlight file results, filtered to what a person would look for from a launcher.
/// The main signal is whether you ever opened the file: macOS records a last-used date for files
/// opened through Finder or an app, and generated, cloned or unzipped files never get one.
final class Files {
    struct Hit { let path: String; let lastUsed: Date?; let useCount: Int; let types: [String] }

    private var query: NSMetadataQuery?
    private var token: NSObjectProtocol?

    /// Folders full of things nobody opens by name.
    static let noise = ["/node_modules/", "/target/", "/build/", "/dist/", "/out/", "/DerivedData/", "/vendor/",
                        "/__pycache__/", "/site-packages/", "/Pods/", "/coverage/", "/venv/", "/env/"]
    /// File kinds that only make sense inside an editor or a project.
    static let codeTypes = ["public.source-code", "public.script", "public.json", "public.xml", "public.yaml",
                            "public.log", "com.apple.property-list", "public.comma-separated-values-text"]
    /// Where new files you have not opened yet still deserve a look.
    static let inboxes = ["Desktop", "Documents", "Downloads"]

    static func keep(_ h: Hit, home: String) -> Bool {
        let parts = h.path.split(separator: "/").map(String.init)
        // Hidden folders and ~/Library are app internals, opened or not.
        if parts.dropLast().contains(where: { $0.hasPrefix(".") }) || h.path.contains("/Library/") { return false }
        if h.lastUsed != nil { return true }   // you opened it, so it is yours
        if noise.contains(where: h.path.contains) { return false }
        if h.types.contains(where: codeTypes.contains) { return false }
        // Never opened: only near the top of Desktop, Documents or Downloads (e.g. ~/Downloads/x.pdf,
        // ~/Documents/Taxes/x.pdf), not buried inside a project.
        guard h.path.hasPrefix(home + "/") else { return false }
        let rel = h.path.dropFirst(home.count + 1).split(separator: "/")
        return rel.count <= 3 && inboxes.contains(String(rel[0]))
    }

    /// Name match, plus recency (halves every 30 days), plus how often it was opened.
    static func rank(_ h: Hit, match: Double, now: Date = Date()) -> Double {
        var s = match + 12 * log2(1 + Double(h.useCount))
        if let used = h.lastUsed { s += 40 + 160 * pow(0.5, max(0, now.timeIntervalSince(used)) / (30 * 86_400)) }
        return s
    }

    func search(_ q: String, _ done: @escaping ([String]) -> Void) {
        cancel()
        let mq = NSMetadataQuery()
        mq.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@ AND kMDItemContentType != 'com.apple.application-bundle'", q)
        mq.searchScopes = [NSMetadataQueryUserHomeScope]
        mq.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]   // opened files first
        token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: mq, queue: .main) { [weak self] _ in
            mq.disableUpdates()
            let home = NSHomeDirectory()
            var ranked: [(Double, String)] = []
            for i in 0..<min(mq.resultCount, 300) {
                guard let item = mq.result(at: i) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                let hit = Hit(path: path, lastUsed: item.value(forAttribute: "kMDItemLastUsedDate") as? Date,
                              useCount: (item.value(forAttribute: "kMDItemUseCount") as? Int) ?? 0,
                              types: (item.value(forAttribute: "kMDItemContentTypeTree") as? [String]) ?? [])
                guard Files.keep(hit, home: home),
                      let m = Match.score(q, (path as NSString).lastPathComponent), m >= 650 else { continue }
                ranked.append((Files.rank(hit, match: m) + Usage.bonus(path, query: q), path))
            }
            self?.cancel()
            done(ranked.sorted { $0.0 > $1.0 }.prefix(5).map(\.1))
        }
        query = mq
        mq.start()
    }

    func cancel() {
        query?.stop()
        query = nil
        if let t = token { NotificationCenter.default.removeObserver(t) }
        token = nil
    }
}

/// Light usage weighting. Two signals, both cheap and stored in UserDefaults:
/// - frecency: every open adds 1 to a score that halves each week, so what you use now outranks
///   what you used a lot months ago, and something you stop using fades out on its own;
/// - picks: what you chose for this exact query (or a shorter prefix of it). Each pick shrinks the
///   other choices for that query, so switching from Hop Settings to System Settings for "se"
///   takes a pick or two, not weeks.
enum Usage {
    static let halfLife: Double = 7 * 86_400

    private static var frecency: [String: [Double]] = {   // id -> [score, last opened]
        if let f = UserDefaults.standard.dictionary(forKey: "frecency") as? [String: [Double]] { return f }
        let old = UserDefaults.standard.dictionary(forKey: "usage") as? [String: Double] ?? [:]   // earlier plain counts
        let now = Date().timeIntervalSince1970
        return old.mapValues { [$0, now] }
    }()
    private static var picks = UserDefaults.standard.dictionary(forKey: "picks") as? [String: [String: Double]] ?? [:]

    static func decayed(_ score: Double, since last: Double, now: Double) -> Double {
        score * pow(0.5, max(0, now - last) / halfLife)
    }

    /// Adds a pick for `id` and fades the other picks for the same query.
    static func pick(_ m: [String: Double], _ id: String) -> [String: Double] {
        var out = m.mapValues { $0 * 0.6 }.filter { $0.value >= 0.05 }
        out[id, default: 0] += 1
        return out
    }

    static func bonus(_ id: String, query: String, now: Double = Date().timeIntervalSince1970,
                      picks: [String: [String: Double]] = picks, frecency: [String: [Double]] = frecency) -> Double {
        var b = 0.0
        if let f = frecency[id] { b += 45 * log2(1 + decayed(f[0], since: f[1], now: now)) }
        let q = query.lowercased()
        for n in stride(from: q.count, through: 1, by: -1) {
            guard let m = picks[String(q.prefix(n))], let c = m[id] else { continue }
            b += 400 * (c / m.values.reduce(0, +)) * (n == q.count ? 1 : 0.5)
            break
        }
        return b
    }

    /// `bonus` for many items at once: gathers this query's pick history a single time (only the
    /// prefixes that have any), then scores each item with a few dictionary lookups. Same result as
    /// `bonus`; used for ranking on every keystroke.
    static func scorer(query: String, now: Double = Date().timeIntervalSince1970,
                       picks: [String: [String: Double]] = picks, frecency: [String: [Double]] = frecency) -> (String) -> Double {
        let q = query.lowercased()
        let history: [(picks: [String: Double], total: Double, weight: Double)] =
            stride(from: q.count, through: 1, by: -1).compactMap { n in
                picks[String(q.prefix(n))].map { ($0, $0.values.reduce(0, +), n == q.count ? 1 : 0.5) }
            }
        let f = frecency
        return { id in
            var b = 0.0
            if let e = f[id] { b += 45 * log2(1 + decayed(e[0], since: e[1], now: now)) }
            if let h = history.first(where: { $0.picks[id] != nil }) { b += 400 * (h.picks[id]! / h.total) * h.weight }
            return b
        }
    }

    static func bump(_ id: String, query: String) {
        let now = Date().timeIntervalSince1970
        let f = frecency[id] ?? [0, now]
        frecency[id] = [decayed(f[0], since: f[1], now: now) + 1, now]
        let q = query.lowercased()
        if !q.isEmpty && q.count <= 24 { picks[q] = pick(picks[q] ?? [:], id) }
        // Keep it small: drop things that have faded to almost nothing.
        if frecency.count > 500 { frecency = frecency.filter { decayed($0.value[0], since: $0.value[1], now: now) > 0.05 } }
        UserDefaults.standard.set(frecency, forKey: "frecency")
        UserDefaults.standard.removeObject(forKey: "usage")
        UserDefaults.standard.set(picks, forKey: "picks")
    }
}

enum System {
    static func sh(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// Runs a tool and returns its stdout. Call off the main thread for anything slow.
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func osascript(_ src: String) -> String { run("/usr/bin/osascript", ["-e", src]) }

    private static var caffeinate: Process?
    static var awake: Bool { caffeinate?.isRunning == true }
    /// caffeinate -w ties it to our pid, so it can never outlive Hop.
    static func toggleAwake() {
        if awake { caffeinate?.terminate(); caffeinate = nil; return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-di", "-w", String(getpid())]
        try? p.run()
        caffeinate = p
    }

    static func script(_ src: String) {
        DispatchQueue.global().async {
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
        }
    }

    static func lock() {
        // SACLockScreenImmediate is what the Control Center "Lock Screen" item calls.
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(h, "SACLockScreenImmediate") {
            typealias Fn = @convention(c) () -> Int32
            _ = unsafeBitCast(sym, to: Fn.self)()
        } else {
            sh("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }

    static func folder(_ dir: FileManager.SearchPathDirectory) -> String {
        FileManager.default.urls(for: dir, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    }
}
