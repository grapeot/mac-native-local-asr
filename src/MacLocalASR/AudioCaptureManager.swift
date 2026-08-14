@preconcurrency import AVFoundation
import Foundation

final class AudioCaptureManager: NSObject, @unchecked Sendable {
    static let sampleRate = 24_000.0
    static let maximumDuration: TimeInterval = 60

    var onMaximumDuration: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    var selectedDeviceID: String?

    private let queue = DispatchQueue(label: "MacLocalASR.AudioCapture")
    private let sessionQueue = DispatchQueue(label: "MacLocalASR.CaptureSession")
    private let sampleBufferQueue = DispatchQueue(label: "MacLocalASR.CaptureOutput")
    private var pcmData = Data()
    private var maximumDurationTask: Task<Void, Never>?
    private var isRecording = false
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    static func listInputDevices() -> [(id: String, name: String)] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { ($0.uniqueID, $0.localizedName) }
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

        let session = AVCaptureSession()

        // Find the selected device or use default
        var device: AVCaptureDevice?
        if let deviceID = selectedDeviceID, !deviceID.isEmpty {
            device = AVCaptureDevice(uniqueID: deviceID)
        }
        if device == nil {
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device else {
            throw AudioCaptureError.noInputDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        session.addOutput(output)
        audioOutput = output

        guard let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.converterUnavailable
        }
        queue.sync {
            pcmData.removeAll(keepingCapacity: true)
            converter = nil
            outputFormat = destinationFormat
        }

        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        captureSession = session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }
        guard session.isRunning else {
            captureSession = nil
            audioOutput = nil
            queue.sync {
                converter = nil
                outputFormat = nil
            }
            throw AudioCaptureError.engineStartFailed("Audio capture session did not start")
        }
        queue.sync { isRecording = true }

        maximumDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumDuration))
            guard !Task.isCancelled else { return }
            self?.onMaximumDuration?()
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
        try PCM16WAVEncoder.makeWAV(
            from: data,
            sampleRate: UInt32(Self.sampleRate),
            channels: 1
        ).write(to: url, options: .atomic)
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
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        queue.sync {
            converter = nil
            outputFormat = nil
            isRecording = false
        }
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
}

extension AudioCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let destinationFormat: AVAudioFormat = queue.sync(execute: { outputFormat }),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let inputFormat = AVAudioFormat(streamDescription: streamDescription) else {
            return
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return
        }
        inputBuffer.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        ) == noErr else {
            return
        }

        let activeConverter: AVAudioConverter? = queue.sync {
            if converter == nil || converter?.inputFormat != inputFormat {
                converter = AVAudioConverter(from: inputFormat, to: destinationFormat)
            }
            return converter
        }
        guard let activeConverter else { return }

        let ratio = destinationFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 1
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: destinationFormat,
            frameCapacity: outputCapacity
        ) else {
            return
        }

        let inputState = ConverterInputState()
        var conversionError: NSError?
        let status = activeConverter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
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
              let samples = outputBuffer.int16ChannelData?[0] else {
            return
        }

        let sampleCount = Int(outputBuffer.frameLength)
        var sumSquares: Float = 0
        for index in 0..<sampleCount {
            let sample = Float(samples[index]) / 32_768.0
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(max(sampleCount, 1)))
        let decibels = 20 * log10(max(rms, 1e-7))
        onAudioLevel?(max(0, min(1, (decibels + 80) / 70)))

        let chunk = Data(bytes: samples, count: sampleCount * MemoryLayout<Int16>.size)
        queue.sync {
            guard isRecording else { return }
            pcmData.append(chunk)
        }
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var wasSupplied = false
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
