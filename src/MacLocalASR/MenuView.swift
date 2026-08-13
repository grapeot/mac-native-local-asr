import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Label {
            Text(appState.statusText)
        } icon: {
            Image(systemName: "circle.fill")
                .foregroundStyle(appState.stateColor)
        }
            .disabled(true)

        if !appState.lastTranscript.isEmpty {
            Button("\(LocalizableStrings.lastPrefix) \(appState.truncatedTranscript)") {
                appState.copyLastTranscript()
            }
        }

        Divider()

        Button(LocalizableStrings.settings) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button(LocalizableStrings.quit) {
            Task {
                await appState.shutdown()
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }
}
