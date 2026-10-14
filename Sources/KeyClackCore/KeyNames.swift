/// macOS virtual key codes (the `kVK_*` constants from Carbon's Events.h) and their display names.
/// Codes are positional (ANSI layout), so on non-US layouts the letter shown may differ from the
/// key cap — it still identifies the same physical key.
public enum KeyCode {
    /// Not a real key: the custom sound entry used for every key without one of its own.
    public static let allOtherKeys = -1
    public static let backspace = 51 // kVK_Delete
    public static let forwardDelete = 117
    public static let space = 49
    public static let returnKey = 36
    public static let keypadEnter = 76
    public static let tab = 48
    public static let capsLock = 57
    public static let leftShift = 56
    public static let rightShift = 60

    /// Keys that are physically long (stabilised) on a real board and get the deeper "thock".
    public static let largeKeys: Set<Int> = [
        space, returnKey, keypadEnter, tab, capsLock, leftShift, rightShift, backspace, forwardDelete,
    ]

    public static func isLarge(_ code: Int) -> Bool { largeKeys.contains(code) }

    public static func name(for code: Int) -> String {
        if code == allOtherKeys { return "All other keys" }
        return names[code] ?? "Key \(code)"
    }

    private static let names: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
        50: "`",
        backspace: "Backspace", forwardDelete: "Forward Delete", space: "Space", returnKey: "Return",
        keypadEnter: "Enter (keypad)", tab: "Tab", capsLock: "Caps Lock", 53: "Escape",
        leftShift: "Left Shift", rightShift: "Right Shift", 59: "Left Control", 62: "Right Control",
        58: "Left Option", 61: "Right Option", 55: "Left Command", 54: "Right Command", 63: "fn",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 114: "Help",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear", 75: "Keypad /",
        78: "Keypad -", 81: "Keypad =",
    ]
}
