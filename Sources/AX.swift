import AppKit
import ApplicationServices

// Accessibility, for menu search, window switching and paste. No SIP changes, no scripting additions.

enum AX {
    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func set(_ el: AXUIElement, _ name: String, _ v: CFTypeRef) {
        AXUIElementSetAttributeValue(el, name as CFString, v)
    }
    static func bool(_ el: AXUIElement, _ name: String) -> Bool { (attr(el, name) as? Bool) ?? false }
    static func string(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }

    static func app(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.3)   // a hung app must not hang us
        return el
    }

    private static var asked = false
    /// True when we may control other apps. The first time it is false, shows the system prompt.
    @discardableResult static func ensureTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !asked {
            asked = true
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        return false
    }
}
