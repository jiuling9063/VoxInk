import VoxInkCore
import AppKit
import Carbon

public struct ShortcutCombination: RawRepresentable, Hashable, Sendable, CaseIterable {
    public let keyCode: UInt32
    let modifiers: UInt32

    public static let optionSpace = Self(uncheckedKey: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    public static let optionShiftSpace = Self(uncheckedKey: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))
    public static let controlOptionSpace = Self(uncheckedKey: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    public static let allCases: [Self] = [.optionSpace, .optionShiftSpace, .controlOptionSpace]
    private static let names = ["optionSpace", "optionShiftSpace", "controlOptionSpace"]
    private static let modifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    private init(uncheckedKey: UInt32, modifiers: UInt32) {
        keyCode = uncheckedKey; self.modifiers = modifiers
    }

    init?(keyCode: UInt32, modifiers: UInt32) {
        guard Self.validationMessage(keyCode: keyCode, modifiers: modifiers) == nil else { return nil }
        self.init(uncheckedKey: keyCode, modifiers: modifiers)
    }

    public init?(rawValue: String) {
        if let index = Self.names.firstIndex(of: rawValue) { self = Self.allCases[index]; return }
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "custom-v1",
              let key = UInt32(parts[1]), let modifiers = UInt32(parts[2]) else { return nil }
        self.init(keyCode: key, modifiers: modifiers)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode); hasher.combine(modifiers)
    }

    public var rawValue: String {
        if let index = Self.allCases.firstIndex(of: self) { return Self.names[index] }
        return "custom-v1:\(keyCode):\(modifiers)"
    }

    public var title: String {
        let symbols: [(UInt32, String)] = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"),
                                          (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
        return (symbols.filter { modifiers & $0.0 != 0 }.map(\.1) + [keyTitle]).joined(separator: " ")
    }

    private var keyTitle: String {
        if let special = Self.specialKeys[keyCode] { return special }
        // Translate the physical key using the current keyboard layout, without modifiers.
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            if let bytes = CFDataGetBytePtr(data) {
                let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKey: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let result = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKey,
                    characters.count, &length, &characters)
                if result == noErr, length > 0 {
                    return String(utf16CodeUnits: characters, count: length).uppercased()
                }
            }
        }
        return Self.printableKeys[keyCode] ?? "Key \(keyCode)"
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey),
                               (.shift, shiftKey), (.command, cmdKey)] where flags.contains(flag) {
            result |= UInt32(carbon)
        }
        return result
    }

    static func validationMessage(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard modifiers & ~modifierMask == 0,
              modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else {
            return L("请至少搭配 ⌃ Control、⌥ Option 或 ⌘ Command。")
        }
        guard printableKeys[keyCode] != nil || specialKeys[keyCode] != nil else {
            return L("请选择字母、数字、标点、空格或 F1–F20；Esc 留作取消。")
        }
        if modifiers == UInt32(cmdKey) {
            return L("为避免占用复制、粘贴等操作，请再搭配一个修饰键。")
        }
        if keyCode == UInt32(kVK_Space),
           [UInt32(cmdKey), UInt32(cmdKey | optionKey), UInt32(controlKey), UInt32(controlKey | optionKey | cmdKey)].contains(modifiers) {
            return L("这个组合常用于系统搜索或输入法，请换一个组合。")
        }
        if modifiers == UInt32(cmdKey | shiftKey), [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)].contains(keyCode) {
            return L("这个组合用于系统截屏，请换一个组合。")
        }
        return nil
    }

    var cancellationModifiers: [UInt32] {
        [UInt32(optionKey), UInt32(shiftKey), UInt32(controlKey), UInt32(cmdKey)]
            .filter { modifiers & $0 != 0 }
            .reduce([UInt32(0)]) { combinations, modifier in
                combinations + combinations.map { $0 | modifier }
            }
    }

    private static let printableKeys: [UInt32: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
        12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4",
        22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]", 31:"O",
        32:"U", 33:"[", 34:"I", 35:"P", 37:"L", 38:"J", 39:"'", 40:"K", 41:";", 42:"\\",
        43:",", 44:"/", 45:"N", 46:"M", 47:".", 50:"`"
    ]
    private static let specialKeys: [UInt32: String] = [
        49:"Space", 122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8",
        101:"F9", 109:"F10", 103:"F11", 111:"F12", 105:"F13", 107:"F14", 113:"F15", 106:"F16",
        64:"F17", 79:"F18", 80:"F19", 90:"F20"
    ]
}
