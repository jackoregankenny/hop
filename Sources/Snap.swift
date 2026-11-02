import AppKit

/// One-shot window placement for the focused window. For tiling, see Tiles (github.com/jackoregankenny/tiles).
enum Snap {
    /// `area` is the screen's visible frame (inset by gap/2), `current` the window, both in Cocoa coordinates.
    typealias Place = (_ area: CGRect, _ current: CGRect) -> CGRect

    struct Action {
        let name: String
        let keywords: [String]
        let symbol: String
        let region: Bool   // fills a region of the screen (gaps apply) rather than keeping the window's size
        let place: Place
    }

    private static func r(_ name: String, _ keywords: [String], _ symbol: String,
                          _ x: CGFloat, _ w: CGFloat, _ y: CGFloat, _ h: CGFloat) -> Action {
        Action(name: name, keywords: keywords, symbol: symbol, region: true) { a, _ in Rects.part(a, x: x, w: w, y: y, h: h) }
    }
    private static func keep(_ name: String, _ keywords: [String], _ symbol: String, _ place: @escaping Place) -> Action {
        Action(name: name, keywords: keywords, symbol: symbol, region: false, place: place)
    }

    /// Keeps a rect inside the area, shrinking it only if it cannot fit.
    static func clamp(_ c: CGRect, to a: CGRect) -> CGRect {
        let w = min(c.width, a.width), h = min(c.height, a.height)
        return CGRect(x: min(max(c.minX, a.minX), a.maxX - w), y: min(max(c.minY, a.minY), a.maxY - h), width: w, height: h)
    }

    static let step: CGFloat = 40   // Make Larger / Make Smaller, per side

    static let all: [Action] = [
        r("Left Half", ["lh", "left"], "rectangle.lefthalf.filled", 0, 0.5, 0, 1),
        r("Right Half", ["rh", "right"], "rectangle.righthalf.filled", 0.5, 0.5, 0, 1),
        r("Top Half", ["top"], "rectangle.tophalf.filled", 0, 1, 0, 0.5),
        r("Bottom Half", ["bottom"], "rectangle.bottomhalf.filled", 0, 1, 0.5, 0.5),
        r("Center Half", ["middle half"], "rectangle.center.inset.filled", 0.25, 0.5, 0, 1),
        r("Top Left Quarter", ["corner", "tl"], "rectangle.inset.topleft.filled", 0, 0.5, 0, 0.5),
        r("Top Right Quarter", ["corner", "tr"], "rectangle.inset.topright.filled", 0.5, 0.5, 0, 0.5),
        r("Bottom Left Quarter", ["corner", "bl"], "rectangle.inset.bottomleft.filled", 0, 0.5, 0.5, 0.5),
        r("Bottom Right Quarter", ["corner", "br"], "rectangle.inset.bottomright.filled", 0.5, 0.5, 0.5, 0.5),
        r("Left Third", ["first third"], "rectangle.split.3x1", 0, 1 / 3, 0, 1),
        r("Center Third", ["middle third"], "rectangle.split.3x1", 1 / 3, 1 / 3, 0, 1),
        r("Right Third", ["last third"], "rectangle.split.3x1", 2 / 3, 1 / 3, 0, 1),
        r("Left Two Thirds", ["first two thirds"], "rectangle.split.3x1", 0, 2 / 3, 0, 1),
        r("Right Two Thirds", ["last two thirds"], "rectangle.split.3x1", 1 / 3, 2 / 3, 0, 1),
        r("Maximize", ["full", "fill", "zoom"], "rectangle.fill", 0, 1, 0, 1),
        r("Almost Maximize", ["big"], "rectangle.inset.filled", 0.05, 0.9, 0.05, 0.9),
        keep("Maximize Height", ["tall", "vertical"], "arrow.up.and.down") { a, c in
            CGRect(x: c.minX, y: a.minY, width: min(c.width, a.width), height: a.height)
        },
        keep("Center", ["centre"], "rectangle.center.inset.filled") { a, c in
            let w = min(c.width, a.width), h = min(c.height, a.height)
            return CGRect(x: a.midX - w / 2, y: a.midY - h / 2, width: w, height: h)
        },
        keep("Make Larger", ["bigger", "grow"], "plus.magnifyingglass") { a, c in
            clamp(c.insetBy(dx: -step, dy: -step), to: a)
        },
        keep("Make Smaller", ["shrink"], "minus.magnifyingglass") { a, c in
            c.insetBy(dx: max(0, min(step, (c.width - 320) / 2)), dy: max(0, min(step, (c.height - 200) / 2)))
        },
        keep("Move Left", ["edge"], "arrow.left.to.line") { a, c in clamp(c.offsetBy(dx: a.minX - c.minX, dy: 0), to: a) },
        keep("Move Right", ["edge"], "arrow.right.to.line") { a, c in clamp(c.offsetBy(dx: a.maxX - c.maxX, dy: 0), to: a) },
        keep("Move Up", ["edge", "top"], "arrow.up.to.line") { a, c in clamp(c.offsetBy(dx: 0, dy: a.maxY - c.maxY), to: a) },
        keep("Move Down", ["edge", "bottom"], "arrow.down.to.line") { a, c in clamp(c.offsetBy(dx: 0, dy: a.minY - c.minY), to: a) },
    ]

