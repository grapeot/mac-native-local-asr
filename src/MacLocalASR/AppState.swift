import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case idle
        case recording
        case processing
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastAction = ""
    @Published private(set) var isBridgeReady = false

    private let audioCapture = AudioCaptureManager()
    private let bridgeClient = ASRBridgeClient()
    private let textOutput = TextOutputManager()
    private var hotkeyManager: HotkeyManager?
    private var errorTask: Task<Void, Never>?

    init() {
        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }

        audioCapture.onMaximumDuration = { [weak self] in
            Task { @MainActor in
                await self?.stopAndTranscribe()
            }
        }
        audioCapture.onDeviceUnavailable = { [weak self] in
            Task { @MainActor in
                self?.audioCapture.cancelRecording()
                self?.showError(LocalizableStrings.audioDeviceUnavailable)
            }
        }

        // Prompt for Accessibility once at startup so auto-paste works later
        TextOutputManager.promptAccessibilityIfNeeded()

        Task {
            await startBridge()
        }
    }

    var menuBarSymbol: String {
        switch phase {
        case .loading, .idle:
            "waveform.circle"
        case .recording:
            "waveform.circle.fill"
        case .processing:
            "waveform.circle.badge.ellipsis"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    var stateColor: Color {
        switch phase {
        case .loading:
            .secondary
        case .idle:
            .green
        case .recording, .error:
            .red
        case .processing:
            .yellow
        }
    }

    var statusText: String {
        switch phase {
        case .loading:
            LocalizableStrings.loadingModel
        case .idle:
            lastAction.isEmpty ? LocalizableStrings.ready : lastAction
        case .recording:
            LocalizableStrings.recording
        case .processing:
            LocalizableStrings.transcribing
        case .error(let message):
            "\(LocalizableStrings.errorPrefix) \(message)"
        }
    }

    var modelStatusText: String {
        switch phase {
        case .loading:
            LocalizableStrings.loadingModel
        case .error(let message):
            "\(LocalizableStrings.errorPrefix) \(message)"
        default:
            isBridgeReady ? LocalizableStrings.modelLoaded : LocalizableStrings.notConfigured
        }
    }

    var truncatedTranscript: String {
        guard lastTranscript.count > 50 else { return lastTranscript }
        return String(lastTranscript.prefix(50)) + "..."
    }

    func toggleRecording() {
        switch phase {
        case .idle:
            Task { await beginRecording() }
        case .recording:
            Task { await stopAndTranscribe() }
        case .loading, .processing, .error:
            break
        }
    }

    func restartBridge() {
        isBridgeReady = false
        Task {
            await bridgeClient.stop()
            await startBridge()
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        textOutput.copy(lastTranscript)
        lastAction = LocalizableStrings.copiedToClipboard
    }

    func shutdown() async {
        errorTask?.cancel()
        audioCapture.cancelRecording()
        await bridgeClient.stop()
        isBridgeReady = false
    }

    private func startBridge() async {
        errorTask?.cancel()
        phase = .loading
        lastAction = ""

        do {
            let settings = try SettingsStore.current()
            try await bridgeClient.start(
                bridgePath: settings.bridgePath,
                modelPath: settings.modelPath
            )
            isBridgeReady = true
            phase = .idle
        } catch {
            isBridgeReady = false
            showError(error.localizedDescription, returnsToIdle: false)
        }
    }

    private func beginRecording() async {
        guard await bridgeClient.ready else {
            isBridgeReady = false
            showError(LocalizableStrings.engineNotReady)
            return
        }

        do {
            try await audioCapture.startRecording()
            lastAction = ""
            phase = .recording
        } catch {
            isBridgeReady = await bridgeClient.ready
            showError(error.localizedDescription)
        }
    }

    private func stopAndTranscribe() async {
        guard phase == .recording else { return }
        phase = .processing

        do {
            let audioURL = try audioCapture.stopRecording()
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let transcript = try await bridgeClient.transcribe(audioURL: audioURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                throw AppError.emptyTranscript
            }

            lastTranscript = transcript
            lastAction = textOutput.output(transcript)
                ? LocalizableStrings.pasted
                : LocalizableStrings.copiedToClipboard
            phase = .idle
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String, returnsToIdle: Bool = true) {
        errorTask?.cancel()
        phase = .error(message)
        guard returnsToIdle else { return }

        errorTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isBridgeReady = await bridgeClient.ready
            phase = isBridgeReady ? .idle : .error(LocalizableStrings.engineNotReady)
        }
    }
}

private enum AppError: LocalizedError {
    case emptyTranscript

    var errorDescription: String? {
        LocalizableStrings.emptyTranscript
    }
}
