// Drives Hop's real hotkeys against a throwaway Finder window and checks the resulting frames.
// Run it with `./build.sh snaptest`. It takes keyboard focus for a few seconds, never presses a snap
// key unless the test window is focused, then closes the window and gives focus back.
// Usage: snaptest <path to Hop binary> <empty config dir>
import AppKit
import ApplicationServices
import Carbon.HIToolbox

func sleep(_ s: Double) { Thread.sleep(forTimeInterval: s) }

func attr(_ el: AXUIElement, _ n: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}

func frame(_ el: AXUIElement) -> CGRect? {
    guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return nil }
    var o = CGPoint.zero, z = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &o)
    AXValueGetValue(s as! AXValue, .cgSize, &z)
    return CGRect(origin: o, size: z)
}

func press(_ key: Int, _ flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)
        // A physical arrow key also carries the numeric-pad and fn flags.
        let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        e?.flags = arrows.contains(key) ? flags.union([.maskNumericPad, .maskSecondaryFn]) : flags
        e?.post(tap: .cghidEventTap)
        sleep(0.03)
    }
}

guard CommandLine.arguments.count == 3 else { print("usage: snaptest <hop binary> <config dir>"); exit(2) }
guard AXIsProcessTrusted() else { print("harness is not trusted for Accessibility"); exit(2) }

// A Hop that is already running owns the hotkeys, so ours could not register them.
if !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.hop.launcher").isEmpty {
    print("Hop is already running; quit it first so the test instance can register the hotkeys")
    exit(2)
}

let previous = NSWorkspace.shared.frontmostApplication
print("frontmost before:", previous?.localizedName ?? "?")

// 1. Hop with defaults only.
let rf = Process()
rf.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
rf.environment = ["HOP_HOME": CommandLine.arguments[2]]
try! rf.run()
sleep(1.0)

// 2. A new Finder window, frontmost.
let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first!
let fax = AXUIElementCreateApplication(finder.processIdentifier)
let before = Set(((attr(fax, kAXWindowsAttribute) as? [AXUIElement]) ?? []).compactMap { attr($0, kAXTitleAttribute) as? String })
NSWorkspace.shared.open(URL(fileURLWithPath: NSTemporaryDirectory()))
sleep(1.2)
guard let wv = attr(fax, kAXFocusedWindowAttribute) else { print("no Finder window"); rf.terminate(); exit(1) }
let win = wv as! AXUIElement
let title = attr(win, kAXTitleAttribute) as? String ?? "?"
print("test window: Finder ·", title, before.contains(title) ? "(a window with this title already existed)" : "(new)")

// Seed a known starting frame so every run starts the same way.
var start = CGRect(x: 200, y: 200, width: 700, height: 500)
var p = start.origin, s = start.size
AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
sleep(0.3)
start = frame(win)!

// Expected frames in AX (top-left) coordinates on the window's screen.
let primaryH = NSScreen.screens[0].frame.height
let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: start.midX, y: primaryH - start.midY)) } ?? NSScreen.main!
let vf = screen.visibleFrame
let top = primaryH - vf.maxY
func ax(_ x: CGFloat, _ w: CGFloat, _ y: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: vf.minX + vf.width * x, y: top + vf.height * y, width: vf.width * w, height: vf.height * h).integral
}

let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]
var fails = 0
var skipped = 0
/// True only when the throwaway Finder window is the focused window of the frontmost app.
func testWindowFocused() -> Bool {
    // NSWorkspace.frontmostApplication goes stale without a run loop; ask Accessibility instead.
    var pid: pid_t = 0
    guard let app = attr(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute),
          AXUIElementGetPid(app as! AXUIElement, &pid) == .success, pid == finder.processIdentifier,
          let f = attr(fax, kAXFocusedWindowAttribute) else { return false }
    return CFEqual(f, win)
}
func step(_ name: String, _ key: Int, _ flags: CGEventFlags, expect: (CGRect) -> CGRect) {
    guard rf.isRunning else { print("FAIL", name, "· Hop is no longer running"); fails += 1; return }
    if !testWindowFocused() {
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(fax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        sleep(0.5)
    }
    // Never press a snap key unless it can only land on the test window.
    guard testWindowFocused() else { print("skip", name, "· focus is elsewhere"); skipped += 1; return }
    let was = frame(win)!
    press(key, flags)
    sleep(0.45)
    let got = frame(win)!
    let want = expect(was)
    let ok = abs(got.minX - want.minX) <= 2 && abs(got.minY - want.minY) <= 2
        && abs(got.width - want.width) <= 2 && abs(got.height - want.height) <= 2
    if !ok { fails += 1 }
    print(ok ? "ok  " : "FAIL", name.padding(toLength: 28, withPad: " ", startingAt: 0),
          "got", got.integral, ok ? "" : "want \(want)")
}

step("⌃⌥← Left Half", kVK_LeftArrow, ctrlOpt) { _ in ax(0, 0.5, 0, 1) }
step("⌃⌥← again → two thirds", kVK_LeftArrow, ctrlOpt) { _ in ax(0, 2.0 / 3, 0, 1) }
step("⌃⌥← again → one third", kVK_LeftArrow, ctrlOpt) { _ in ax(0, 1.0 / 3, 0, 1) }
step("⌃⌥→ Right Half", kVK_RightArrow, ctrlOpt) { _ in ax(0.5, 0.5, 0, 1) }
step("⌃⌥↑ Top Half", kVK_UpArrow, ctrlOpt) { _ in ax(0, 1, 0, 0.5) }
step("⌃⌥U Top Left Quarter", kVK_ANSI_U, ctrlOpt) { _ in ax(0, 0.5, 0, 0.5) }
step("⌃⌥K Bottom Right Quarter", kVK_ANSI_K, ctrlOpt) { _ in ax(0.5, 0.5, 0.5, 0.5) }
step("⌃⌥F Center Third", kVK_ANSI_F, ctrlOpt) { _ in ax(1.0 / 3, 1.0 / 3, 0, 1) }
step("⌃⌥E Left Two Thirds", kVK_ANSI_E, ctrlOpt) { _ in ax(0, 2.0 / 3, 0, 1) }
step("⌃⌥- Make Smaller", kVK_ANSI_Minus, ctrlOpt) { w in w.insetBy(dx: 40, dy: 40) }
step("⌃⌥C Center", kVK_ANSI_C, ctrlOpt) { w in
    CGRect(x: vf.midX - w.width / 2, y: top + vf.height / 2 - w.height / 2, width: w.width, height: w.height).integral
}
step("⌃⌥↩ Maximize", kVK_Return, ctrlOpt) { _ in ax(0, 1, 0, 1) }
step("⌃⌥⌫ Restore", kVK_Delete, ctrlOpt) { _ in start }

// Clean up: close the test window, quit Hop, give focus back.
if let close = attr(win, kAXCloseButtonAttribute) { AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) }
rf.terminate()
rf.waitUntilExit()
previous?.activate()
print(fails == 0 && skipped == 0 ? "\nall snaps correct" : "\n\(fails) failed, \(skipped) skipped")
exit(fails == 0 && skipped == 0 ? 0 : 1)
