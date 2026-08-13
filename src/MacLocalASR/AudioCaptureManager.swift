@preconcurrency import AVFoundation
import Foundation

final class AudioCaptureManager: @unchecked Sendable {
    static let sampleRate = 24_000.0
    static let maximumDuration: TimeInterval = 60

    var onMaximumDuration: (() -> Void)?
    var onDeviceUnavailable: (() -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "MacLocalASR.AudioCapture")
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var pcmData = Data()
    private var maximumDurationTask: Task<Void, Never>?
    private var deviceObserver: NSObjectProtocol?
    private var isRecording = false

    deinit {
        removeDeviceListener()
    }

    func startRecording() async throws {
        guard await requestMicrophoneAccess() else {
            throw AudioCaptureError.microphoneAccessDenied
        }

        let shouldStart = queue.sync { () -> Bool in
            guard !isRecording else { return false }
            return true
        }
        guard shouldStart else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }
        guard let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ), let newConverter = AVAudioConverter(from: inputFormat, to: destinationFormat) else {
            throw AudioCaptureError.converterUnavailable
        }

        queue.sync {
            pcmData.removeAll(keepingCapacity: true)
            converter = newConverter
            outputFormat = destinationFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndAppend(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            queue.sync { isRecording = true }
            installDeviceListener()
            maximumDurationTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.maximumDuration))
                guard !Task.isCancelled else { return }
                self?.onMaximumDuration?()
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }

    func stopRecording() throws -> URL {
        let recording = queue.sync { isRecording }
        guard recording else { throw AudioCaptureError.notRecording }
        stopEngine()

        let data = queue.sync { pcmData }
        guard !data.isEmpty else { throw AudioCaptureError.noAudioCaptured }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacLocalASR-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try makeWAV(from: data).write(to: url, options: .atomic)
        return url
    }

    func cancelRecording() {
        let recording = queue.sync { isRecording }
        guard recording else { return }
        stopEngine()
        queue.sync {
            pcmData.removeAll(keepingCapacity: false)
        }
    }

    private func stopEngine() {
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.sync {
            converter = nil
            outputFormat = nil
            isRecording = false
        }
    }

    private func convertAndAppend(_ inputBuffer: AVAudioPCMBuffer) {
        let activeConverter: AVAudioConverter? = queue.sync { converter }
        let activeFormat: AVAudioFormat? = queue.sync { outputFormat }
        guard let converter = activeConverter, let outputFormat = activeFormat else { return }

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        let inputState = ConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if inputState.wasSupplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputState.wasSupplied = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        guard conversionError == nil,
              status != .error,
              outputBuffer.frameLength > 0,
              let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers.mData else {
            return
        }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        let chunk = Data(bytes: audioBuffer, count: byteCount)
        queue.sync {
            pcmData.append(chunk)
        }
    }

    private func makeWAV(from pcm: Data) -> Data {
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + pcm.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(Self.sampleRate))
        data.appendLittleEndian(UInt32(Self.sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        default:
            false
        }
    }

    private func installDeviceListener() {
        guard deviceObserver == nil else { return }
        deviceObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let recording = self.queue.sync { self.isRecording }
            guard recording else { return }
            self.onDeviceUnavailable?()
        }
    }

    private func removeDeviceListener() {
        guard let deviceObserver else { return }
        NotificationCenter.default.removeObserver(deviceObserver)
        self.deviceObserver = nil
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var wasSupplied = false
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii)!)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

enum AudioCaptureError: LocalizedError {
    case microphoneAccessDenied
    case noInputDevice
    case converterUnavailable
    case engineStartFailed(String)
    case notRecording
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            LocalizableStrings.microphoneAccessRequired
        case .noInputDevice:
            LocalizableStrings.noInputDevice
        case .converterUnavailable:
            LocalizableStrings.audioConversionFailed
        case .engineStartFailed(let message):
            message
        case .notRecording:
            LocalizableStrings.notRecording
        case .noAudioCaptured:
            LocalizableStrings.noAudioCaptured
        }
    }
}