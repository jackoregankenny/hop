import AppKit

/// ~/.config/rayfast/config.json (or $RAYFAST_HOME). Everything is optional.
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
        ProcessInfo.processInfo.environment["RAYFAST_HOME"] ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config/rayfast")
    }
    static var path: String { (dir as NSString).appendingPathComponent("config.json") }
    static var scriptsDir: String { (dir as NSString).appendingPathComponent("scripts") }

    static func load() -> Config {
        var c = Config()
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
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

    /// Opens the config in the default editor, writing a commented example first if there is none.
    static func edit() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: path) { try? sample.write(toFile: path, atomically: true, encoding: .utf8) }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
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

/// Script commands: executables in ~/.config/rayfast/scripts with metadata comments.
/// Raycast's script-command headers (@raycast.title, .mode, .icon, .argument1) are read as-is,
/// so scripts written for it run here unchanged; @rayfast.* works too.
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
        let re = try? NSRegularExpression(pattern: #"@ray(?:cast|fast)\.([A-Za-z0-9]+)[ \t]+(.+?)\s*$"#, options: .anchorsMatchLines)
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
            let p = Process()
            if FileManager.default.isExecutableFile(atPath: path) {
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = arg.map { [$0] } ?? []
            } else {
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = [path] + (arg.map { [$0] } ?? [])
            }
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
