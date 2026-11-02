import AppKit

/// On/off switches in the menu bar menu. Everything defaults to on; turning something off stops it
/// entirely (no timers, no hotkeys, no network, no Apple Events) rather than just hiding results.
enum Feature: String, CaseIterable {
    case windowSnapping, clipboardHistory, browserTabs, exchangeRates, fileSearch, automaticUpdates

    var title: String {
        switch self {
        case .windowSnapping: return "Window Snapping"
        case .clipboardHistory: return "Clipboard History"
        case .browserTabs: return "Browser Tabs"
        case .exchangeRates: return "Exchange Rates"
        case .fileSearch: return "File Search"
        case .automaticUpdates: return "Automatic Updates"
        }
    }

    var detail: String {
        switch self {
        case .windowSnapping: return "Halves, thirds, quarters and their ⌃⌥ hotkeys"
        case .clipboardHistory: return "Remembers copied text while Rayfast runs"
        case .browserTabs: return "Searches open tabs in Safari, Orion and Chromium browsers"
        case .exchangeRates: return "Live ECB rates for things like 100 usd to eur (the only network call)"
        case .fileSearch: return "Spotlight file results"
        case .automaticUpdates: return "Checks GitHub Releases every few hours and installs while Rayfast is closed"
        }
    }

    var isOn: Bool {
        get { UserDefaults.standard.object(forKey: "feature." + rawValue) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "feature." + rawValue) }
    }
}

/// Text you paste from the launcher. Lives in config.json next to hotkeys and quicklinks:
/// "snippets": [{ "name": "Sign-off", "keyword": "sig", "text": "Thanks,\n{clipboard}" }]
struct Snippet {
    let name: String
    let keyword: String?
    let text: String

    /// {date}, {time}, {datetime}, {clipboard}
    func expanded(now: Date = Date(), clipboard: String? = NSPasteboard.general.string(forType: .string)) -> String {
        let f = DateFormatter()
        var out = text
        for (token, style) in [("{datetime}", (DateFormatter.Style.medium, DateFormatter.Style.short)),
                               ("{date}", (.medium, .none)), ("{time}", (.none, .short))] where out.contains(token) {
            f.dateStyle = style.0
            f.timeStyle = style.1
            out = out.replacingOccurrences(of: token, with: f.string(from: now))
        }
        return out.replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
    }

    static func parse(_ list: [[String: String]]?) -> [Snippet] {
        (list ?? []).compactMap { d in
            guard let text = d["text"], let name = d["name"] ?? d["keyword"] else { return nil }
            return Snippet(name: name, keyword: d["keyword"]?.lowercased(), text: text)
        }
    }

    /// Appends a snippet to config.json, keeping everything else in it.
    static func save(_ text: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)
        var obj = (fm.contents(atPath: Config.path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        var list = obj["snippets"] as? [[String: String]] ?? []
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        list.append(["name": String(first.trimmingCharacters(in: .whitespaces).prefix(40)), "text": text])
        obj["snippets"] = list
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            fm.createFile(atPath: Config.path, contents: data)
        }
    }
}
