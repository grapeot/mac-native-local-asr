import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage(SettingsStore.bridgePathKey) private var bridgePath = ""
    @AppStorage(SettingsStore.modelPathKey) private var modelPath = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(LocalizableStrings.hotkey, name: .toggleRecording)

            LabeledContent(LocalizableStrings.bridgePath) {
                HStack {
                    TextField(LocalizableStrings.bridgePath, text: $bridgePath)
                    Button(LocalizableStrings.browse) {
                        chooseBridge()
                    }
                }
            }

            LabeledContent(LocalizableStrings.modelPath) {
                HStack {
                    TextField(LocalizableStrings.modelPath, text: $modelPath)
                    Button(LocalizableStrings.browse) {
                        chooseModelDirectory()
                    }
                }
            }

            LabeledContent(LocalizableStrings.status) {
                Text(appState.modelStatusText)
                    .lineLimit(1)
            }

            HStack {
                Spacer()
                Button(LocalizableStrings.close) {
                    appState.restartBridge()
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseBridge() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pythonScript]
        if panel.runModal() == .OK, let url = panel.url {
            bridgePath = url.path
        }
    }

    private func chooseModelDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            modelPath = url.path
        }
    }
}
