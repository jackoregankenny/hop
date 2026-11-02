import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreAudio
import CoreServices
import IOBluetooth
import IOKit.ps

// Things macOS already exposes, wired into the launcher. Each one is a small, self-contained source.

/// System Settings panes, opened with x-apple.systempreferences:<extension id>.
enum SettingsPanes {
    static let all: [(name: String, keywords: [String], id: String)] = [
        ("Wi-Fi", ["wifi", "wireless", "network"], "com.apple.wifi-settings-extension"),
        ("Bluetooth", ["bt"], "com.apple.BluetoothSettings"),
        ("Network", ["ethernet", "proxy", "dns"], "com.apple.Network-Settings.extension"),
        ("VPN", [], "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"),
        ("Battery", ["power", "energy", "low power"], "com.apple.Battery-Settings.extension"),
        ("General", ["about", "mac info"], "com.apple.SystemProfiler.AboutExtension"),
        ("Storage", ["disk space"], "com.apple.settings.Storage"),
        ("Software Update", ["update", "upgrade", "macos"], "com.apple.Software-Update-Settings.extension"),
        ("Appearance", ["dark mode", "accent", "theme"], "com.apple.Appearance-Settings.extension"),
        ("Accessibility", ["a11y", "zoom", "voiceover"], "com.apple.Accessibility-Settings.extension"),
        ("Control Center", ["menu bar"], "com.apple.ControlCenter-Settings.extension"),
        ("Siri", ["apple intelligence"], "com.apple.Siri-Settings.extension"),
        ("Spotlight", [], "com.apple.Spotlight-Settings.extension"),
        ("Privacy & Security", ["permissions", "privacy", "security", "filevault"], "com.apple.settings.PrivacySecurity.extension"),
        ("Desktop & Dock", ["dock", "stage manager", "hot corners", "mission control"], "com.apple.Desktop-Settings.extension"),
        ("Displays", ["monitor", "resolution", "night shift", "brightness"], "com.apple.Displays-Settings.extension"),
        ("Wallpaper", ["background"], "com.apple.Wallpaper-Settings.extension"),
        ("Notifications", [], "com.apple.Notifications-Settings.extension"),
        ("Sound", ["audio", "volume", "alert"], "com.apple.Sound-Settings.extension"),
        ("Focus", ["do not disturb", "dnd"], "com.apple.Focus-Settings.extension"),
        ("Screen Time", [], "com.apple.Screen-Time-Settings.extension"),
        ("Lock Screen", ["screen saver"], "com.apple.Lock-Screen-Settings.extension"),
        ("Touch ID & Password", ["fingerprint", "password"], "com.apple.Touch-ID-Settings.extension"),
        ("Users & Groups", ["accounts", "guest"], "com.apple.Users-Groups-Settings.extension"),
        ("Login Items", ["startup", "background items"], "com.apple.LoginItems-Settings.extension"),
        ("Keyboard", ["shortcuts", "input sources", "dictation"], "com.apple.Keyboard-Settings.extension"),
        ("Trackpad", ["gestures", "scrolling"], "com.apple.Trackpad-Settings.extension"),
        ("Mouse", [], "com.apple.Mouse-Settings.extension"),
        ("Printers & Scanners", ["printer"], "com.apple.Print-Scan-Settings.extension"),
        ("Date & Time", ["clock", "timezone"], "com.apple.Date-Time-Settings.extension"),
        ("Language & Region", ["locale", "language"], "com.apple.Localization-Settings.extension"),
        ("Sharing", ["airplay receiver", "file sharing", "remote login", "ssh"], "com.apple.Sharing-Settings.extension"),
        ("AirDrop & Handoff", ["airdrop", "handoff"], "com.apple.AirDrop-Handoff-Settings.extension"),
        ("Time Machine", ["backup"], "com.apple.Time-Machine-Settings.extension"),
        ("Internet Accounts", ["mail accounts"], "com.apple.Internet-Accounts-Settings.extension"),
        ("Apple Account", ["icloud", "apple id"], "com.apple.systempreferences.AppleIDSettings"),
        ("Game Controllers", ["controller"], "com.apple.Game-Controller-Settings.extension"),
        ("Startup Disk", [], "com.apple.Startup-Disk-Settings.extension"),
        ("Transfer or Reset", ["erase", "reset"], "com.apple.Transfer-Reset-Settings.extension"),
    ]
    static func open(_ id: String) { Web.open("x-apple.systempreferences:\(id)") }
    static func openAccessibilityPrivacy() {
        Web.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}

/// The built-in macOS dictionary, offline.
enum Define {
    static func word(_ q: String) -> String? {
        let l = q.lowercased()
        var w: String?
        for p in ["define ", "def ", "meaning of "] where l.hasPrefix(p) { w = String(q.dropFirst(p.count)) }
        if l.hasSuffix(" meaning") { w = String(q.dropLast(8)) }
        return w?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }
    static func lookup(_ w: String) -> String? {
        let r = CFRange(location: 0, length: (w as NSString).length)
        return DCSCopyTextDefinition(nil, w as CFString, r)?.takeRetainedValue() as String?
    }
}

/// Emoji searched by their Unicode names; no data file shipped.
enum Emoji {
    private static var index: [(String, String)] = {
        var out: [(String, String)] = []
        for r in [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x2600...0x27BF] {
            for v in r {
                guard let s = Unicode.Scalar(v), s.properties.isEmojiPresentation, let name = s.properties.name else { continue }
                out.append((String(Character(s)), name.lowercased()))
            }
        }
        return out
    }()

