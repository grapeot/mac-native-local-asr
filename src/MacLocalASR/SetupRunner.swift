import AppKit
import Foundation

enum SetupRunner {
    static let installDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".maclocalasr")
    static let venvPython = installDir.appendingPathComponent(".venv/bin/python")
    static let bridgeScript = installDir.appendingPathComponent("start_asr_bridge.py")
    static let mlxQwen3ASRVersion = "0.3.5"

    // Bridge script embedded as a string — written to disk during setup.
    // This eliminates any "file not found" dependency on the repo layout.
    static let bridgeScriptContent = #"""
#!/usr/bin/env python3
"""Minimal JSONL transcription bridge for Qwen3-ASR on Apple Silicon."""

from __future__ import annotations
import argparse, json, sys
from pathlib import Path

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--local-files-only", action="store_true")
    args = parser.parse_args()

    try:
        from mlx_qwen3_asr import transcribe, load_model
    except ImportError:
        print(json.dumps({"type": "error", "message": "mlx-qwen3-asr not installed"}), flush=True)
        return 2

    resolved_model_path = {"v": None}

    def resolve_model_path() -> str:
        local = Path(args.model)
        if local.is_dir() and (local / "config.json").is_file():
            return str(local)
        from huggingface_hub import snapshot_download
        return snapshot_download(
            repo_id=args.model,
            allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model"],
            local_files_only=args.local_files_only,
        )

    def ensure_model():
        if resolved_model_path["v"]:
            return None
        try:
            model_path = resolve_model_path()
            load_model(model_path)
            resolved_model_path["v"] = model_path
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
                r = transcribe(ap, model=resolved_model_path["v"], verbose=False, return_timestamps=False, return_chunks=True)
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
        guard FileManager.default.isExecutableFile(atPath: venvPython.path),
              let installedBridge = try? String(contentsOf: bridgeScript, encoding: .utf8) else {
            return false
        }
        return installedBridge == bridgeScriptContent
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

        // Step 3: Install the tested mlx-qwen3-asr version
        await MainActor.run { progress("Installing mlx-qwen3-asr (this may take a minute)…") }
        _ = await runProcess(venvPython.path, args: ["-m", "pip", "install", "--upgrade", "pip", "--quiet"])
        let installResult = await runProcess(venvPython.path, args: [
            "-m", "pip", "install", "mlx-qwen3-asr==\(mlxQwen3ASRVersion)", "--quiet"
        ])
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

        // Step 5: Download the model while setup is explicitly online.
        await MainActor.run { progress("Downloading Qwen3-ASR-1.7B for offline use…") }
        let downloadScript = """
        import sys
        from huggingface_hub import snapshot_download
        snapshot_download(
            repo_id=sys.argv[1],
            allow_patterns=["*.json", "*.safetensors", "*.txt", "*.model"],
        )
        """
        let downloadResult = await runProcess(venvPython.path, args: [
            "-c", downloadScript, SettingsStore.defaultModelId
        ])
        if !downloadResult.success {
            await MainActor.run { progress("Error downloading model: \(downloadResult.stderr)") }
            return false
        }

        // Step 6: Write bridge script from embedded content
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
