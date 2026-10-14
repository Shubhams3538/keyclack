import CoreGraphics
import Foundation

/// System-wide key listener built on a listen-only Quartz event tap.
///
/// Listen-only means KeyClack can observe keystrokes but never modify, block or inject them.
/// It needs the Input Monitoring permission (System Settings › Privacy & Security). Keys typed
/// into password fields are hidden from all taps by macOS (Secure Input), so those are silent.
final class KeyMonitor {
    struct Event {
        let keyCode: Int
        let isDown: Bool
        let isRepeat: Bool
    }

    /// Called on the main thread.
    var onKey: ((Event) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Fallback press state for modifier keys we have no device flag for.
    private var heldModifiers = Set<Int>()

    var isRunning: Bool { tap != nil }

    /// Device-dependent modifier flags (NX_DEVICE*KEYMASK in IOLLEvent.h). The device-independent
    /// `.maskShift` can't tell "left shift released while right shift is still held" from a press.
    private static let modifierMasks: [Int: UInt64] = [
        56: 0x0000_0002, // left shift
        60: 0x0000_0004, // right shift
        59: 0x0000_0001, // left control
        62: 0x0000_2000, // right control
        58: 0x0000_0020, // left option
        61: 0x0000_0040, // right option
        55: 0x0000_0008, // left command
        54: 0x0000_0010, // right command
        63: 0x0080_0000, // fn
    ]

    /// Returns false if macOS refused the tap (permission not granted yet).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // Common modes: keep clicking while a menu is open or a window is being dragged.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        heldModifiers.removeAll()
    }

    deinit { stop() }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables a tap whose callback was slow; just turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown, .keyUp:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            onKey?(Event(keyCode: code, isDown: type == .keyDown, isRepeat: isRepeat))
        case .flagsChanged:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            onKey?(Event(keyCode: code, isDown: modifierIsDown(code, flags: event.flags), isRepeat: false))
        default:
            break
        }
    }

    private func modifierIsDown(_ code: Int, flags: CGEventFlags) -> Bool {
        // Caps Lock only reports a change per press (lock on, then lock off), never a release.
        if code == 57 { return true }
        if let mask = Self.modifierMasks[code] {
            return flags.rawValue & mask != 0
        }
        // Unknown modifier (e.g. the Globe key on some keyboards): alternate press/release.
        if heldModifiers.remove(code) != nil { return false }
        heldModifiers.insert(code)
        return true
    }
}

/// C-compatible tap callback; `refcon` is the unretained `KeyMonitor`.
private func keyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
