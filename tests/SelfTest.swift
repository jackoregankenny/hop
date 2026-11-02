import AppKit
import Carbon.HIToolbox

enum SelfTest {
    static func run() -> Never {
        var fails = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "ok   " : "FAIL ", what)
            if !ok { fails += 1 }
        }
        func best(_ q: String, _ names: [String]) -> String? {
            names.compactMap { n in Match.score(q, n).map { ($0, n) } }.max { $0.0 < $1.0 }?.1
        }
        let apps = ["Visual Studio Code", "Safari", "System Settings", "Slack", "Spotify", "FaceTime",
                    "Finder", "Activity Monitor", "Terminal", "Telegram", "Google Chrome", "Calculator"]

        check(best("saf", apps) == "Safari", "prefix: saf -> Safari")
        check(best("vsc", apps) == "Visual Studio Code", "initials: vsc -> Visual Studio Code")
        check(best("ft", apps) == "FaceTime", "camelCase initials: ft -> FaceTime")
        check(best("am", apps) == "Activity Monitor", "initials: am -> Activity Monitor")
        check(best("chrome", apps) == "Google Chrome", "word prefix: chrome -> Google Chrome")
        check(best("spotfy", apps) == "Spotify", "typo: spotfy -> Spotify")
        check(best("termnial", apps) == "Terminal", "transposition: termnial -> Terminal")
        check(best("calcualtor", apps) == "Calculator", "typo: calcualtor -> Calculator")
        check(best("settngs", apps) == "System Settings", "typo in second word: settngs -> System Settings")
        check(Match.score("zzz", "Safari") == nil, "no match: zzz")
        check(Match.score("mtk", "Tile: Master & Stack", loose: false) == nil, "strict: no scattered-letter match")
        check(Match.score("wifi", "Show Logs in Finder", loose: false) == nil, "strict: wifi is not Show Logs in Finder")
        check(Match.score("spotfy", "Spotify", loose: false) != nil, "strict still allows typos")

        check(Calc.eval("2+2*3") == 8, "2+2*3 = 8")
        check(Calc.eval("(2+2)*3") == 12, "(2+2)*3 = 12")
        check(Calc.eval("2^10") == 1024, "2^10 = 1024")
        check(Calc.eval("sqrt(16) + 1") == 5, "sqrt(16)+1 = 5")
        check(Calc.eval("-3 + 1") == -2, "-3 + 1 = -2")
        check(Calc.eval("1,000 * 3") == 3000, "1,000 * 3 = 3000")
        check(Calc.eval("10 % 3") == 1, "10 % 3 = 1")
        check(Calc.eval("42") == nil, "bare number is not an answer")
        check(Calc.eval("safari") == nil, "word is not math")
        check(Calc.eval("2+") == nil, "incomplete expression")
        check(Calc.format(0.1 + 0.2) == "0.3", "format 0.1+0.2")

        check(Units.convert("5 km to mi") == "3.106856 mi", "5 km to mi")
        check(Units.convert("100 f to c") == "37.777778 °C", "100 f to c")
        check(Units.convert("1 gb in mb") == "1000 mb", "1 gb in mb")
        check(Units.convert("5 km to kg") == nil, "mismatched dimensions")
        check(Units.currency("100 usd to eur").map { "\($0.0) \($0.1) \($0.2)" } == "100.0 USD EUR", "currency parse")
        check(Units.currency("5 km to mil") == nil, "units are not currency")

        check(Web.looksLikeURL("github.com/justrach") == "https://github.com/justrach", "url detection")
        check(Web.looksLikeURL("hello world") == nil, "not a url")
        check(Web.looksLikeURL("3.14") == nil, "number is not a url")

        for (combo, action) in Config.defaultHotkeys {
            check(HotKeys.parse(combo) != nil && action == "show", "default hotkey opens Hop: \(combo)")
        }
        check(ConfigCheck.run(text: #"{ "snapGap": 4 }"#, known: []).errors.isEmpty, "a retired key is only a warning")
        check(ConfigCheck.run(text: Config.sample, known: ["clipboard history", "lock screen"]) .warnings.isEmpty, "the example config is clean")

        // Usage weighting
        let week = Usage.halfLife
        check(Usage.decayed(8, since: 0, now: week) == 4, "frecency halves each week")
        check(Usage.decayed(8, since: 100, now: 50) == 8, "no decay backwards in time")
        var picks: [String: Double] = [:]
        for _ in 0..<10 { picks = Usage.pick(picks, "hop-settings") }
        picks = Usage.pick(picks, "system-settings")
        picks = Usage.pick(picks, "system-settings")
        check(picks["system-settings"]! > picks["hop-settings"]!, "two recent picks beat ten old ones")
        for _ in 0..<12 { picks = Usage.pick(picks, "system-settings") }
        check(picks["hop-settings"] == nil, "a choice you stopped making fades out")

        // Files: the shapes of noise seen in real results, and files people do want
        let home = "/Users/u"
        func hit(_ p: String, opened: Double? = nil, uses: Int = 0, _ types: [String] = ["public.data"]) -> Files.Hit {
            Files.Hit(path: home + p, lastUsed: opened.map { Date(timeIntervalSinceNow: -$0 * 86_400) }, useCount: uses, types: types)
        }
        let noisy: [(String, Files.Hit)] = [
            ("never-opened JSON in a repo", hit("/Code/shop/backend/stock/doctype/stock_settings/stock_settings.json", ["public.json"])),
            ("component source", hit("/Code/webapp/frontend/src/lib/components/AdminSettingsInner.svelte", ["public.source-code"])),
            ("test fixture spreadsheet", hit("/Code/sheets/xlsx/tests/calc_tests/DATE_AND_TIME/NOW_TODAY.xlsx")),
            ("Rust test", hit("/Code/sheets/base/src/test/test_today.rs", ["public.source-code"])),
            ("screenshot five folders into Downloads", hit("/Downloads/demo-videos/details/launch-kit/screens/v2-inbox-dark.png")),
            ("folder inside a design project", hit("/Design/project/directory/today")),
            ("in node_modules", hit("/Downloads/app/node_modules/x/readme.md")),
            ("app support, even if opened", hit("/Library/Application Support/SomeEditor/User/state.vscdb", opened: 1)),
            ("inside .git, even if opened", hit("/Code/x/.git/config", opened: 1)),
        ]
        for (what, h) in noisy { check(!Files.keep(h, home: home), "file noise dropped: \(what)") }
        let wanted: [(String, Files.Hit)] = [
            ("PDF you opened", hit("/Downloads/edition-dark.pdf", opened: 11, uses: 8, ["com.adobe.pdf"])),
            ("new download, not opened yet", hit("/Downloads/invoice-october.pdf", ["com.adobe.pdf"])),
            ("document in a Documents subfolder", hit("/Documents/Taxes/return.pdf", ["com.adobe.pdf"])),
            ("code file you opened from Finder", hit("/Code/notes/plan.md", opened: 2, ["public.source-code"])),
        ]
        for (what, h) in wanted { check(Files.keep(h, home: home), "file kept: \(what)") }
        check(Files.rank(hit("/a.pdf", opened: 1), match: 700) > Files.rank(hit("/b.pdf", opened: 200), match: 700),
              "recently opened files rank higher")
        check(Files.rank(hit("/a.pdf", opened: 60), match: 650) > Files.rank(hit("/b.pdf"), match: 700),
              "an opened file beats a slightly better named one you never opened")

        // Intent: where the single web row goes
        for q in ["how do i reset smc", "why is the sky blue", "best mechanical keyboard", "is it going to rain",
                  "rust vs zig?", "flights dublin to lisbon march"] {
            check(Intent.webFirst(q, bestLocal: 760, hasAnswer: false), "web first for a question: \(q)")
        }
        check(!Intent.webFirst("slack", bestLocal: 1000, hasAnswer: false), "web last when an app matches")
        check(!Intent.webFirst("vsc", bestLocal: 820, hasAnswer: false), "web last for initials of an app")
        check(!Intent.webFirst("time in tokyo", bestLocal: nil, hasAnswer: true), "web last when there is an answer")
        check(Intent.webFirst("qwzx", bestLocal: nil, hasAnswer: false), "web first when nothing here matches")
        check(Intent.webFirst("spotfy", bestLocal: 280, hasAnswer: false), "web first when only a weak typo matches")
        check(!Intent.isQuestion("is") && !Intent.isQuestion("left half"), "single words and short names are not questions")

        // Themes
        check(Theme.from(nil) == Theme(), "no theme key gives the default look")
        let mid = Theme.from("midnight")
        check(mid.appearance == "dark" && mid.blur == "hud" && mid.accent == "#7c8cff", "preset by name")
        let custom = Theme.from(["preset": "paper", "accent": "#2563eb", "fontSize": 99, "width": 820])
        check(custom.blur == "none" && custom.accent == "#2563eb" && custom.width == 820 && custom.fontSize == 22,
              "preset plus overrides, sizes clamped")
        check(Theme.from(["accent": "blue"]).accent == nil, "bad colours are ignored")
        let c = Theme.color("#0d1020b8")
        check(c != nil && abs(c!.alphaComponent - 184.0 / 255) < 0.001, "hex colour with alpha")
        check(Theme.color("#fff") == Theme.color("#ffffff"), "short hex")

        // Updates
        check(Updater.isNewer("v0.10.0", than: "0.9.2"), "versions compare numerically")
        check(!Updater.isNewer("0.2.0", than: "0.2.0") && !Updater.isNewer("0.1.9", than: "0.2"), "same or older is not newer")
        check(Updater.isNewer("1.0", than: "0.9.9.9"), "missing parts count as zero")
        check(Feature.updateChecks.rawValue == "automaticUpdates", "update switch keeps its old defaults key")
        check(Updater(app: "Hop").pending == nil || ProcessInfo.processInfo.environment["HOP_FAKE_UPDATE"] != nil,
              "nothing pending before a check")

        // Usage points: frecency, plus this query's share of picks, or half that for a shorter prefix.
        // Literal data, so nothing is written to Hop's preferences.
        let p: [String: [String: Double]] = ["sl": ["slack": 3], "s": ["spotify": 1, "slack": 1]]
        let fr: [String: [Double]] = ["slack": [4, 0], "safari": [2, 0]]
        let fast = Usage.scorer(query: "sl", now: 86_400, picks: p, frecency: fr)
        check(abs(fast("spotify") - 100) < 0.001 && fast("none") == 0, "a pick for a shorter prefix counts half")
        check(fast("slack") > 400 + fast("safari"), "picks for the exact query count in full, on top of frecency")

        // Snippets
        let sn = Snippet.parse([["name": "Link", "keyword": "MDL", "text": "[x]({clipboard}) on {date}"], ["text": "no name"]])
        check(sn.count == 1 && sn[0].keyword == "mdl", "snippet parse: needs a name or keyword, keyword lowercased")
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        check(sn[0].expanded(now: day, clipboard: "https://a.b") == "[x](https://a.b) on \(f.string(from: day))", "snippet placeholders")
        check(Snippet(name: "n", keyword: nil, text: "{clipboard}").expanded(clipboard: nil) == "", "empty clipboard expands to nothing")

        let m = HotKeys.merged(["ctrl+opt+c": "Center", "opt+space": "show"], ["alt+ctrl+c": "Maximize", "opt+space": "none"])
        check(m == ["alt+ctrl+c": "Maximize"], "config overrides defaults by key, none removes")

        // Settings window: hotkey edits are written as differences from the defaults
        let defaults = Config.defaultHotkeys.map { ["combo": $0.key, "action": $0.value] }
        check(SettingsWindow.hotkeyChanges(defaults).isEmpty, "unchanged hotkeys write nothing")
        let edited = defaults.filter { $0["combo"] != "opt+space" && $0["combo"] != "ctrl+opt+c" }
            + [["combo": "alt+ctrl+c", "action": "Maximize"], ["combo": "ctrl+opt+v", "action": "Clipboard History"], ["combo": "", "action": "x"]]
        check(SettingsWindow.hotkeyChanges(edited) == ["opt+space": "none", "alt+ctrl+c": "Maximize", "ctrl+opt+v": "Clipboard History"],
              "removed default -> none, rebound and new combos kept, incomplete rows dropped")
        check(HotKeys.merged(Config.defaultHotkeys, SettingsWindow.hotkeyChanges(edited)).count == edited.filter { $0["combo"] != "" }.count,
              "written changes merge back to the edited list")
        check(HotKeys.name(forKeyCode: kVK_LeftArrow) == "left" && HotKeys.name(forKeyCode: kVK_Return) == "return", "key code names")

        func key(_ code: Int, _ chars: String, _ mods: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
        }
        let rec = KeyRecorder()
        var recorded: [String] = []
        rec.onRecord = { recorded.append($0) }
        rec.start(); rec.keyDown(with: key(kVK_ANSI_V, "v", [.control, .option]))
        rec.start(); rec.keyDown(with: key(kVK_LeftArrow, "", [.command, .shift]))
        rec.start(); rec.keyDown(with: key(kVK_Escape, "\u{1b}", []))
        check(recorded == ["ctrl+opt+v", "shift+cmd+left"] && rec.combo == "shift+cmd+left", "recorder: combos recorded, escape cancels")
        check(HotKeys.parse("shift+cmd+left") != nil, "recorded combos parse")

        // Config.update keeps other keys, and an emptied list removes its key
        let tmpHome = NSTemporaryDirectory() + "hop-selftest-\(getpid())"
        setenv("HOP_HOME", tmpHome, 1)
        try? FileManager.default.createDirectory(atPath: tmpHome, withIntermediateDirectories: true)
        try? Data(#"{ "theme": "paper" }"#.utf8).write(to: URL(fileURLWithPath: tmpHome + "/config.json"))
        Config.update("quicklinks") { _ in [["name": "Docs", "url": "https://example.com/{query}", "key": "d"]] }
        Snippet.save("Hello\nthere")
        var cfg = Config.load()
        check(cfg.theme.font == "serif" && cfg.quicklinks.first?.key == "d" && cfg.snippets.first?.name == "Hello",
              "update keeps other keys and adds lists")
        Config.update("quicklinks") { _ in [[String: String]]() }
        cfg = Config.load()
        let raw = (try? String(contentsOfFile: tmpHome + "/config.json", encoding: .utf8)) ?? ""
        check(cfg.quicklinks.isEmpty && !raw.contains("quicklinks") && raw.contains("paper"), "an emptied list removes its key")
        check(ConfigCheck.run(text: raw, known: []).errors.isEmpty, "written config passes --check")
        let big = ConfigCheck.run(text: #"{ "theme": { "fontSize": 40 } }"#, known: [])
        check(big.errors.isEmpty && big.warnings == ["theme.fontSize: 40 is outside 11–22, so Hop uses 22"], "--check warns about a clamped number")
        try? FileManager.default.removeItem(atPath: tmpHome)
        unsetenv("HOP_HOME")

        // Clipboard: dictation apps paste, then restore the old clipboard; the dictated text stays on top
        let cb = Clipboard()
        let t0 = Date()
        cb.add(.text("old"), now: t0)
        cb.add(.text("dictated words"), now: t0.addingTimeInterval(60))
        cb.add(.text("old"), now: t0.addingTimeInterval(60.4))
        check(cb.items == [.text("dictated words"), .text("old")], "a quick restore does not bury dictated text")
        cb.add(.text("old"), now: t0.addingTimeInterval(120))
        check(cb.items.first == .text("old"), "copying it again later moves it up")
        cb.add(.text("dictated again"), transient: true, now: t0.addingTimeInterval(200))
        cb.add(.text("never seen before"), now: t0.addingTimeInterval(200.2))
        check(cb.items.prefix(2) == [.text("dictated again"), .text("never seen before")], "a restore right after transient text goes under it")
        cb.add(.text("a real copy"), now: t0.addingTimeInterval(200.5))
        check(cb.items.first == .text("a real copy"), "only the first change after transient text counts as a restore")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        if case let .image(_, type, thumb, size)? = Clipboard.image(png, .png) {
            check(type == .png && size == CGSize(width: 640, height: 400) && max(thumb.size.width, thumb.size.height) <= 36,
                  "images keep their bytes and get a small thumbnail")
        } else { check(false, "image clip from png") }
        for i in 0..<15 { if let c = Clipboard.image(png + Data([UInt8(i)]), .png) { cb.add(c) } }
        check(cb.items.filter { if case .image = $0 { return true }; return false }.count == 12 && cb.items.contains(.text("old")),
              "at most 12 images, text kept")

        // Frequency beats a slightly better name: a word-start match used 10 times outranks an unused prefix match
        let used = Usage.scorer(query: "x", now: 0, picks: [:], frecency: ["a": [10, 0]])
        check(760 + used("a") > 900 + used("b"), "often-used item ranks above a better-matching unused one")

        // Hotkeys
        check(HotKeys.parse("ctrl+opt+left").map { "\($0.key) \($0.mods)" } == "\(kVK_LeftArrow) \(controlKey | optionKey)", "parse ctrl+opt+left")
        check(HotKeys.parse("cmd+bogus") == nil, "unknown key rejected")
        check(HotKeys.symbols("ctrl+opt+shift+h") == "⌃⌥⇧H", "hotkey symbols")

        // Integrations that need no permission
        check(Emoji.search("fire").first?.emoji == "🔥", "emoji: fire")
        check(!Emoji.search("fire").contains { $0.name.contains("rolling eyes") }, "emoji: no scattered matches")
        check(Emoji.query(":thumbs") == "thumbs", "emoji prefix")
        check(Clock.zone("time in tokyo")?.identifier == "Asia/Tokyo", "time in tokyo")
        check(Clock.zone("sf time")?.identifier == "America/Los_Angeles", "sf time")
        check(Clock.zone("time in dublin")?.identifier == "Europe/Dublin", "time in dublin")
        check(Clock.unix("1700000000") != nil && Clock.unix("12345") == nil, "unix timestamp")
        check(Define.word("define serendipity") == "serendipity", "define parse")
        // CI machines have no sound hardware and may lack dictionaries.
        let ci = ProcessInfo.processInfo.environment["CI"] != nil
        check(ci || Define.lookup("serendipity")?.contains("chance") == true, "dictionary lookup")
        check(Volume.parse("vol 30") == 30 && Volume.parse("volume 300") == nil, "volume parse")
        check(SettingsPanes.all.contains { Match.score("wifi", $0.name) != nil || $0.keywords.contains("wifi") }, "wifi pane")
        check(ci || !Audio.devices().isEmpty, "audio devices listed")

        // Script commands, using the examples shipped in scripts/
        let dir = FileManager.default.currentDirectoryPath + "/scripts"   // build.sh runs from the repo root
        let scripts = Script.load(from: dir)
        check(scripts.contains { $0.title == "What's on Port" && $0.argument == "port" }, "script metadata with argument")
        check(scripts.contains { $0.title == "Copy UUID" && $0.mode == "silent" }, "silent script")
        let hop = NSTemporaryDirectory() + "hop-selftest-scripts"
        try? FileManager.default.createDirectory(atPath: hop, withIntermediateDirectories: true)
        try? "#!/bin/sh\n# @hop.title Hop Header\n# @hop.mode silent\n".write(toFile: hop + "/h.sh", atomically: true, encoding: .utf8)
        check(Script.load(from: hop).contains { $0.title == "Hop Header" && $0.mode == "silent" }, "@hop. headers work like @raycast.")
        try? FileManager.default.removeItem(atPath: hop)

        print(fails == 0 ? "\nall passed" : "\n\(fails) failed")
        exit(fails == 0 ? 0 : 1)
    }
}
