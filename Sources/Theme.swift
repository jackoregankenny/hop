import AppKit

/// The panel's look, from the "theme" key in config.json: a preset name, or a preset plus overrides.
///   "theme": "midnight"
///   "theme": { "preset": "paper", "accent": "#2563eb", "fontSize": 16, "width": 820 }
/// Keys: preset, appearance (auto|dark|light), blur (auto|glass|clear|popover|hud|sidebar|menu|none;
/// auto is Liquid Glass on macOS 26 and the popover blur before it),
/// background ("#rrggbb" or "#rrggbbaa", drawn over the blur), accent, font (system|rounded|mono|serif
/// or a font name), fontSize, width, rows, rowHeight, radius.
struct Theme: Equatable {
    var width: CGFloat = 760
    var rows = 8
    var rowHeight: CGFloat = 50
    var radius: CGFloat = 16
    var fontSize: CGFloat = 15
    var font = "system"
    var appearance = "auto"
    var blur = "auto"
    var background: String?
    var accent: String?

    var fieldHeight: CGFloat { (fontSize * 4.2).rounded() }

    static let presets: [String: [String: Any]] = [
        "default": [:],
        "compact": ["width": 640, "rowHeight": 40, "fontSize": 13, "radius": 12],
        "midnight": ["appearance": "dark", "blur": "hud", "background": "#0d1020b8", "accent": "#7c8cff"],
        "graphite": ["appearance": "dark", "blur": "sidebar", "background": "#1c1c1e80", "accent": "#a1a1aa"],
        "paper": ["appearance": "light", "blur": "none", "background": "#fbfaf7", "accent": "#d9480f", "font": "serif"],
        "terminal": ["appearance": "dark", "blur": "none", "background": "#0b0b0bf2", "accent": "#22c55e",
                     "font": "mono", "fontSize": 14, "radius": 8],
    ]

    /// The number keys and their range; values outside it are clamped.
    static let limits: [String: ClosedRange<CGFloat>] = ["width": 480...1400, "rows": 3...14, "rowHeight": 32...80, "radius": 0...32,
                                                          "fontSize": 11...22]

    static func from(_ value: Any?) -> Theme {
        var keys: [String: Any] = [:]
        if let name = value as? String { keys = presets[name.lowercased()] ?? [:] }
        if let d = value as? [String: Any] {
            keys = presets[(d["preset"] as? String ?? "default").lowercased()] ?? [:]
            keys.merge(d) { _, mine in mine }
        }
        var t = Theme()
        func num(_ k: String) -> CGFloat? {
            (keys[k] as? NSNumber).map { min(max(CGFloat($0.doubleValue), limits[k]!.lowerBound), limits[k]!.upperBound) }
        }
        if let v = num("width") { t.width = v }
        if let v = num("rows") { t.rows = Int(v) }
        if let v = num("rowHeight") { t.rowHeight = v }
        if let v = num("radius") { t.radius = v }
        if let v = num("fontSize") { t.fontSize = v }
        if let v = keys["font"] as? String { t.font = v }
        if let v = keys["appearance"] as? String { t.appearance = v.lowercased() }
        if let v = keys["blur"] as? String { t.blur = v.lowercased() }
        if let v = keys["background"] as? String, color(v) != nil { t.background = v }
        if let v = keys["accent"] as? String, color(v) != nil { t.accent = v }
        return t
    }

    /// "#rgb", "#rrggbb" or "#rrggbbaa".
    static func color(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let (r, g, b, a) = s.count == 6
            ? ((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff, UInt64(255))
            : ((v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff)
        return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    var nsAppearance: NSAppearance? {
        switch appearance {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    /// Liquid Glass style on macOS 26 and later: "regular", "clear", or nil for the classic blur.
    var glass: String? {
        switch blur {
        case "auto", "glass": return "regular"
        case "clear": return "clear"
        default: return nil
        }
    }

    static let blurs: Set<String> = ["auto", "glass", "clear", "popover", "hud", "sidebar", "menu", "none"]
    static let appearances: Set<String> = ["auto", "dark", "light"]

    /// The classic blur, also the fallback for glass before macOS 26.
    var material: NSVisualEffectView.Material? {
        switch blur {
        case "none": return nil
        case "hud": return .hudWindow
        case "sidebar": return .sidebar
        case "menu": return .menu
        default: return .popover
        }
    }

    var selection: NSColor { accent.flatMap(Theme.color)?.withAlphaComponent(0.28) ?? NSColor.labelColor.withAlphaComponent(0.1) }

    func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        switch font.lowercased() {
        case "system": return base
        case "mono", "monospace": return .monospacedSystemFont(ofSize: size, weight: weight)
        case "rounded", "serif":
            let design: NSFontDescriptor.SystemDesign = font.lowercased() == "rounded" ? .rounded : .serif
            return base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        default: return NSFont(name: font, size: size) ?? base
        }
    }
}
