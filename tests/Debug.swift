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
}
