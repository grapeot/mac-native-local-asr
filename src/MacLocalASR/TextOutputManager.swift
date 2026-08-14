import AppKit
import Carbon.HIToolbox

struct TextOutputManager {
    @discardableResult
    func copy(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    func output(_ text: String) -> Bool {
        copy(text)
    }
}
