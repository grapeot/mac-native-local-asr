import SwiftUI

struct MainRecordView: View {
    @ObservedObject var appState: AppState
    @State private var showCopyCheckmark = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)

            // Timer
            Text(appState.recordingTimerText)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Spacer().frame(height: 24)

            // Status text
            Text(appState.statusText)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 32)

            // Waveform / level indicator
            MacWaveformView(
                mode: waveformMode,
                level: appState.audioLevel
            )
            .frame(height: 80)
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)

            // Transcript display
            transcriptArea

            Spacer(minLength: 24)

            // Primary action button
            primaryButton

            Spacer().frame(height: 16)

            // Secondary controls
            secondaryControls

            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    private var transcriptArea: some View {
        ScrollView {
            Text(appState.lastTranscript.isEmpty
                ? LocalizableStrings.transcriptPlaceholder
                : appState.lastTranscript
            )
            .font(.body)
            .foregroundStyle(appState.lastTranscript.isEmpty ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private var primaryButton: some View {
        Button(action: { appState.toggleRecording() }) {
            Text(appState.phase == .recording
                ? LocalizableStrings.stop
                : LocalizableStrings.record
            )
            .font(.system(size: 17, weight: .medium))
            .frame(width: 200, height: 48)
            .background(appState.phase == .recording
                ? Color.red.opacity(0.15)
                : Color.accentColor.opacity(0.15)
            )
            .foregroundStyle(appState.phase == .recording ? .red : .accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(appState.phase == .loading || appState.phase == .processing)
    }

    private var secondaryControls: some View {
        HStack(spacing: 32) {
            // Copy button
            Button(action: {
                appState.copyLastTranscript()
                showCopyCheckmark = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    showCopyCheckmark = false
                }
            }) {
                Image(systemName: showCopyCheckmark ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(appState.lastTranscript.isEmpty)

            // Settings button
            Button(action: {
                appDelegateShared?.showSettings()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - State

    private var waveformMode: MacWaveformView.Mode {
        switch appState.phase {
        case .recording: return .active
        case .processing: return .generating
        default: return .idle
        }
    }
}

// MARK: - Waveform (macOS version of VoiceFlow's WaveformView)

struct MacWaveformView: View {
    enum Mode {
        case idle
        case active
        case generating
    }

    var mode: Mode
    var level: Float = 0

    private let barCount = 23
    private let barWidth: CGFloat = 9
    private let barSpacing: CGFloat = 6

    @State private var history: [Float] = Array(repeating: 0, count: 23)
    @State private var lastTick: TimeInterval = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: mode == .idle)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let centerY = size.height / 2
                let total = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
                let originX = (size.width - total) / 2

                let snapshot = currentBars(at: t)

                for i in 0..<barCount {
                    let barX = originX + CGFloat(i) * (barWidth + barSpacing)
                    let height = snapshot[i] * (size.height - 4) + 2
                    let barHeight = max(height, 1)
                    let rect = CGRect(
                        x: barX,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    let radius = min(2, barWidth / 2, barHeight / 2)
                    let path = Path(roundedRect: rect, cornerRadius: radius)
                    context.fill(path, with: .color(barColor))
                }
            }
            .onChange(of: timeline.date) {
                if mode == .active {
                    advanceHistory(at: t)
                } else if mode == .idle && history.contains(where: { $0 > 0.01 }) {
                    history = history.map { $0 * 0.6 }
                }
            }
        }
        .opacity(mode == .idle ? 0.45 : 1.0)
    }

    private var barColor: Color {
        switch mode {
        case .idle: return .secondary
        case .active: return .red
        case .generating: return .orange
        }
    }

    private func advanceHistory(at t: TimeInterval) {
        guard t - lastTick >= 1.0 / 30.0 else { return }
        lastTick = t
        let sample = max(Float(0.04), level)
        history.removeFirst()
        history.append(sample)
    }

    private func currentBars(at t: TimeInterval) -> [CGFloat] {
        switch mode {
        case .idle:
            return Array(repeating: 0.02, count: barCount)
        case .active:
            return history.map { CGFloat($0) }
        case .generating:
            let speed = 12.0
            let position = (t * speed).truncatingRemainder(dividingBy: Double(barCount))
            return (0..<barCount).map { i in
                let distance = min(abs(Double(i) - position),
                                   Double(barCount) - abs(Double(i) - position))
                let intensity = max(0, 1 - distance / 3)
                return CGFloat(0.04 + intensity * 0.96)
            }
        }
    }
}