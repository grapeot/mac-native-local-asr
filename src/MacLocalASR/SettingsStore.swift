import Foundation

struct SettingsStore {
    static let modelPathKey = "asrModelId"
    static let venvPythonKey = "asrVenvPython"

    static let defaultModelId = "Qwen/Qwen3-ASR-1.7B"

    // Fixed locations — user never touches these
    static let installDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".maclocalasr")
    static let venvPython = installDir.appendingPathComponent(".venv/bin/python")
    static let bridgeScript = installDir.appendingPathComponent("start_asr_bridge.py")

    let venvPythonPath: String
    let bridgeScriptPath: String
    let modelId: String

    static func current(defaults: UserDefaults = .standard) throws -> SettingsStore {
        // Bridge script is always at our install dir — copy it if missing
        let bridgeURL = bridgeScript
        if !FileManager.default.fileExists(atPath: bridgeURL.path) {
            try installBridgeScript(to: bridgeURL)
        }

        // Venv python must exist (created by setup)
        let venvPythonPath = venvPython.path
        guard FileManager.default.isExecutableFile(atPath: venvPythonPath) else {
            throw SettingsError.venvNotReady
        }

        let modelId = defaults.string(forKey: modelPathKey) ?? defaultModelId

        return SettingsStore(
            venvPythonPath: venvPythonPath,
            bridgeScriptPath: bridgeURL.path,
            modelId: modelId
        )
    }

    static func isConfigured() -> Bool {
        FileManager.default.isExecutableFile(atPath: venvPython.path)
            && FileManager.default.fileExists(atPath: bridgeScript.path)
    }

    private static func installBridgeScript(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Find the script bundled in the app
        let candidates = [
            // Next to the executable
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/start_asr_bridge.py"),
            // Repo path during development
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts/start_asr_bridge.py"),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.copyItem(at: candidate, to: url)
                return
            }
        }
        throw SettingsError.bridgeScriptNotFound
    }
}

enum SettingsError: LocalizedError {
    case venvNotReady
    case bridgeScriptNotFound

    var errorDescription: String? {
        switch self {
        case .venvNotReady:
            LocalizableStrings.venvNotReady
        case .bridgeScriptNotFound:
            LocalizableStrings.bridgeNotFound
        }
    }
}