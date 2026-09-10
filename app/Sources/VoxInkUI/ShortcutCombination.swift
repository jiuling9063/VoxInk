import Carbon

public enum ShortcutCombination: String, CaseIterable, Sendable {
    case optionSpace, optionShiftSpace, controlOptionSpace

    public var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .optionShiftSpace: "⌥ ⇧ Space"
        case .controlOptionSpace: "⌃ ⌥ Space"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .optionShiftSpace: UInt32(optionKey | shiftKey)
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        }
    }
}
