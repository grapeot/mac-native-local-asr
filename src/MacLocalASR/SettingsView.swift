import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage(SettingsStore.deviceKey) private var deviceID = ""
    @State private var devices: [(id: String, name: String)] = []

    var body: some View {
        Form {
            Section(LocalizableStrings.hotkey) {
                KeyboardShortcuts.Recorder(LocalizableStrings.hotkey, name: .toggleRecording)
            }

            Section(LocalizableStrings.inputDevice) {
                Picker(LocalizableStrings.inputDevice, selection: $deviceID) {
                    Text(LocalizableStrings.systemDefault).tag("")
                    ForEach(devices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
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
        .onAppear {
            devices = AudioCaptureManager.listInputDevices()
        }
    }
}