import AppKit
import Foundation

/// Minimal HTTP control server on localhost:17843.
/// Lets external tools (curl) query state and trigger actions for automated testing.
/// Socket I/O runs on a background thread; MainActor calls are dispatched via DispatchQueue.
final class ControlServer: @unchecked Sendable {
    static let port = 17843

    private var serverSocket: Int32 = -1
    private var thread: Thread?
    private weak var appState: AppState?

    func start(appState: AppState) {
        self.appState = appState

        serverSocket = socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard serverSocket >= 0 else { return }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(ControlServer.port).bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(serverSocket, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(serverSocket); return }
        guard listen(serverSocket, 5) == 0 else { close(serverSocket); return }

        let t = Thread { [weak self] in
            self?.acceptLoop()
        }
        t.name = "ControlServer"
        t.start()
        thread = t
    }

    func stop() {
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
    }

    private func acceptLoop() {
        while serverSocket >= 0 {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverSocket, sa, &len)
                }
            }
            if client < 0 { break }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(client, &buffer, buffer.count)
            let request = n > 0 ? String(bytes: buffer.prefix(n), encoding: .utf8) ?? "" : ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

            let response = handleRequestSync(path)

            let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(response.count)\r\nConnection: close\r\n\r\n\(response)"
            let data = httpResponse.data(using: .utf8) ?? Data()
            _ = data.withUnsafeBytes { buf -> Int in
                send(client, buf.baseAddress, data.count, 0)
            }
            close(client)
        }
    }

    private func handleRequestSync(_ path: String) -> String {
        switch path {
        case "/status":
            var result = "{}"
            let sem = DispatchSemaphore(value: 0)
            let state = self.appState
            DispatchQueue.main.sync {
                if let state {
                    var phase = "unknown"
                    switch state.phase {
                    case .loading: phase = "loading"
                    case .idle: phase = "idle"
                    case .recording: phase = "recording"
                    case .processing: phase = "processing"
                    case .error(let msg): phase = "error:\(msg)"
                    }
                    let t = state.lastTranscript.replacingOccurrences(of: "\"", with: "\\\"")
                    let sp = state.setupProgress.replacingOccurrences(of: "\"", with: "\\\"")
                    result = "{\"phase\":\"\(phase)\",\"configured\":\(state.isConfigured),\"ready\":\(state.isBridgeReady),\"lastTranscript\":\"\(t)\",\"setupProgress\":\"\(sp)\"}"
                }
                sem.signal()
            }
            sem.wait()
            return result

        case "/setup":
            let state = self.appState
            DispatchQueue.main.async {
                Task { @MainActor in
                    await state?.runSetup()
                }
            }
            return "{\"action\":\"setup_started\"}"

        case "/toggle":
            let state = self.appState
            DispatchQueue.main.async {
                state?.toggleRecording()
            }
            return "{\"action\":\"toggle\"}"

        case "/settings":
            DispatchQueue.main.async {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.showSettings()
                }
            }
            return "{\"action\":\"settings_opened\"}"

        default:
            return "{\"error\":\"unknown\",\"paths\":[\"/status\",\"/setup\",\"/toggle\",\"/settings\"]}"
        }
    }

    @MainActor
    private func buildStatusJSON() -> String {
        guard let appState else { return "{}" }
        let phase: String
        switch appState.phase {
        case .loading: phase = "loading"
        case .idle: phase = "idle"
        case .recording: phase = "recording"
        case .processing: phase = "processing"
        case .error(let msg): phase = "error:\(msg)"
        }
        return "{\"phase\":\"\(phase)\",\"configured\":\(appState.isConfigured),\"ready\":\(appState.isBridgeReady),\"lastTranscript\":\"\(appState.lastTranscript.replacingOccurrences(of: "\"", with: "\\\""))\",\"setupProgress\":\"\(appState.setupProgress.replacingOccurrences(of: "\"", with: "\\\""))\"}"
    }
}