    static func query(_ q: String) -> String? {
        let l = q.lowercased()
        if l.hasPrefix(":") && l.count > 1 { return String(l.dropFirst()) }
        if l.hasPrefix("emoji ") { return String(l.dropFirst(6)) }
        return nil
    }

    static func search(_ q: String) -> [(emoji: String, name: String)] {
        index.compactMap { e, name in Match.score(q, name, loose: false).map { ($0, e, name) } }
            .sorted { $0.0 > $1.0 }.prefix(24).map { ($0.1, $0.2) }
    }
}

enum Clock {
    private static let aliases: [String: String] = [
        "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "la": "America/Los_Angeles",
        "seattle": "America/Los_Angeles", "pst": "America/Los_Angeles", "pt": "America/Los_Angeles",
        "nyc": "America/New_York", "ny": "America/New_York", "boston": "America/New_York", "est": "America/New_York",
        "et": "America/New_York", "austin": "America/Chicago", "texas": "America/Chicago", "london": "Europe/London",
        "uk": "Europe/London", "ireland": "Europe/Dublin", "beijing": "Asia/Shanghai", "china": "Asia/Shanghai",
        "india": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
        "japan": "Asia/Tokyo", "germany": "Europe/Berlin", "france": "Europe/Paris", "utc": "UTC", "gmt": "GMT",
    ]

