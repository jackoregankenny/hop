import AppKit

/// ~/.config/hop/config.json (or $HOP_HOME). Everything is optional.
struct Config {
    struct Quicklink { let name: String; let url: String; let key: String? }

    /// ⌘Space only fires once Spotlight's shortcut is turned off; ⌥Space always works.
    static let defaultHotkeys = ["cmd+space": "show", "opt+space": "show"].merging(Snap.defaultHotkeys) { a, _ in a }
    var hotkeys = Config.defaultHotkeys
    var quicklinks: [Quicklink] = []
    var snapGap: CGFloat = 0
    var snippets: [Snippet] = []
    var theme = Theme()

    /// The hotkeys to register: window actions drop out when Window Snapping is off.
    static func active(_ hotkeys: [String: String], snapping: Bool) -> [String: String] {
        snapping ? hotkeys : hotkeys.filter { !Snap.actionNames.contains($0.value) }
    }

    static var dir: String {
        ProcessInfo.processInfo.environment["HOP_HOME"] ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config/hop")
    }
    static var path: String { (dir as NSString).appendingPathComponent("config.json") }
    static var scriptsDir: String { (dir as NSString).appendingPathComponent("scripts") }

    static func load() -> Config {
        var c = Config()
        guard let obj = raw() else { return c }
        c.hotkeys = HotKeys.merged(defaultHotkeys, obj["hotkeys"] as? [String: String])
        c.quicklinks = (obj["quicklinks"] as? [[String: String]] ?? []).compactMap { q in
            guard let name = q["name"], let url = q["url"] else { return nil }
            return Quicklink(name: name, url: url, key: q["key"]?.lowercased())
        }
        if let g = obj["snapGap"] as? Double { c.snapGap = CGFloat(g) }
        c.snippets = Snippet.parse(obj["snippets"] as? [[String: String]])
        c.theme = Theme.from(obj["theme"])
        return c
    }

    /// config.json as written; nil when it is missing or not a JSON object.
    static func raw() -> [String: Any]? {
        FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// Rewrites one top-level key of config.json and keeps the rest; nil or an empty list removes the key.
    /// The settings window, Save Page and Save Clipboard all write through here; ConfigWatch picks it up.
    static func update(_ key: String, _ change: (Any?) -> Any?) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var obj = raw() ?? [:]
        let v = change(obj[key])
        if v == nil || (v as? [Any])?.isEmpty == true || (v as? [String: Any])?.isEmpty == true { obj[key] = nil } else { obj[key] = v }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            fm.createFile(atPath: path, contents: data + Data("\n".utf8))
        }
    }

    /// Opens the config in the default editor, writing a commented example first if there is none.
    static func edit() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) { try? sample.write(toFile: path, atomically: true, encoding: .utf8) }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func openScripts() {
        try? FileManager.default.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: scriptsDir))
    }

    static let sample = """
    {
      "hotkeys": {
        "ctrl+opt+v": "Clipboard History",
        "ctrl+opt+shift+left": "Move Left",
        "ctrl+opt+shift+right": "Move Right",
        "cmd+space": "none"
      },
      "snapGap": 0,
      "theme": { "preset": "default", "accent": "#7c8cff" },
      "snippets": [
        { "name": "Today's date", "keyword": "today", "text": "{date}" },
        { "name": "Markdown link from clipboard", "keyword": "mdl", "text": "[link]({clipboard})" }
      ],
      "quicklinks": [
        { "name": "GitHub Notifications", "url": "https://github.com/notifications" },
        { "name": "npm", "key": "npm", "url": "https://www.npmjs.com/search?q={query}" },
        { "name": "crates.io", "key": "crates", "url": "https://crates.io/search?q={query}" },
        { "name": "MDN", "key": "mdn", "url": "https://developer.mozilla.org/search?q={query}" }
      ]
    }

    """
}

/// Script commands: executables in ~/.config/hop/scripts with metadata comments.
/// Raycast's script-command headers (@raycast.title, .mode, .icon, .argument1) are read as-is,
/// so scripts written for it run here unchanged; @hop.* works too (and @rayfast.*, Hop's old name).
struct Script {
    let path: String
    let title: String
    let mode: String          // silent | compact | inline | fullOutput
    let icon: String?
    let subtitle: String
    let argument: String?     // placeholder when the script takes an argument

