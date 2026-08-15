import Testing
@testable import MacLocalASR

struct SetupRunnerTests {
    @Test func embeddedBridgeOnlyTranscribesSwiftCapturedAudio() {
        let bridge = SetupRunner.bridgeScriptContent

        #expect(bridge.contains(#"elif t == "transcribe":"#))
        #expect(bridge.contains("local_files_only=args.local_files_only"))
        #expect(bridge.contains(#"model=resolved_model_path["v"]"#))
        #expect(!bridge.contains("sounddevice"))
        #expect(!bridge.contains("record_and_transcribe"))
    }

    @Test func dependencyVersionIsPinned() {
        #expect(SetupRunner.mlxQwen3ASRVersion == "0.3.5")
    }
}