    static func zone(_ q: String) -> TimeZone? {
        let l = q.lowercased().trimmingCharacters(in: .whitespaces)
        var place: String?
        if l.hasPrefix("time in ") { place = String(l.dropFirst(8)) }
        else if l.hasPrefix("time ") { place = String(l.dropFirst(5)) }
        else if l.hasSuffix(" time") { place = String(l.dropLast(5)) }
        guard let p = place?.trimmingCharacters(in: .whitespaces), p.count >= 2 else { return nil }
        if let id = aliases[p] { return TimeZone(identifier: id) }
        let ids = TimeZone.knownTimeZoneIdentifiers
        let city = { (id: String) in id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ").lowercased() } ?? "" }
        if let id = ids.first(where: { city($0) == p }) ?? (p.count >= 3 ? ids.first(where: { city($0).hasPrefix(p) }) : nil) {
            return TimeZone(identifier: id)
        }
        return TimeZone(abbreviation: p.uppercased())
    }

    static func describe(_ tz: TimeZone, now: Date = Date()) -> (String, String) {
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        let time = f.string(from: now)
        f.dateFormat = "EEE d MMM"
        let diff = Double(tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        let rel = diff == 0 ? "same as here" : "\(diff > 0 ? "+" : "")\(Calc.format(diff))h from here"
        let place = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
        return (time, "\(place) · \(f.string(from: now)) · \(rel)")
    }

    /// 10 or 13 digit numbers read as unix timestamps; "now" / "unix" gives the current one.
    static func unix(_ q: String) -> (String, String)? {
        let l = q.lowercased()
        if l == "unix" || l == "timestamp" || l == "epoch" {
            return (String(Int(Date().timeIntervalSince1970)), "Unix time now")
        }
        guard (l.count == 10 || l.count == 13), l.allSatisfy(\.isNumber), let n = Double(l) else { return nil }
        let d = Date(timeIntervalSince1970: l.count == 13 ? n / 1000 : n)
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM yyyy, HH:mm:ss zzz"
        return (f.string(from: d), "Unix timestamp → local time")
    }
}

enum Battery {
    static func status() -> (String, String)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let mins = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            var sub = charging ? "Charging" : plugged ? "Plugged in" : "On battery"
            if mins > 0 { sub += " · \(mins / 60)h \(mins % 60)m \(charging ? "to full" : "left")" }
            return ("\(cap)%", sub)
        }
        return nil
    }
}

/// Default sound input / output through CoreAudio.
enum Audio {
    struct Device { let id: AudioDeviceID; let name: String; let output: Bool; let current: Bool }

    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(_ output: Bool) -> AudioDeviceID {
        var a = addr(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    static func devices() -> [Device] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        let defOut = defaultDevice(true), defIn = defaultDevice(false)
        var out: [Device] = []
        for id in ids {
            var na = addr(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name) == noErr,
                  let n = name?.takeRetainedValue() as String? else { continue }
            for output in [true, false] {
                var sa = addr(kAudioDevicePropertyStreams, output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput)
                var ss: UInt32 = 0
                if AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ss) == noErr, ss > 0 {
                    out.append(Device(id: id, name: n, output: output, current: id == (output ? defOut : defIn)))
                }
            }
        }
        return out
    }

