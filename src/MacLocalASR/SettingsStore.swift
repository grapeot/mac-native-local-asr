import Foundation

struct SettingsStore {
    static let bridgePathKey = "asrBridgePath"
    static let modelPathKey = "asrModelPath"

    let bridgePath: String
    let modelPath: String

    static func current(defaults: UserDefaults = .standard) throws -> SettingsStore {
        let bridgePath = defaults.string(forKey: bridgePathKey) ?? ""
        let modelPath = defaults.string(forKey: modelPathKey) ?? ""

        guard !bridgePath.isEmpty else { throw SettingsError.bridgeNotConfigured }
        guard FileManager.default.fileExists(atPath: bridgePath) else {
            throw SettingsError.bridgeNotFound
        }
        guard !modelPath.isEmpty else { throw SettingsError.modelNotConfigured }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SettingsError.modelNotFound
        }

        return SettingsStore(bridgePath: bridgePath, modelPath: modelPath)
    }
}

enum SettingsError: LocalizedError {
    case bridgeNotConfigured
    case bridgeNotFound
    case modelNotConfigured
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .bridgeNotConfigured:
            LocalizableStrings.bridgeNotConfigured
        case .bridgeNotFound:
            LocalizableStrings.bridgeNotFound
        case .modelNotConfigured:
            LocalizableStrings.modelNotConfigured
        case .modelNotFound:
            LocalizableStrings.modelNotFound
        }
    }
}
