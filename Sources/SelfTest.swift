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

        // Snapping, in Cocoa coordinates on a 1000x800 screen.
        let a = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let win = CGRect(x: 100, y: 100, width: 400, height: 300)
        let snap = { (n: String, c: CGRect) in Snap.target(n, screen: a, current: c, gap: 0)! }
        check(snap("Left Half", win) == CGRect(x: 0, y: 0, width: 500, height: 800), "left half")
        check(snap("Top Half", win) == CGRect(x: 0, y: 400, width: 1000, height: 400), "top half is the upper part")
        check(snap("Top Left Quarter", win) == CGRect(x: 0, y: 400, width: 500, height: 400), "top left quarter")
        check(snap("Bottom Right Quarter", win) == CGRect(x: 500, y: 0, width: 500, height: 400), "bottom right quarter")
        check(abs(snap("Center Third", win).minX - 333.33) < 1 && abs(snap("Center Third", win).width - 333.33) < 1, "center third")
        check(snap("Center Half", win) == CGRect(x: 250, y: 0, width: 500, height: 800), "center half")
        check(snap("Center", win) == CGRect(x: 300, y: 250, width: 400, height: 300), "center keeps size")
        check(snap("Maximize Height", win) == CGRect(x: 100, y: 0, width: 400, height: 800), "maximize height keeps x and width")
        check(snap("Make Larger", win) == CGRect(x: 60, y: 60, width: 480, height: 380), "make larger")
        check(snap("Make Larger", a) == a, "make larger stays on screen")
        check(snap("Make Smaller", win) == CGRect(x: 140, y: 140, width: 320, height: 220), "make smaller")
        check(snap("Make Smaller", CGRect(x: 0, y: 0, width: 300, height: 150)).size == CGSize(width: 300, height: 150),
              "make smaller never grows a small window")
        check(snap("Move Right", win) == CGRect(x: 600, y: 100, width: 400, height: 300), "move right keeps size")
        check(snap("Move Up", win) == CGRect(x: 100, y: 500, width: 400, height: 300), "move up keeps size")
        let gapped = Snap.target("Left Half", screen: a, current: win, gap: 10)!
        check(gapped == CGRect(x: 10, y: 10, width: 485, height: 780), "gaps on region snaps")
        check(Snap.target("Center", screen: a, current: win, gap: 10)!.size == win.size, "no gaps on size-keeping actions")
        let half = snap("Left Half", win)
        check(abs(snap("Left Half", half).width - 666.67) < 1, "left half again cycles to two thirds")
        check(Snap.target("Nope", screen: a, current: win, gap: 0) == nil, "unknown action")
        for (combo, action) in Config.defaultHotkeys {
            check(HotKeys.parse(combo) != nil, "default hotkey parses: \(combo)")
            check(action == "show" || action == "Restore Window" || action.hasSuffix("Display")
                  || Snap.all.contains { $0.name == action }, "default hotkey has an action: \(action)")
        }
        let off = Config.active(Config.defaultHotkeys, snapping: false)
        check(Set(off.values) == ["show"], "window snapping off leaves only the launcher hotkeys")
        check(Config.active(["ctrl+opt+x": "Clipboard History", "ctrl+opt+y": "Left Half"], snapping: false) == ["ctrl+opt+x": "Clipboard History"],
              "snapping off drops user-bound window hotkeys too")
        check(Config.active(Config.defaultHotkeys, snapping: true).count == Config.defaultHotkeys.count, "snapping on keeps all")

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

        // Snippets
        let sn = Snippet.parse([["name": "Link", "keyword": "MDL", "text": "[x]({clipboard}) on {date}"], ["text": "no name"]])
        check(sn.count == 1 && sn[0].keyword == "mdl", "snippet parse: needs a name or keyword, keyword lowercased")
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        check(sn[0].expanded(now: day, clipboard: "https://a.b") == "[x](https://a.b) on \(f.string(from: day))", "snippet placeholders")
        check(Snippet(name: "n", keyword: nil, text: "{clipboard}").expanded(clipboard: nil) == "", "empty clipboard expands to nothing")

        let m = HotKeys.merged(["ctrl+opt+c": "Center", "opt+space": "show"], ["alt+ctrl+c": "Maximize", "opt+space": "none"])
        check(m == ["alt+ctrl+c": "Maximize"], "config overrides defaults by key, none removes")

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
        check(Media.volume("vol 30") == 30 && Media.volume("volume 300") == nil, "volume parse")
        check(SettingsPanes.all.contains { Match.score("wifi", $0.name) != nil || $0.keywords.contains("wifi") }, "wifi pane")
        check(ci || !Audio.devices().isEmpty, "audio devices listed")

        // Script commands, using the examples shipped in scripts/
        let dir = FileManager.default.currentDirectoryPath + "/scripts"   // build.sh runs from the repo root
        let scripts = Script.load(from: dir)
        check(scripts.contains { $0.title == "What's on Port" && $0.argument == "port" }, "script metadata with argument")
        check(scripts.contains { $0.title == "Copy UUID" && $0.mode == "silent" }, "silent script")

        print(fails == 0 ? "\nall passed" : "\n\(fails) failed")
        exit(fails == 0 ? 0 : 1)
    }
}
