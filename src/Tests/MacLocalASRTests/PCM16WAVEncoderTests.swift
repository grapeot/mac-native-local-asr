import Foundation
import Testing
@testable import MacLocalASR

struct PCM16WAVEncoderTests {
    @Test func writesCanonicalMono24kHzHeaderAndPayload() {
        let pcm = Data([0x01, 0x02, 0x03, 0x04])
        let wav = PCM16WAVEncoder.makeWAV(from: pcm, sampleRate: 24_000, channels: 1)

        #expect(wav.count == 48)
        #expect(wav.ascii(at: 0, count: 4) == "RIFF")
        #expect(wav.uint32LE(at: 4) == 40)
        #expect(wav.ascii(at: 8, count: 4) == "WAVE")
        #expect(wav.ascii(at: 12, count: 4) == "fmt ")
        #expect(wav.uint32LE(at: 16) == 16)
        #expect(wav.uint16LE(at: 20) == 1)
        #expect(wav.uint16LE(at: 22) == 1)
        #expect(wav.uint32LE(at: 24) == 24_000)
        #expect(wav.uint32LE(at: 28) == 48_000)
        #expect(wav.uint16LE(at: 32) == 2)
        #expect(wav.uint16LE(at: 34) == 16)
        #expect(wav.ascii(at: 36, count: 4) == "data")
        #expect(wav.uint32LE(at: 40) == 4)
        #expect(wav.suffix(4) == pcm)
    }
}

private extension Data {
    func ascii(at offset: Int, count: Int) -> String {
        String(decoding: self[offset..<(offset + count)], as: UTF8.self)
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
