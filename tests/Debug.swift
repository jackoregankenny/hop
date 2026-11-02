import AppKit

/// Developer-only flags, compiled into `./build.sh` builds (-D TESTING) and never into releases.
enum Debug {
    /// Before the app starts: --selftest runs the self-test, --probe reports what Hop can see.
    static func early() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { SelfTest.run() }
        guard args.contains("--probe") else { return }
        print("accessibility trusted:", AXIsProcessTrusted())
        print("windows on this Space:", WindowCore.windows().count, "· focused:", WindowCore.focused()?.appName ?? "none")
        if let front = NSWorkspace.shared.frontmostApplication {
            print("menu items in \(front.localizedName ?? "?"):",
                  Menus.read(pid: front.processIdentifier, appName: front.localizedName ?? "").count)
        }
        print("window titles (all apps):", WindowList.read().count)
        print("shortcuts:", Shortcuts.list().count)
        print("audio devices:", Audio.devices().map { "\($0.output ? "out" : "in"):\($0.name)\($0.current ? "*" : "")" }
            .joined(separator: ", "))
        print("battery:", Battery.status().map { "\($0.0) \($0.1)" } ?? "none")
        exit(0)
    }

    /// After launch: --show opens the panel, --query prefills it, --snapshot out.png renders it to a
    /// file and quits (no Screen Recording permission needed).
    static func launched(_ launcher: Launcher) {
        let args = CommandLine.arguments
        if args.contains("--bench") { bench(launcher); exit(0) }
        if args.contains("--show") {
            let q = args.firstIndex(of: "--query").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? ""
            let focus = !args.contains("--snapshot")   // a snapshot must not take the keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { launcher.show(query: q, focus: focus) }
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // The content, not the backdrop: Liquid Glass is drawn by the window server and cannot be
            // captured offscreen, so this shows layout and text, not the material.
            let v = launcher.root
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    /// --bench: where time goes on the main thread. Icons are timed through first draw, because
    /// NSWorkspace hands back lazy images and the real decoding happens when a row first draws.
    static func bench(_ launcher: Launcher) {
        func ms(_ f: () -> Void) -> Double {
            let t = DispatchTime.now().uptimeNanoseconds
            f()
            return Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000
        }
        launcher.apps.refreshNow()
        let paths = Array(launcher.apps.all.prefix(40).map(\.path))
        var ready = 0
        let ask = ms { for p in paths { if Icons.image(.file(p), ready: { ready += 1 }) != nil { ready += 1 } } }
        let start = DispatchTime.now().uptimeNanoseconds
        while ready < paths.count && RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) {}
        let wall = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let ctx = CGContext(data: nil, width: 72, height: 72, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let draw = ms {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            for p in paths { Icons.image(.file(p))?.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72)) }
            NSGraphicsContext.restoreGraphicsState()
        }
        print(String(format: "icons: %d apps · main thread to request %.2f ms · ready in background after %.0f ms · drawing them %.2f ms",
                     paths.count, ask, wall, draw))
        let opens = (0..<3).map { _ in ms { launcher.loadSources() } }
        print(String(format: "panel open (loadSources): first %.1f ms, then %.1f ms, %.1f ms", opens[0], opens[1], opens[2]))
        print(String(format: "  audio devices %.1f ms · scripts %.1f ms · running apps %.1f ms · frontmost %.1f ms · AX trusted %.1f ms",
                     ms { _ = Audio.devices() }, ms { _ = Script.load() },
                     ms { _ = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular } },
                     ms { _ = NSWorkspace.shared.frontmostApplication }, ms { _ = AXIsProcessTrusted() }))
        var total = 0.0, n = 0, worst = 0.0
        for word in ["visual studio code", "slack", "settings", "new tab", "left half", "how do i reset"] {
            for i in 1...word.count {
                let t = ms { _ = launcher.compose(String(word.prefix(i))) }
                total += t; n += 1; worst = max(worst, t)
            }
        }
        print(String(format: "keystrokes: %d, average %.2f ms, worst %.2f ms", n, total / Double(n), worst))
    }
}
