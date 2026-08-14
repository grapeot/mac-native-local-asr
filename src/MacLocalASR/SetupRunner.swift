import AppKit
import Foundation

enum SetupRunner {
    static let installDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".maclocalasr")
    static let venvPython = installDir.appendingPathComponent(".venv/bin/python")
    static let bridgeScript = installDir.appendingPathComponent("start_asr_bridge.py")

    // Bridge script embedded as a string — written to disk during setup.
    // This eliminates any "file not found" dependency on the repo layout.
    static let bridgeScriptContent = #"""
#!/usr/bin/env python3
"""Minimal JSONL bridge for Qwen3-ASR on Apple Silicon via mlx-qwen3-asr."""

from __future__ import annotations
import argparse, json, sys
from pathlib import Path

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--local-files-only", action="store_true")
    args = parser.parse_args()

    try:
        from mlx_qwen3_asr import transcribe
    except ImportError:
        print(json.dumps({"type": "error", "message": "mlx-qwen3-asr not installed"}), flush=True)
        return 2

    model_loaded = {"v": False}
    def ensure_model():
        if model_loaded["v"]:
            return None
        try:
            from mlx_qwen3_asr import load_model
            load_model(args.model)
            model_loaded["v"] = True
            return None
        except Exception as e:
            return str(e)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            print(json.dumps({"type": "error", "message": "Invalid JSON"}), flush=True)
            continue
        t = req.get("type")
        if t == "start":
            err = ensure_model()
            if err:
                print(json.dumps({"type": "error", "message": f"Model load failed: {err}"}), flush=True)
                return 2
            print(json.dumps({"type": "ready"}), flush=True)
        elif t == "transcribe":
            ap = req.get("audio_path", "")
            if not ap or not Path(ap).is_file():
                print(json.dumps({"type": "error", "message": f"Audio not found: {ap}"}), flush=True)
                continue
            try:
                r = transcribe(ap, model=args.model, verbose=False, return_timestamps=False, return_chunks=True)
                chunks = r.chunks or []
                text = " ".join((c.get("text") or "").strip() for c in chunks).strip()
                if not text:
                    text = (r.text or "").strip()
                print(json.dumps({"type": "transcript", "text": text}), flush=True)
            except Exception as e:
                print(json.dumps({"type": "error", "message": str(e)}), flush=True)
        elif t == "stop":
            print(json.dumps({"type": "stopped"}), flush=True)
            break
        else:
            print(json.dumps({"type": "error", "message": f"Unknown type: {t}"}), flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
"""#

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

        // Step 5: Write bridge script from embedded content
        await MainActor.run { progress("Installing bridge script…") }
        try? FileManager.default.removeItem(at: bridgeScript)
        do {
            try bridgeScriptContent.write(to: bridgeScript, atomically: true, encoding: .utf8)
            // Make it executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgeScript.path)
        } catch {
            await MainActor.run { progress("Error writing bridge script: \(error.localizedDescription)") }
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