    static func select(_ d: Device) {
        let sels = d.output ? [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
                            : [kAudioHardwarePropertyDefaultInputDevice]
        for sel in sels {
            var a = addr(sel), id = d.id
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        }
    }
}

/// Paired Bluetooth devices. Only touched after the user asks for Bluetooth, because the first
/// access shows the system permission prompt.
enum Bluetooth {
    static var unlocked = false
    static func paired() -> [IOBluetoothDevice] {
        guard unlocked else { return [] }
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }
    static func toggle(_ d: IOBluetoothDevice) {
        DispatchQueue.global().async {
            if d.isConnected() { d.closeConnection() } else { d.openConnection() }
        }
    }
}

enum Media {
    /// Posts the hardware media keys, so it drives whatever is Now Playing (Music, Spotify, a browser tab).
    static func key(_ code: Int32) {
        guard AXIsProcessTrusted() else { AX.ensureTrusted(); return }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((code << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    static let playPause: Int32 = 16, next: Int32 = 17, previous: Int32 = 18

    static func volume(_ q: String) -> Int? {
        let l = q.lowercased()
        for p in ["volume ", "vol "] where l.hasPrefix(p) {
            if let n = Int(l.dropFirst(p.count).trimmingCharacters(in: CharacterSet(charactersIn: " %"))), (0...100).contains(n) { return n }
        }
        return nil
    }
    static func setVolume(_ n: Int) { System.script("set volume output volume \(n)") }
}

enum Paste {
    /// Copies, then sends ⌘V to the app that was frontmost (the panel never takes focus from it).
    static func paste(_ s: String, _ clipboard: Clipboard) {
        clipboard.copy(s)
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                e?.flags = .maskCommand
                e?.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }
}

/// Every menu item of the frontmost app, read through Accessibility.
enum Menus {
    struct Entry { let title: String; let path: String; let el: AXUIElement }

    static func read(pid: pid_t, appName: String) -> [Entry] {
        let app = AX.app(pid)
        guard let bar = AX.attr(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var out: [Entry] = []
        func kids(_ el: AXUIElement) -> [AXUIElement] { (AX.attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
        func walk(_ el: AXUIElement, _ path: [String], _ depth: Int) {
            for menu in kids(el) where AX.string(menu, kAXRoleAttribute) == kAXMenuRole {
                for item in kids(menu) where out.count < 2000 {
                    guard let t = AX.string(item, kAXTitleAttribute), !t.isEmpty else { continue }
                    let sub = kids(item).contains { AX.string($0, kAXRoleAttribute) == kAXMenuRole }
                    if sub {
                        if depth < 2 { walk(item, path + [t], depth + 1) }
                    } else if AX.bool(item, kAXEnabledAttribute) {
                        out.append(Entry(title: t, path: ([appName] + path).joined(separator: " › "), el: item))
                    }
                }
            }
        }
        for top in kids(bar as! AXUIElement).dropFirst() {   // skip the Apple menu
            if let t = AX.string(top, kAXTitleAttribute), !t.isEmpty { walk(top, [t], 0) }
        }
        return out
    }

    static func press(_ e: Entry) { AXUIElementPerformAction(e.el, kAXPressAction as CFString) }
}

/// Open windows of every app on this Space, by title.
enum WindowList {
    struct Entry { let title: String; let app: String; let appPath: String?; let el: AXUIElement; let appEl: AXUIElement }

    static func read() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }
        var out: [Entry] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            let el = AX.app(app.processIdentifier)
            for w in (AX.attr(el, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
                guard let t = AX.string(w, kAXTitleAttribute), !t.isEmpty,
                      AX.string(w, kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
                out.append(Entry(title: t, app: app.localizedName ?? "", appPath: app.bundleURL?.path, el: w, appEl: el))
            }
        }
        return out
    }

    static func focus(_ e: Entry) {
        if AX.bool(e.el, kAXMinimizedAttribute) { AX.set(e.el, kAXMinimizedAttribute, kCFBooleanFalse) }
        AX.set(e.el, kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(e.el, kAXRaiseAction as CFString)
        AX.set(e.appEl, kAXFrontmostAttribute, kCFBooleanTrue)
    }
}

/// Tabs from running Chromium browsers and Safari over Apple Events. Never launches a browser.
enum Tabs {
    struct Tab { let title: String; let url: String; let browser: String; let appPath: String?; let window: Int; let index: Int }
    private static let chromium = ["com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac",
                                   "com.vivaldi.Vivaldi"]
    private static let webkit = ["com.apple.Safari", "com.kagi.kagimacOS"]   // Orion speaks Safari's dictionary

    static func read() -> [Tab] {
        var out: [Tab] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, chromium.contains(id) || webkit.contains(id), let name = app.localizedName else { continue }
            let titleKey = webkit.contains(id) ? "name" : "title"
            let src = """
            set out to ""
            tell application id "\(id)"
              set wi to 0
              repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                  set ti to ti + 1
                  set out to out & wi & tab & ti & tab & (\(titleKey) of t) & tab & (URL of t) & linefeed
                end repeat
              end repeat
            end tell
            return out
            """
            for line in System.osascript(src).split(separator: "\n") {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 4, let w = Int(f[0]), let i = Int(f[1]) else { continue }
                out.append(Tab(title: f[2], url: f[3], browser: name, appPath: app.bundleURL?.path, window: w, index: i))
            }
        }
        return out
    }

    static func focus(_ t: Tab) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == t.browser }),
              let id = app.bundleIdentifier else { return }
        let src = webkit.contains(id)
            ? "tell application id \"\(id)\"\nset current tab of window \(t.window) to tab \(t.index) of window \(t.window)\nset index of window \(t.window) to 1\nactivate\nend tell"
            : "tell application id \"\(id)\"\nset active tab index of window \(t.window) to \(t.index)\nset index of window \(t.window) to 1\nactivate\nend tell"
        DispatchQueue.global().async { _ = System.osascript(src) }
    }
}

/// The user's Shortcuts from the Shortcuts app, through the shortcuts CLI.
enum Shortcuts {
    static func list() -> [String] {
        System.run("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
    static func run(_ name: String) { DispatchQueue.global().async { _ = System.run("/usr/bin/shortcuts", ["run", name]) } }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
