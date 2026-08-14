import Testing
@testable import MacLocalASR

struct SetupRunnerTests {
    @Test func embeddedBridgeOnlyTranscribesSwiftCapturedAudio() {
        let bridge = SetupRunner.bridgeScriptContent

        #expect(bridge.contains(#"elif t == "transcribe":"#))
        #expect(!bridge.contains("sounddevice"))
        #expect(!bridge.contains("record_and_transcribe"))
    }
}
