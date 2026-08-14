import AppKit
import Foundation

enum SetupRunner {
    static let installDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".maclocalasr")
    static let venvPython = installDir.appendingPathComponent(".venv/bin/python")
    static let bridgeScript = installDir.appendingPathComponent("start_asr_bridge.py")

    static func isSetupComplete() -> Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
            && FileManager.default.fileExists(atPath: bridgeScript.path)
    }

    static func runSetup(progress: @escaping @MainActor (String) -> Void) async -> Bool {
        await MainActor.run { progress("Creating install directory…") }
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        // Step 1: Find system python3
        let sysPython = findSystemPython3()
        guard let sysPython else {
            await MainActor.run { progress("Error: Python 3 not found. Install with: brew install python3") }
            return false
        }

        // Step 2: Create venv (if not exists or broken)
        if !FileManager.default.isExecutableFile(atPath: venvPython.path) {
            await MainActor.run { progress("Creating Python environment…") }
            let result = await runProcess(sysPython, args: ["-m", "venv", installDir.appendingPathComponent(".venv").path])
            if !result.success {
                await MainActor.run { progress("Error creating venv: \(result.stderr)") }
                return false
            }
        }

        // Step 3: Install mlx-qwen3-asr
        await MainActor.run { progress("Installing mlx-qwen3-asr (this may take a minute)…") }
        _ = await runProcess(venvPython.path, args: ["-m", "pip", "install", "--upgrade", "pip", "--quiet"])
        let installResult = await runProcess(venvPython.path, args: ["-m", "pip", "install", "mlx-qwen3-asr", "--quiet"])
        if !installResult.success {
            await MainActor.run { progress("Error installing mlx-qwen3-asr: \(installResult.stderr)") }
            return false
        }

        // Step 4: Verify import
        let checkResult = await runProcess(venvPython.path, args: ["-c", "import mlx_qwen3_asr"])
        if !checkResult.success {
            await MainActor.run { progress("Error: mlx-qwen3-asr import failed") }
            return false
        }

        // Step 5: Copy bridge script
        await MainActor.run { progress("Installing bridge script…") }
        let bridgeSource = findBridgeScript()
        guard let bridgeSource else {
            await MainActor.run { progress("Error: start_asr_bridge.py not found") }
            return false
        }
        try? FileManager.default.removeItem(at: bridgeScript)
        do {
            try FileManager.default.copyItem(at: bridgeSource, to: bridgeScript)
        } catch {
            await MainActor.run { progress("Error copying bridge script: \(error.localizedDescription)") }
            return false
        }

        await MainActor.run { progress("") }
        return true
    }

    private static func findSystemPython3() -> String? {
        for candidate in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            let result = runProcessSync(candidate, args: ["--version"])
            if result.success && result.stdout.contains("Python 3") {
                return candidate
            }
        }
        return nil
    }

    private static func findBridgeScript() -> URL? {
        let candidates = [
            // Relative to executable
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/start_asr_bridge.py"),
            // From cwd (swift run uses src/)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../scripts/start_asr_bridge.py"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts/start_asr_bridge.py"),
            // Repo root from src/
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../../scripts/start_asr_bridge.py"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private struct ProcessResult {
        let success: Bool
        let stdout: String
        let stderr: String
    }

    private static func runProcess(_ executable: String, args: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ProcessResult(success: false, stdout: "", stderr: error.localizedDescription))
                return
            }
            process.terminationHandler = { proc in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(success: proc.terminationStatus == 0, stdout: stdout, stderr: stderr))
            }
        }
    }

    private static func runProcessSync(_ executable: String, args: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ProcessResult(success: process.terminationStatus == 0, stdout: stdout, stderr: stderr)
        } catch {
            return ProcessResult(success: false, stdout: "", stderr: error.localizedDescription)
        }
    }
}