    /// Pressing Left/Right Half again cycles 1/2 -> 2/3 -> 1/3, like Rectangle.
    static func cycled(_ name: String, area a: CGRect, current: CGRect, gap: CGFloat) -> CGRect? {
        let left = name == "Left Half", right = name == "Right Half"
        guard left || right else { return nil }
        let rects = [0.5, 2.0 / 3, 1.0 / 3].map { w in Rects.withGaps(Rects.part(a, x: left ? 0 : 1 - w, w: w), gap) }
        guard let i = rects.firstIndex(where: { $0.near(current, 4) }) else { return rects[0] }
        return rects[(i + 1) % rects.count]
    }

    /// Where `name` puts a window at `current` on a screen whose visible frame is `screen`.
    static func target(_ name: String, screen: CGRect, current: CGRect, gap: CGFloat) -> CGRect? {
        guard let action = all.first(where: { $0.name == name }) else { return nil }
        let a = screen.insetBy(dx: gap / 2, dy: gap / 2)
        if let c = cycled(name, area: a, current: current, gap: gap) { return c }
        return action.region ? Rects.withGaps(action.place(a, current), gap) : action.place(screen, current)
    }

    /// Every action Window Snapping covers, for switching it all off at once.
    static let actionNames: Set<String> = Set(all.map(\.name)).union(["Restore Window", "Next Display", "Previous Display"])

    /// Rectangle's default shortcuts, so the muscle memory carries over.
    static let defaultHotkeys: [String: String] = [
        "ctrl+opt+left": "Left Half", "ctrl+opt+right": "Right Half",
        "ctrl+opt+up": "Top Half", "ctrl+opt+down": "Bottom Half",
        "ctrl+opt+u": "Top Left Quarter", "ctrl+opt+i": "Top Right Quarter",
        "ctrl+opt+j": "Bottom Left Quarter", "ctrl+opt+k": "Bottom Right Quarter",
        "ctrl+opt+d": "Left Third", "ctrl+opt+f": "Center Third", "ctrl+opt+g": "Right Third",
        "ctrl+opt+e": "Left Two Thirds", "ctrl+opt+t": "Right Two Thirds",
        "ctrl+opt+return": "Maximize", "ctrl+opt+shift+up": "Maximize Height", "ctrl+opt+c": "Center",
        "ctrl+opt+equal": "Make Larger", "ctrl+opt+minus": "Make Smaller",
        "ctrl+opt+delete": "Restore Window",
        "ctrl+opt+cmd+right": "Next Display", "ctrl+opt+cmd+left": "Previous Display",
    ]
}

final class Snapper {
    var gap: CGFloat = 0
    private var restore: [CGWindowID: CGRect] = [:]

    func snap(_ name: String) {
        guard AX.ensureTrusted(), let w = WindowCore.focused(), let screen = Geo.screen(containing: w.frame),
              let target = Snap.target(name, screen: screen.visibleFrame, current: Geo.flip(w.frame), gap: gap) else { return }
        if restore[w.id] == nil { restore[w.id] = w.frame }
        WindowCore.move(w, cocoa: target)
    }

    func restoreFocused() {
        guard AX.ensureTrusted(), let w = WindowCore.focused(), let r = restore.removeValue(forKey: w.id) else { return }
        AX.setFrame(w.el, r, app: w.app)
    }

    func moveDisplay(by step: Int) {
        let screens = NSScreen.screens
        guard AX.ensureTrusted(), screens.count > 1, let w = WindowCore.focused(),
              let from = Geo.screen(containing: w.frame), let i = screens.firstIndex(of: from) else { return }
        let to = screens[(i + step + screens.count) % screens.count]
        let f = Geo.flip(w.frame), a = from.visibleFrame, b = to.visibleFrame
        if restore[w.id] == nil { restore[w.id] = w.frame }
        // Keep the window's relative position and size.
        WindowCore.move(w, cocoa: CGRect(x: b.minX + (f.minX - a.minX) / a.width * b.width,
                                         y: b.minY + (f.minY - a.minY) / a.height * b.height,
                                         width: f.width / a.width * b.width, height: f.height / a.height * b.height))
    }

    struct Command { let title: String; let keywords: [String]; let symbol: String; let run: () -> Void }

    func commands() -> [Command] {
        Snap.all.map { s in Command(title: s.name, keywords: s.keywords + ["window"], symbol: s.symbol) { [weak self] in self?.snap(s.name) } }
            + [Command(title: "Restore Window", keywords: ["undo", "window"], symbol: "arrow.uturn.backward") { [weak self] in self?.restoreFocused() },
               Command(title: "Next Display", keywords: ["monitor", "screen"], symbol: "display.2") { [weak self] in self?.moveDisplay(by: 1) },
               Command(title: "Previous Display", keywords: ["monitor", "screen"], symbol: "display.2") { [weak self] in self?.moveDisplay(by: -1) }]
    }
}
