import AppKit
import CryptoKit
import ServiceManagement

struct Item {
    enum Icon { case file(String), symbol(String), text(String), image(NSImage) }
    var id: String
    var title: String
    var subtitle = ""
    var icon: Icon = .symbol("circle")
    var fill: String? = nil            // what Tab puts in the field
    var keepOpen = false               // runs without closing the panel (scripts that print output)
    var action: () -> Void
    var alt: (() -> Void)? = nil        // ⌘↵
}

/// Icons, never decoded on the main thread. NSWorkspace hands back lazy images whose real
/// decoding happens at first draw (18 ms each when macOS's own cache is cold), so:
/// - at launch every app's icon is drawn once into a small PNG under ~/Library/Caches (keyed by
///   path and modification date, so an updated app gets a fresh icon), at low priority;
/// - a row asks for its icon and gets it from that PNG on a background queue in well under 1 ms;
/// - memory holds only icons recently shown (bounded), not all of them.
enum Icons {
    private static let memory: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 150; return c }()
    private static var waiting: [String: [() -> Void]] = [:]   // main thread only
    private static var loading = Set<String>()                 // main thread only
    private static let urgent = DispatchQueue(label: "hop.icons", qos: .userInitiated)
    private static let idle = DispatchQueue(label: "hop.icons.cache", qos: .utility)
    static let points: CGFloat = 36                            // the largest a row draws them

    static var cacheDir: URL = {
        let base = ProcessInfo.processInfo.environment["HOP_CACHE"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "hop")
        let dir = base.appendingPathComponent("icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The icon if it is ready; otherwise nil, with `ready` called on the main thread once it is.
    static func image(_ icon: Item.Icon, ready: (() -> Void)? = nil) -> NSImage? {
        switch icon {
        case .file(let path):
            if let img = memory.object(forKey: path as NSString) { return img }
            if let ready { waiting[path, default: []].append(ready) }
            guard loading.insert(path).inserted else { return nil }
            urgent.async {
                let img = cached(path) ?? render(path)
                DispatchQueue.main.async {
                    memory.setObject(img, forKey: path as NSString)
                    loading.remove(path)
                    waiting.removeValue(forKey: path)?.forEach { $0() }
                }
            }
            return nil
        case .image(let img): return img   // already a small thumbnail
        case .symbol(let name):
            return memo("s:" + name) {
                NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            }
        case .text(let t):
            return memo("t:" + t) {
                NSImage(size: NSSize(width: 28, height: 28), flipped: false) { r in
                    let s = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: 22)])
                    let sz = s.size()
                    s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2))
                    return true
                }
            }
        }
    }

    /// The image in memory under `key`, made and kept the first time.
    private static func memo(_ key: String, _ make: () -> NSImage?) -> NSImage? {
        if let img = memory.object(forKey: key as NSString) { return img }
        let img = make()
        if let img { memory.setObject(img, forKey: key as NSString) }
        return img
    }

    /// Makes sure every app has an icon on disk, in the background at low priority. Already
    /// cached icons cost one stat each; nothing is kept in memory.
    static func cacheAll(_ paths: [String], wait: Bool = false) {
        let work = { for p in paths where !FileManager.default.fileExists(atPath: file(for: p).path) { _ = render(p) } }
        if wait { idle.sync(execute: work) } else { idle.async(execute: work) }
    }

    /// Path plus modification date, so an app that is updated gets its new icon.
    private static func file(for path: String) -> URL {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .map { $0.timeIntervalSince1970 } ?? 0
        let digest = SHA256.hash(data: Data("\(path)|\(mtime)".utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(digest + ".png")
    }

    /// Reads the PNG into the same premultiplied bitmap a fresh render produces. Loading it as-is
    /// leaves a format AppKit converts on every draw, which costs ~0.2 ms per icon on the main thread.
    private static func cached(_ path: String) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(file(for: path) as CFURL, nil),
              let png = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let cg = bitmap({ $0.draw(png, in: CGRect(x: 0, y: 0, width: $1, height: $1)) }) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: points, height: points))
    }

    /// A 2x premultiplied sRGB bitmap the size of a row icon: the cheapest thing for AppKit to draw.
    private static func bitmap(_ draw: (CGContext, Int) -> Void) -> CGImage? {
        let px = Int(points * 2)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx, px)
        return ctx.makeImage()
    }

    /// Draws the icon once into a 2x bitmap and stores it as PNG; later draws are a plain image copy.
    private static func render(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        guard let cg = bitmap({ ctx, px in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
        }) else { return icon }
        // Only app bundles go to disk: their icons are stable, while plain files come and go.
        if path.hasSuffix(".app"), let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: file(for: path), options: .atomic)
        }
        return NSImage(cgImage: cg, size: NSSize(width: points, height: points))
    }
}

