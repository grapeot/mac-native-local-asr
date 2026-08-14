import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section(LocalizableStrings.hotkey) {
                KeyboardShortcuts.Recorder(LocalizableStrings.hotkey, name: .toggleRecording)
            }

            Section(LocalizableStrings.status) {
                HStack {
                    Text(appState.modelStatusText)
                    Spacer()
                    if !appState.isConfigured {
                        Button(LocalizableStrings.setup) {
                            Task { await appState.runSetup() }
                        }
                    }
                }
                if !appState.setupProgress.isEmpty {
                    Text(appState.setupProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button(LocalizableStrings.close) {
                        appState.restartBridge()
                        NSApp.keyWindow?.close()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}