    static func load(from dir: String = Config.scriptsDir) -> [Script] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let re = try? NSRegularExpression(pattern: #"@(?:raycast|rayfast|hop)\.([A-Za-z0-9]+)[ \t]+(.+?)\s*$"#, options: .anchorsMatchLines)
        return names.sorted().compactMap { name in
            let path = (dir as NSString).appendingPathComponent(name)
            guard !name.hasPrefix("."), let h = FileHandle(forReadingAtPath: path) else { return nil }
            let head = String(decoding: h.readData(ofLength: 4096), as: UTF8.self)
            try? h.close()
            var meta: [String: String] = [:]
            for m in re?.matches(in: head, range: NSRange(head.startIndex..., in: head)) ?? [] {
                if let k = Range(m.range(at: 1), in: head), let v = Range(m.range(at: 2), in: head) { meta[String(head[k])] = String(head[v]) }
            }
            guard let title = meta["title"] else { return nil }
            var placeholder: String?
            if let arg = meta["argument1"], let d = arg.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                placeholder = obj["placeholder"] as? String ?? "argument"
            }
            let sub = [meta["packageName"], meta["description"]].compactMap { $0 }.joined(separator: " · ")
            return Script(path: path, title: title, mode: meta["mode"] ?? "fullOutput", icon: meta["icon"],
                          subtitle: sub.isEmpty ? "Script" : sub, argument: placeholder)
        }
    }

    /// Runs off the main thread with a 30 s limit and a PATH that includes Homebrew.
    func run(_ arg: String?, done: @escaping (String, Int32) -> Void) {
        DispatchQueue.global().async {
            let exec = FileManager.default.isExecutableFile(atPath: path)   // otherwise zsh runs it
            let p = System.process(exec ? path : "/bin/zsh", (exec ? [] : [path]) + (arg.map { [$0] } ?? []))
            p.currentDirectoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch {
                DispatchQueue.main.async { done("Could not run: \(error.localizedDescription)", -1) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { if p.isRunning { p.terminate() } }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { done(out, p.terminationStatus) }
        }
    }
}

/// Applies config edits as soon as they are saved, by you or by an agent: watches the config
/// folder (atomic saves replace the file) and the file itself (in-place writes).
final class ConfigWatch {
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        try? FileManager.default.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)
        dirSource = watch(Config.dir, .write)
        fileSource = watch(Config.path, [.write, .extend, .delete, .rename])
    }

    private func watch(_ path: String, _ events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        s.setEventHandler { [weak self] in self?.changed() }
        s.setCancelHandler { close(fd) }
        s.resume()
        return s
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileSource?.cancel()   // a replaced file is a new inode; watch the new one
            self.fileSource = self.watch(Config.path, [.write, .extend, .delete, .rename])
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

/// `hop --check`: validates config.json and says exactly what is wrong, for people and agents.
enum ConfigCheck {
    static let topKeys: Set<String> = ["hotkeys", "snapGap", "snippets", "quicklinks", "theme"]
    static let themeKeys = Set(["preset", "appearance", "blur", "background", "accent", "font"]).union(Theme.limits.keys)

    /// `known`: lowercased names a hotkey may run (commands, apps, snippets, scripts, quicklinks).
    static func run(text: String?, known: Set<String>) -> (errors: [String], warnings: [String], summary: String) {
        var errors: [String] = [], warnings: [String] = []
        guard let text else { return ([], [], "no config file; defaults in use") }
        let obj: [String: Any]
        do {
            guard let o = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                return (["the top level must be a JSON object { … }"], [], "")
            }
            obj = o
        } catch {
            let detail = (error as NSError).userInfo["NSDebugDescription"] as? String ?? error.localizedDescription
            return (["invalid JSON: \(detail)"], [], "")
        }
        func suggest(_ k: String, _ options: Set<String>) -> String {
            options.min { Match.osa(k.lowercased(), $0.lowercased()) < Match.osa(k.lowercased(), $1.lowercased()) }
                .map { Match.osa(k.lowercased(), $0.lowercased()) <= 3 ? " (did you mean \"\($0)\"?)" : "" } ?? ""
        }
        for k in obj.keys.sorted() where !topKeys.contains(k) { errors.append("unknown key \"\(k)\"\(suggest(k, topKeys))") }

        var hotkeyCount = 0
        if let v = obj["hotkeys"] {
            if let hk = v as? [String: String] {
                for (combo, action) in hk.sorted(by: { $0.key < $1.key }) {
                    hotkeyCount += 1
                    if HotKeys.parse(combo) == nil {
                        errors.append("hotkeys.\"\(combo)\": can't read this combo; use modifiers cmd, opt, ctrl, shift and a key "
                                      + "like a, 1, left, return, space, minus, equal, delete, f1")
                    }
                    let a = action.trimmingCharacters(in: .whitespaces).lowercased()
                    if !(a.isEmpty || a == "none" || known.contains(a)) {
                        warnings.append("hotkeys.\"\(combo)\": nothing is called \"\(action)\"\(suggest(a, known)); "
                                        + "use \"show\", a command, app, snippet, script or quicklink name, or \"none\"")
                    }
                }
            } else { errors.append("hotkeys must be an object of \"combo\": \"action\" strings") }
        }
        if let v = obj["snapGap"], !(v is NSNumber) { errors.append("snapGap must be a number") }
        let snippets = obj["snippets"] as? [[String: Any]]
        if obj["snippets"] != nil && snippets == nil { errors.append("snippets must be an array of objects") }
        for (i, s) in (snippets ?? []).enumerated() {
            if !(s["text"] is String) { errors.append("snippets[\(i)]: needs \"text\"") }
            if !(s["name"] is String || s["keyword"] is String) { errors.append("snippets[\(i)]: needs a \"name\" or \"keyword\"") }
        }
        let links = obj["quicklinks"] as? [[String: Any]]
        if obj["quicklinks"] != nil && links == nil { errors.append("quicklinks must be an array of objects") }
        for (i, l) in (links ?? []).enumerated() {
            if !(l["name"] is String) { errors.append("quicklinks[\(i)]: needs \"name\"") }
            if let u = l["url"] as? String { if URL(string: u.replacingOccurrences(of: "{query}", with: "x")) == nil {
                errors.append("quicklinks[\(i)]: \"url\" is not a URL") } } else { errors.append("quicklinks[\(i)]: needs \"url\"") }
        }
        var themeName = "default"
        switch obj["theme"] {
        case nil: break
        case let name as String:
            themeName = name
            if Theme.presets[name.lowercased()] == nil {
                errors.append("theme: no preset \"\(name)\"; presets are \(Theme.presets.keys.sorted().joined(separator: ", "))")
            }
        case let d as [String: Any]:
            themeName = (d["preset"] as? String ?? "default") + " + overrides"
            for k in d.keys.sorted() where !themeKeys.contains(k) { errors.append("theme: unknown key \"\(k)\"\(suggest(k, themeKeys))") }
            if let p = d["preset"] as? String, Theme.presets[p.lowercased()] == nil { errors.append("theme.preset: no preset \"\(p)\"") }
            for k in ["background", "accent"] { if let c = d[k] as? String, Theme.color(c) == nil {
                errors.append("theme.\(k): \"\(c)\" is not a colour; use #rgb, #rrggbb or #rrggbbaa") } }
            for (k, options) in [("blur", Theme.blurs), ("appearance", Theme.appearances)] {
                if let v = d[k] as? String, !options.contains(v.lowercased()) { errors.append("theme.\(k): use one of \(options.sorted().joined(separator: ", "))") }
            }
            for k in Theme.limits.keys.sorted() where d[k] != nil && !(d[k] is NSNumber) {
                errors.append("theme.\(k) must be a number")
            }
        default: errors.append("theme must be a preset name or an object")
        }
        let summary = "\(hotkeyCount) hotkeys, \(snippets?.count ?? 0) snippets, \(links?.count ?? 0) quicklinks, theme \(themeName)"
        return (errors, warnings, summary)
    }
}
