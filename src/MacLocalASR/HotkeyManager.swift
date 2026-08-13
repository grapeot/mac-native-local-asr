import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self(
        "toggleRecording",
        default: .init(.space, modifiers: [.command, .shift])
    )
}

@MainActor
final class HotkeyManager {
    init(action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            Task { @MainActor in action() }
        }
    }
}
