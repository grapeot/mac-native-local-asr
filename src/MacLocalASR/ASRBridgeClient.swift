import Foundation

actor ASRBridgeClient {
    private(set) var isReady = false

    private var process: Process?
    private var inputHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var pendingResponse: CheckedContinuation<BridgeResponse, Error>?
    private var responseTimeoutTask: Task<Void, Never>?
    private var diagnosticLines: [String] = []
    private var bridgePath = ""
    private var modelPath = ""
    private var restartAttempts = 0
    private var stopping = false

    var ready: Bool { isReady }

    func start(bridgePath: String, modelPath: String) async throws {
        self.bridgePath = bridgePath
        self.modelPath = modelPath
        restartAttempts = 0
        try await launchAndWaitUntilReady()
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard isReady else { throw BridgeError.notReady }

        do {
            let response = try await request(
                ["type": "transcribe", "audio_path": audioURL.path],
                timeout: .seconds(15)
            )
            guard response.type == "transcript", let text = response.text else {
                throw BridgeError.unexpectedResponse
            }
            return text
        } catch {
            await terminateProcess()
            try? await restartAfterFailure()
            throw error
        }
    }

    func stop() async {
        stopping = true
        if process?.isRunning == true {
            try? send(["type": "stop"])
            try? await Task.sleep(for: .seconds(2))
        }
        await terminateProcess()
        stopping = false
    }

    private func launchAndWaitUntilReady() async throws {
        await terminateProcess()

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let bridgeURL = URL(fileURLWithPath: bridgePath)
        let projectPython = bridgeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: projectPython.path) {
            process.executableURL = projectPython
            process.arguments = [bridgePath, "--model", modelPath, "--local-files-only"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3",
                bridgePath,
                "--model", modelPath,
                "--local-files-only"
            ]
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self, weak process] _ in
            guard let process else { return }
            Task { await self?.processTerminated(process) }
        }

        self.process = process
        inputHandle = stdinPipe.fileHandleForWriting
        stdoutTask = Task { [weak self] in
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    await self?.handleStdoutLine(line)
                }
            } catch {
                await self?.failPending(error)
            }
        }
        stderrTask = Task { [weak self] in
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    await self?.appendDiagnostic(line)
                }
            } catch {
                return
            }
        }

        do {
            try process.run()
            let response = try await request(["type": "start"], timeout: .seconds(30))
            guard response.type == "ready" else {
                throw BridgeError.modelLoadFailed(response.message)
            }
            isReady = true
        } catch {
            await terminateProcess()
            throw error
        }
    }

    private func request(
        _ object: [String: String],
        timeout: Duration
    ) async throws -> BridgeResponse {
        guard pendingResponse == nil else { throw BridgeError.requestInProgress }
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponse = continuation
            responseTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.failPending(BridgeError.timeout)
            }
            do {
                try send(object)
            } catch {
                responseTimeoutTask?.cancel()
                responseTimeoutTask = nil
                pendingResponse = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func send(_ object: [String: String]) throws {
        guard process?.isRunning == true, let inputHandle else {
            throw BridgeError.processExited
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let response = try? JSONDecoder().decode(BridgeResponse.self, from: data) else {
            appendDiagnostic("Skipped non-JSON stdout: \(line)")
            return
        }
        guard let pendingResponse else {
            appendDiagnostic("Unexpected bridge message: \(line)")
            return
        }
        self.pendingResponse = nil
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil

        if response.type == "error" {
            pendingResponse.resume(
                throwing: BridgeError.runtime(response.message ?? LocalizableStrings.unknownError)
            )
        } else {
            pendingResponse.resume(returning: response)
        }
    }

    private func appendDiagnostic(_ line: String) {
        diagnosticLines.append(line)
        if diagnosticLines.count > 50 {
            diagnosticLines.removeFirst(diagnosticLines.count - 50)
        }
    }

    private func processTerminated(_ terminatedProcess: Process) async {
        guard process === terminatedProcess else { return }
        let hadPendingResponse = pendingResponse != nil
        isReady = false
        failPending(BridgeError.processExited)
        guard !stopping, !hadPendingResponse else { return }
        try? await restartAfterFailure()
    }

    private func failPending(_ error: Error) {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        pendingResponse?.resume(throwing: error)
        pendingResponse = nil
    }

    private func restartAfterFailure() async throws {
        while restartAttempts < 3 {
            let delay = 1 << restartAttempts
            restartAttempts += 1
            try await Task.sleep(for: .seconds(delay))
            do {
                try await launchAndWaitUntilReady()
                restartAttempts = 0
                return
            } catch {
                continue
            }
        }
        throw BridgeError.restartFailed
    }

    private func terminateProcess() async {
        isReady = false
        failPending(BridgeError.processExited)
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil
        try? inputHandle?.close()
        inputHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }
}

private struct BridgeResponse: Decodable, Sendable {
    let type: String
    let text: String?
    let message: String?
}

enum BridgeError: LocalizedError {
    case notReady
    case processExited
    case timeout
    case requestInProgress
    case unexpectedResponse
    case modelLoadFailed(String?)
    case runtime(String)
    case restartFailed

    var errorDescription: String? {
        switch self {
        case .notReady:
            LocalizableStrings.engineNotReady
        case .processExited:
            LocalizableStrings.engineCrashed
        case .timeout:
            LocalizableStrings.transcriptionTimedOut
        case .requestInProgress:
            LocalizableStrings.requestInProgress
        case .unexpectedResponse:
            LocalizableStrings.unexpectedBridgeResponse
        case .modelLoadFailed(let message):
            message ?? LocalizableStrings.modelLoadFailed
        case .runtime(let message):
            message
        case .restartFailed:
            LocalizableStrings.engineRestartFailed
        }
    }
}
