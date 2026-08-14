import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var appState: AppState

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

        if !appState.isConfigured {
            Button(LocalizableStrings.setup) {
                appDelegateShared?.showSettings()
                Task { await appState.runSetup() }
            }
        }

        Button(LocalizableStrings.settings) {
            appDelegateShared?.showSettings()
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