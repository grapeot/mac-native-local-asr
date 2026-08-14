@preconcurrency import AVFoundation
import Foundation

final class AudioCaptureManager: @unchecked Sendable {
    static let sampleRate = 24_000.0
    static let maximumDuration: TimeInterval = 60

    var onMaximumDuration: (() -> Void)?
    var onDeviceUnavailable: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "MacLocalASR.AudioCapture")
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var pcmData = Data()
    private var maximumDurationTask: Task<Void, Never>?
    private var deviceObserver: NSObjectProtocol?
    private var isRecording = false
    private var previousDeviceUID: String?
    var selectedDeviceID: String?  // nil = system default

    // List available audio input devices
    static func listInputDevices() -> [(id: String, name: String)] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { ($0.uniqueID, $0.localizedName) }
    }

    // Set system default input device by uniqueID
    static func setDefaultInputDevice(uniqueID: String) {
        var deviceUID = uniqueID as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var propertyID = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // First get the current device ID to restore later
        // Then set the new one
        var deviceID = AudioDeviceID(0)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyID, 0, nil, &deviceIDSize, &deviceID)

        // Find device by UID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesCount = UInt32(0)
        var devicesDataSize = UInt32(0)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &devicesDataSize)
        devicesCount = devicesDataSize / UInt32(MemoryLayout<AudioDeviceID>.size)
        var devices = [AudioDeviceID](repeating: 0, count: Int(devicesCount))
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &devicesDataSize, &devices)

        for device in devices {
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidProperty = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(device, &uidProperty, 0, nil, &uidSize, &uid) == noErr {
                if (uid as String) == uniqueID {
                    var newDeviceID = device
                    AudioObjectSetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &propertyID,
                        0, nil,
                        UInt32(MemoryLayout<AudioDeviceID>.size),
                        &newDeviceID
                    )
                    return
                }
            }
        }
    }

    static func getDefaultInputDeviceUID() -> String? {
        var propertyID = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyID, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &uidProperty, 0, nil, &uidSize, &uid) == noErr else {
            return nil
        }
        return uid as String
    }

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

        // Switch to selected device if specified
        if let deviceID = selectedDeviceID, !deviceID.isEmpty {
            previousDeviceUID = Self.getDefaultInputDeviceUID()
            Self.setDefaultInputDevice(uniqueID: deviceID)
            // Give the system a moment to switch
            try? await Task.sleep(for: .milliseconds(200))
        }

        // Re-create engine to pick up the new default device
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
        // Restore previous default input device
        if let prevUID = previousDeviceUID {
            Self.setDefaultInputDevice(uniqueID: prevUID)
            previousDeviceUID = nil
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

        // Compute RMS audio level for UI feedback
        let level: Float = {
            guard byteCount > 0 else { return 0 }
            var sumSquares: Float = 0
            let sampleCount = byteCount / MemoryLayout<Int16>.size
            audioBuffer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                for i in 0..<sampleCount {
                    let s = Float(ptr[i]) / 32768.0
                    sumSquares += s * s
                }
            }
            let rms = sqrt(sumSquares / Float(max(sampleCount, 1)))
            let db = 20 * log10(max(rms, 1e-7))
            let normalized = Float(max(0, min(1, (db + 50) / 40)))
            return normalized
        }()
        onAudioLevel?(level)

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