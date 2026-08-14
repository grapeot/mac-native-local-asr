import Foundation

enum LocalizableStrings {
    static var appName: String { tr("Mac Local ASR", "Mac 本地听写") }
    static var loadingModel: String { tr("Loading model…", "模型加载中…") }
    static var ready: String { tr("Ready", "就绪") }
    static var recording: String { tr("Recording…", "录音中…") }
    static var transcribing: String { tr("Transcribing…", "转写中…") }
    static var errorPrefix: String { tr("Error:", "错误：") }
    static var lastPrefix: String { tr("Last:", "上次：") }
    static var settings: String { tr("Settings…", "设置…") }
    static var showWindow: String { tr("Show Window", "显示窗口") }
    static var quit: String { tr("Quit", "退出") }
    static var copiedToClipboard: String { tr("Copied to clipboard", "已复制到剪贴板") }
    static var microphoneAccessRequired: String { tr("Microphone access required", "需要麦克风权限") }
    static var hotkey: String { tr("Hotkey", "快捷键") }
    static var inputDevice: String { tr("Input Device", "输入设备") }
    static var systemDefault: String { tr("System Default", "系统默认") }
    static var bridgePath: String { tr("ASR Bridge Path", "ASR 引擎路径") }
    static var modelPath: String { tr("Model Path", "模型路径") }
    static var status: String { tr("Status", "状态") }
    static var modelLoaded: String { tr("Model loaded", "模型已加载") }
    static var close: String { tr("Close", "关闭") }
    static var browse: String { tr("Browse…", "浏览…") }
    static var notConfigured: String { tr("Not configured", "尚未配置") }
    static var setup: String { tr("Setup…", "配置…") }
    static var venvNotReady: String { tr("ASR not configured. Click Setup to install.", "ASR 未配置，点击配置以安装。") }
    static var bridgeNotConfigured: String { tr("ASR bridge not configured", "尚未配置 ASR 引擎") }
    static var bridgeNotFound: String { tr("ASR bridge was not found", "找不到 ASR 引擎") }
    static var modelNotConfigured: String { tr("Model path not set", "尚未设置模型路径") }
    static var modelNotFound: String { tr("Model directory was not found", "找不到模型目录") }
    static var engineNotReady: String { tr("ASR engine is not ready", "ASR 引擎尚未就绪") }
    static var engineCrashed: String { tr("ASR engine exited", "ASR 引擎已退出") }
    static var engineRestartFailed: String { tr("ASR engine failed to restart", "ASR 引擎重启失败") }
    static var transcriptionTimedOut: String { tr("Transcription timed out", "转写超时") }
    static var requestInProgress: String { tr("ASR request already in progress", "ASR 请求正在进行中") }
    static var unexpectedBridgeResponse: String { tr("Unexpected ASR response", "ASR 返回了意外响应") }
    static var modelLoadFailed: String { tr("Model failed to load", "模型加载失败") }
    static var unknownError: String { tr("Unknown error", "未知错误") }
    static var audioDeviceUnavailable: String { tr("Audio input device changed", "音频输入设备已更改") }
    static var noInputDevice: String { tr("No audio input device", "没有音频输入设备") }
    static var audioConversionFailed: String { tr("Audio conversion failed", "音频转换失败") }
    static var notRecording: String { tr("Recording is not active", "当前未在录音") }
    static var noAudioCaptured: String { tr("No audio was captured", "未录到音频") }
    static var emptyTranscript: String { tr("No speech was recognized", "未识别到语音") }
    static var record: String { tr("Record", "录音") }
    static var stop: String { tr("Stop", "停止") }
    static var transcriptPlaceholder: String { tr("Your transcription will appear here", "转写结果将显示在这里") }

    private static func tr(_ en: String, _ zh: String) -> String {
        let preferredLanguages = Locale.preferredLanguages
        for lang in preferredLanguages {
            if lang.hasPrefix("zh") {
                return zh
            }
        }
        return en
    }
}