import AgentMonitorKit
import Foundation

enum HookInstallError: LocalizedError {
    case configMissing(String)
    case invalidJSON(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .configMissing(let path):
            return "File konfigurasi tidak ditemukan: \(path)"
        case .invalidJSON(let message):
            return "JSON tidak valid: \(message)"
        case .writeFailed(let message):
            return "Gagal menulis file: \(message)"
        }
    }
}

@MainActor
final class HookInstallerService: ObservableObject {
    static let shared = HookInstallerService()

    @Published private(set) var installed: [String: Bool] = [:]

    private let paths = MyNotchPaths()
    private let fm = FileManager.default

    private init() {
        refresh()
    }

    func refresh() {
        var next: [String: Bool] = [:]
        for def in AgentMonitorManager.shared.registry.definitions {
            guard let hooks = def.hooks else { continue }
            let configURL = expandedURL(hooks.config)
            guard let data = try? Data(contentsOf: configURL),
                  let json = try? JSONDecoder().decode(JSONValue.self, from: data)
            else {
                next[def.id] = false
                continue
            }
            next[def.id] = HookConfigMerger.isInstalled(in: json, events: hooks.events)
        }
        installed = next
    }

    func install(_ def: AgentDefinition) throws {
        guard let hooks = def.hooks else { return }
        do {
            try installReporterScript()
        } catch {
            throw HookInstallError.writeFailed(error.localizedDescription)
        }

        let configURL = expandedURL(hooks.config)
        let original = try readAndBackupConfig(at: configURL)
        let updated = HookConfigMerger.installing(
            into: original,
            agentID: def.id,
            events: hooks.events,
            reporterPath: paths.reporter.path
        )
        try validateAndWrite(updated, to: configURL)
        refresh()
    }

    func uninstall(_ def: AgentDefinition) throws {
        guard let hooks = def.hooks else { return }
        let configURL = expandedURL(hooks.config)
        let original = try readAndBackupConfig(at: configURL)
        let updated = HookConfigMerger.uninstalling(from: original)
        try validateAndWrite(updated, to: configURL)
        refresh()
    }

    private func installReporterScript() throws {
        for dir in [paths.root, paths.bin] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }

        let data = try Data(contentsOf: NotchReportScript.url)
        try data.write(to: paths.reporter, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.reporter.path)
    }

    private func readAndBackupConfig(at url: URL) throws -> JSONValue {
        guard fm.fileExists(atPath: url.path) else {
            throw HookInstallError.configMissing(url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HookInstallError.writeFailed(error.localizedDescription)
        }

        let decoded: JSONValue
        do {
            decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw HookInstallError.invalidJSON(error.localizedDescription)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = URL(fileURLWithPath: "\(url.path).mynotch-backup-\(stamp)")
        do {
            try data.write(to: backupURL, options: .atomic)
        } catch {
            throw HookInstallError.writeFailed(error.localizedDescription)
        }

        return decoded
    }

    private func validateAndWrite(_ value: JSONValue, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let encoded: Data
        do {
            encoded = try encoder.encode(value) + Data("\n".utf8)
            _ = try JSONDecoder().decode(JSONValue.self, from: encoded)
        } catch {
            throw HookInstallError.invalidJSON(error.localizedDescription)
        }

        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            throw HookInstallError.writeFailed(error.localizedDescription)
        }
    }

    private func expandedURL(_ rawPath: String) -> URL {
        let expanded = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}
