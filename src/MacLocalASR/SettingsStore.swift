import Foundation

struct SettingsStore {
    static let modelPathKey = "asrModelId"
    static let defaultModelId = "Qwen/Qwen3-ASR-1.7B"

    let venvPythonPath: String
    let bridgeScriptPath: String
    let modelId: String

    static func current(defaults: UserDefaults = .standard) throws -> SettingsStore {
        let venvPythonPath = SetupRunner.venvPython.path
        let bridgeScriptPath = SetupRunner.bridgeScript.path

        guard FileManager.default.isExecutableFile(atPath: venvPythonPath) else {
            throw SettingsError.venvNotReady
        }
        guard FileManager.default.fileExists(atPath: bridgeScriptPath) else {
            throw SettingsError.bridgeNotFound
        }

        let modelId = defaults.string(forKey: modelPathKey) ?? defaultModelId
        return SettingsStore(venvPythonPath: venvPythonPath, bridgeScriptPath: bridgeScriptPath, modelId: modelId)
    }

    static func isConfigured() -> Bool {
        SetupRunner.isSetupComplete()
    }
}

enum SettingsError: LocalizedError {
    case venvNotReady
    case bridgeNotFound

    var errorDescription: String? {
        switch self {
        case .venvNotReady:
            LocalizableStrings.venvNotReady
        case .bridgeNotFound:
            LocalizableStrings.bridgeNotFound
        }
    }
}