enum Web {
    static let urlSafe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: urlSafe) ?? s }
    static func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    static func google(_ q: String) -> String { "https://www.google.com/search?q=\(enc(q))" }

    // "yt lofi" -> YouTube search for "lofi"
    static let bangs: [(key: String, name: String, symbol: String, url: (String) -> String)] = [
        ("g", "Google", "magnifyingglass", google),
        ("x", "X", "at", { "https://x.com/search?q=\(enc($0))" }),
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

    func refresh() { System.background(Apps.scan, qos: .utility) { self.set($0) } }

    private func set(_ found: [App]) {
        guard found != all else { return }
        all = found
        onChange?()
    }

    static func scan() -> [App] {
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

final class Clipboard {
    /// Text, or an image kept as the bytes that were copied plus a small thumbnail for its row.
    enum Clip: Equatable {
        case text(String)
        case image(Data, NSPasteboard.PasteboardType, thumb: NSImage, size: CGSize)
        static func == (a: Clip, b: Clip) -> Bool {
            switch (a, b) {
            case let (.text(x), .text(y)): return x == y
            case let (.image(x, _, _, _), .image(y, _, _, _)): return x == y
            default: return false
            }
        }
    }

    private(set) var items: [Clip] = []      // in memory only, never written to disk
    private var change = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var lastAdded = Date.distantPast
    private var lastTransient = Date.distantPast
    /// Passwords stay out. Transient text is kept: dictation apps (Wispr Flow, Granola…) mark what
    /// they paste that way, and it is exactly what you want back later.
    private static let skip: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"), .init("com.agilebits.onepassword"),
    ]
    private static let maxImages = 12, maxImageBytes = 30_000_000

    /// Off means no polling at all and nothing remembered.
    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            timer?.invalidate()
            timer = nil
            items = []
            guard enabled else { return }
            change = NSPasteboard.general.changeCount
            // Fast enough to catch dictation apps, which paste and then put your old clipboard back
            // within a fraction of a second. A changeCount read is a cheap check, so this costs next to nothing.
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
            timer?.tolerance = 0.1
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != change else { return }
        change = pb.changeCount
        let types = pb.types ?? []
        if types.contains(where: Clipboard.skip.contains) { return }
        let transient = types.contains(.init("org.nspasteboard.TransientType"))
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.text(s), transient: transient)
        } else if let type = [NSPasteboard.PasteboardType.png, .tiff].first(where: types.contains),
                  let data = pb.data(forType: type), data.count <= Clipboard.maxImageBytes, let clip = Clipboard.image(data, type) {
            add(clip)
        }
    }

    func add(_ clip: Clip, transient: Bool = false, now: Date = Date()) {
        // A dictation app putting back what was on the clipboard before: the dictated text stays on top.
        if items.count > 1, items[1] == clip, now.timeIntervalSince(lastAdded) < 3 { return }
        let restore = !transient && now.timeIntervalSince(lastTransient) < 1.5
        items.removeAll { $0 == clip }
        items.insert(clip, at: restore && !items.isEmpty ? 1 : 0)
        lastTransient = transient ? now : .distantPast   // only the very next change counts as the restore
        lastAdded = now
        var images = 0
        items = items.filter { if case .image = $0 { images += 1; return images <= Clipboard.maxImages }; return true }
        if items.count > 100 { items.removeLast() }
    }

    /// A thumbnail decoded at row size (fast, and the full image is never drawn).
    static func image(_ data: Data, _ type: NSPasteboard.PasteboardType) -> Clip? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: 72,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return .image(data, type, thumb: NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2)),
                      size: CGSize(width: w, height: h))
    }

    func copy(_ s: String) { copy(.text(s)) }

    func copy(_ clip: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip {
        case .text(let s): pb.setString(s, forType: .string)
        case let .image(data, type, _, _): pb.setData(data, forType: type)
        }
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
    /// Points per doubling of recent use: 1 use ≈ 80, 3 ≈ 160, 10 ≈ 280, 30 ≈ 400. Enough for something
    /// you open all the time to beat a slightly better name match (a word start is 140 below a prefix).
    static let weight = 80.0

    private static var frecency = UserDefaults.standard.dictionary(forKey: "frecency") as? [String: [Double]] ?? [:]   // id -> [score, last opened]
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

    static func bonus(_ id: String, query: String) -> Double { scorer(query: query)(id) }

    /// Usage points for any id, for one query: frecency, plus the share of picks for this query, or
    /// half that for its longest shorter prefix with any. Gathers the pick history once, so ranking on
    /// every keystroke costs a few dictionary lookups per item.
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
            if let e = f[id] { b += weight * log2(1 + decayed(e[0], since: e[1], now: now)) }
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
        UserDefaults.standard.set(picks, forKey: "picks")
    }
}

enum System {
    /// A process for the tool at `path`, not started yet.
    static func process(_ path: String, _ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        return p
    }

    static func sh(_ path: String, _ args: [String]) { try? process(path, args).run() }

    /// Runs `work` off the main thread and hands what it returns to `then` on the main thread.
    static func background<T>(_ work: @escaping () -> T, qos: DispatchQoS.QoSClass = .userInitiated, then: @escaping (T) -> Void) {
        DispatchQueue.global(qos: qos).async {
            let result = work()
            DispatchQueue.main.async { then(result) }
        }
    }

    /// Runs a tool and returns its stdout. Call off the main thread for anything slow.
    static func run(_ path: String, _ args: [String]) -> String {
        let p = process(path, args)
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
        let p = process("/usr/bin/caffeinate", ["-di", "-w", String(getpid())])
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
