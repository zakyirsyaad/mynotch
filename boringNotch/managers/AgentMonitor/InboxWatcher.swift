import AgentMonitorKit
import Darwin
import Foundation
import os

final class InboxWatcher {
    private let directory: URL
    private let maxAge: TimeInterval
    private let onEvents: @MainActor ([InboxEvent]) -> Void
    private let queue = DispatchQueue(label: "\(bundleIdentifier).agent-inbox", qos: .utility)
    private let logger = Logger(subsystem: bundleIdentifier, category: "AgentMonitor")
    private let maxFileSize: off_t = 300_000

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isRunning = false

    init(
        directory: URL = MyNotchPaths().inbox,
        maxAge: TimeInterval = 600,
        onEvents: @escaping @MainActor ([InboxEvent]) -> Void
    ) {
        self.directory = directory
        self.maxAge = maxAge
        self.onEvents = onEvents
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.ensurePrivateDirectories()
            self.drainInbox()
            self.installWatcher()
        }
    }

    func drainNow() {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.drainInbox()
        }
    }

    func stop() {
        queue.sync {
            isRunning = false
            teardownWatcher()
        }
    }

    private func ensurePrivateDirectories() {
        let fm = FileManager.default
        let root = directory.deletingLastPathComponent()
        for url in [root, directory] {
            if !fm.fileExists(atPath: url.path) {
                do {
                    try fm.createDirectory(
                        at: url,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                } catch {
                    logger.error("Failed to create inbox directory \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    private func installWatcher() {
        teardownWatcher()
        guard isRunning else { return }

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Failed to open inbox directory for watching: \(self.directory.path, privacy: .public)")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.ensurePrivateDirectories()
                self.drainInbox()
                self.installWatcher()
            } else {
                self.drainInbox()
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        self.source = source
        source.resume()
    }

    private func teardownWatcher() {
        if let source {
            self.source = nil
            self.fileDescriptor = -1
            source.cancel()
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func drainInbox() {
        let fm = FileManager.default
        let currentUID = getuid()
        let now = Date()

        guard let entries = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return
        }

        var decodedEvents: [InboxEvent] = []

        for name in entries {
            if name.hasPrefix(".tmp-") || !name.hasSuffix(".json") {
                continue
            }

            let fileURL = directory.appendingPathComponent(name, isDirectory: false)
            var fileStat = stat()
            guard lstat(fileURL.path, &fileStat) == 0 else {
                continue
            }

            let isRegularFile = (fileStat.st_mode & S_IFMT) == S_IFREG
            guard isRegularFile, fileStat.st_uid == currentUID else {
                logger.warning("Skipping non-regular or foreign inbox file: \(name, privacy: .public)")
                continue
            }

            defer {
                try? fm.removeItem(at: fileURL)
            }

            guard fileStat.st_size >= 0, fileStat.st_size <= maxFileSize else {
                logger.warning("Dropping oversized inbox file: \(name, privacy: .public)")
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let event = try InboxEvent.decode(data)
                if now.timeIntervalSince(event.timestamp) > maxAge {
                    logger.debug("Dropping stale inbox event \(event.event, privacy: .public) from \(event.source, privacy: .public)")
                    continue
                }
                decodedEvents.append(event)
            } catch {
                logger.error("Failed to decode inbox file \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        guard !decodedEvents.isEmpty else { return }
        decodedEvents.sort { $0.timestamp < $1.timestamp }

        let callback = onEvents
        Task { @MainActor in
            callback(decodedEvents)
        }
    }
}
