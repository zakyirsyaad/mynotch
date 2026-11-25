import AgentMonitorKit
import AppKit
import Darwin
import Foundation

@MainActor
final class AgentIconProvider: ObservableObject {
    static let shared = AgentIconProvider()

    @Published private(set) var revision: Int = 0

    private let paths = MyNotchPaths()
    private var cache: [String: NSImage] = [:]
    private var missingCache: Set<String> = []
    private let watchQueue = DispatchQueue(label: "\(bundleIdentifier).agent-icons", qos: .utility)
    private var watchSource: DispatchSourceFileSystemObject?
    private var watchFD: Int32 = -1

    private init() {
        startWatchingIconsDirectory()
    }

    deinit {
        if let source = watchSource {
            source.cancel()
        } else if watchFD >= 0 {
            close(watchFD)
        }
    }

    func icon(for agentID: String) -> NSImage? {
        if let cached = cache[agentID] {
            return cached
        }
        if missingCache.contains(agentID) {
            return nil
        }

        let customURL = paths.icons.appendingPathComponent("\(agentID).png", isDirectory: false)
        if let customImage = NSImage(contentsOf: customURL) {
            cache[agentID] = customImage
            return customImage
        }

        if let def = AgentMonitorManager.shared.registry.definition(id: agentID) {
            for bundleID in def.appBundleIDs {
                if let appIcon = AppIconAsNSImage(for: bundleID) {
                    cache[agentID] = appIcon
                    return appIcon
                }
            }
        }

        missingCache.insert(agentID)
        return nil
    }

    func setCustomIcon(_ source: URL, for agentID: String) throws {
        let fm = FileManager.default
        for dir in [paths.root, paths.icons] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }

        guard let image = NSImage(contentsOf: source),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let destination = paths.icons.appendingPathComponent("\(agentID).png", isDirectory: false)
        try pngData.write(to: destination, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        invalidate()
        startWatchingIconsDirectory()
    }

    func invalidate() {
        cache.removeAll()
        missingCache.removeAll()
        revision += 1
    }

    private func startWatchingIconsDirectory() {
        let iconsPath = paths.icons.path
        guard FileManager.default.fileExists(atPath: iconsPath), watchSource == nil else {
            return
        }

        let fd = open(iconsPath, O_EVTONLY)
        guard fd >= 0 else { return }
        watchFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: watchQueue
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.invalidate()
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        watchSource = source
        source.resume()
    }
}
