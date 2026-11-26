import AgentMonitorKit
import Darwin
import Foundation
import os

enum DiscordIPCConnectionState: Equatable, Sendable {
    case disabled
    case waitingForDiscord
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disabled:
            return "Nonaktif"
        case .waitingForDiscord:
            return "Menunggu Discord…"
        case .connected:
            return "Terhubung"
        case .error(let message):
            return message
        }
    }
}

final class DiscordIPCClient {
    var onConnectionStateChanged: (@MainActor (DiscordIPCConnectionState) -> Void)?
    var onMessage: (@MainActor (JSONValue) -> Void)?

    private let queue = DispatchQueue(label: "\(bundleIdentifier).discord-ipc", qos: .utility)
    private let logger = Logger(subsystem: bundleIdentifier, category: "DiscordIPC")

    private var clientID: String = ""
    private var isRunning = false
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var reconnectWorkItem: DispatchWorkItem?
    private var readBuffer = Data()
    private var backoffSeconds: TimeInterval = 2

    deinit {
        stop()
    }

    func start(clientID: String) {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        queue.async { [weak self] in
            guard let self else { return }
            self.clientID = trimmed
            guard !trimmed.isEmpty else {
                self.stopLocked(state: .disabled)
                return
            }
            if self.isRunning {
                return
            }
            self.isRunning = true
            self.backoffSeconds = 2
            self.connectLocked()
        }
    }

    func updateClientID(_ clientID: String) {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        queue.async { [weak self] in
            guard let self else { return }
            if self.clientID == trimmed && self.isRunning {
                return
            }
            self.stopLocked(state: trimmed.isEmpty ? .disabled : .waitingForDiscord)
            guard !trimmed.isEmpty else { return }
            self.clientID = trimmed
            self.isRunning = true
            self.backoffSeconds = 2
            self.connectLocked()
        }
    }

    func stop() {
        queue.sync {
            stopLocked(state: .disabled)
        }
    }

    func sendJSON(_ value: JSONValue, opcode: DiscordIPCOpcode = .frame) {
        queue.async { [weak self] in
            guard let self, self.socketFD >= 0 else { return }
            do {
                let data = try DiscordIPCFramer.encodeJSON(value, opcode: opcode)
                self.writeAll(data, to: self.socketFD)
            } catch {
                self.logger.error("Failed to encode Discord IPC frame: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func stopLocked(state: DiscordIPCConnectionState) {
        isRunning = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        teardownSocketLocked()
        emitState(state)
    }

    private func connectLocked() {
        guard isRunning, !clientID.isEmpty else { return }
        teardownSocketLocked()

        guard let socketPath = findDiscordSocketPath(),
              let fd = openUnixSocket(at: socketPath)
        else {
            emitState(.waitingForDiscord)
            scheduleReconnectLocked()
            return
        }

        socketFD = fd
        readBuffer.removeAll(keepingCapacity: true)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadableLocked()
        }
        source.setCancelHandler {
            close(fd)
        }
        readSource = source
        source.resume()

        do {
            let handshake = try DiscordIPCFramer.encodeJSON(
                DiscordIPCFramer.handshakePayload(clientID: clientID),
                opcode: .handshake
            )
            if !writeAll(handshake, to: fd) {
                handleDisconnectLocked(errorMessage: nil)
            }
        } catch {
            handleDisconnectLocked(errorMessage: error.localizedDescription)
        }
    }

    private func handleReadableLocked() {
        guard socketFD >= 0 else { return }
        var chunk = [UInt8](repeating: 0, count: 16_384)
        let bytesRead = Darwin.read(socketFD, &chunk, chunk.count)

        if bytesRead > 0 {
            readBuffer.append(contentsOf: chunk[0..<bytesRead])
            drainFramesLocked()
        } else if bytesRead == 0 {
            handleDisconnectLocked(errorMessage: nil)
        } else if errno != EAGAIN && errno != EWOULDBLOCK {
            handleDisconnectLocked(errorMessage: nil)
        }
    }

    private func drainFramesLocked() {
        while true {
            let frame: DiscordIPCFrame?
            do {
                frame = try DiscordIPCFramer.decodeNextFrame(from: &readBuffer)
            } catch {
                logger.error("Discord IPC framing error: \(String(describing: error), privacy: .public)")
                handleDisconnectLocked(errorMessage: "Frame IPC tidak valid")
                return
            }

            guard let frame else { return }

            switch frame.opcode {
            case .frame:
                if let json = try? JSONDecoder().decode(JSONValue.self, from: frame.payload) {
                    if json["evt"]?.stringValue == "READY" {
                        backoffSeconds = 2
                        emitState(.connected)
                    }
                    let callback = onMessage
                    Task { @MainActor in
                        callback?(json)
                    }
                }
            case .ping:
                let pong = DiscordIPCFramer.encode(opcode: .pong, payload: frame.payload)
                _ = writeAll(pong, to: socketFD)
            case .close:
                handleDisconnectLocked(errorMessage: nil)
                return
            case .handshake, .pong:
                break
            }
        }
    }

    private func handleDisconnectLocked(errorMessage: String?) {
        teardownSocketLocked()
        guard isRunning else { return }
        emitState(errorMessage.map { .error($0) } ?? .waitingForDiscord)
        scheduleReconnectLocked()
    }

    private func scheduleReconnectLocked() {
        reconnectWorkItem?.cancel()
        let delay = backoffSeconds
        backoffSeconds = min(30, backoffSeconds * 2)

        let item = DispatchWorkItem { [weak self] in
            self?.connectLocked()
        }
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func teardownSocketLocked() {
        if let source = readSource {
            readSource = nil
            socketFD = -1
            source.cancel()
        } else if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        readBuffer.removeAll(keepingCapacity: false)
    }

    private func emitState(_ state: DiscordIPCConnectionState) {
        let callback = onConnectionStateChanged
        Task { @MainActor in
            callback?(state)
        }
    }

    private func findDiscordSocketPath() -> String? {
        var candidates: [String] = []
        let tempDir = NSTemporaryDirectory()
        if !tempDir.isEmpty {
            candidates.append(tempDir)
        }
        if let envTmp = ProcessInfo.processInfo.environment["TMPDIR"], !envTmp.isEmpty {
            candidates.append(envTmp)
        }
        candidates.append("/tmp")

        let currentUID = getuid()
        for base in candidates {
            let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
            for index in 0..<10 {
                let path = "\(trimmedBase)/discord-ipc-\(index)"
                var st = stat()
                if lstat(path, &st) == 0,
                   (st.st_mode & S_IFMT) == S_IFSOCK,
                   st.st_uid == currentUID
                {
                    return path
                }
            }
        }
        return nil
    }

    private func openUnixSocket(at path: String) -> Int32? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            close(fd)
            return nil
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    @discardableResult
    private func writeAll(_ data: Data, to fd: Int32) -> Bool {
        guard fd >= 0 else { return false }
        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return true }
            var totalWritten = 0
            while totalWritten < data.count {
                let written = Darwin.write(fd, base.advanced(by: totalWritten), data.count - totalWritten)
                if written > 0 {
                    totalWritten += written
                } else if errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}
