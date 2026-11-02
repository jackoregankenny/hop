import AppKit

/// On/off switches in the menu bar menu. Everything defaults to on; turning something off stops it
/// entirely (no timers, no hotkeys, no network, no Apple Events) rather than just hiding results.
enum Feature: String, CaseIterable {
    case windowSnapping, clipboardHistory, browserTabs, exchangeRates, fileSearch
    /// Keeps its old key, so a switch turned off before updates became opt-in stays off.
    case updateChecks = "automaticUpdates"

    /// Its name and one line on what it does, for Settings › General.
    var text: (title: String, detail: String) {
        switch self {
        case .windowSnapping: return ("Window Snapping", "Halves, thirds, quarters and their ⌃⌥ hotkeys")
        case .clipboardHistory: return ("Clipboard History", "Remembers copied text and images while Hop runs (dictation included)")
        case .browserTabs: return ("Browser Tabs", "Searches open tabs in Safari, Orion and Chromium browsers")
        case .exchangeRates: return ("Exchange Rates", "Live ECB rates for things like 100 usd to eur (the only network call)")
        case .fileSearch: return ("File Search", "Spotlight file results")
        case .updateChecks: return ("Check for Updates", "Looks at GitHub Releases every few hours; installs only when you choose to")
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

    /// Saves the clipboard's text as a snippet. False when there is no text to save.
    static func saveClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return false }
        save(text)
        return true
    }

    /// Appends a snippet to config.json, keeping everything else in it.
    static func save(_ text: String) {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        Config.update("snippets") { list in
            var l = list as? [[String: String]] ?? []
            l.append(["name": String(first.trimmingCharacters(in: .whitespaces).prefix(40)), "text": text])
            return l
        }
    }
}
