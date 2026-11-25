import Foundation

public struct MatchRule: Sendable, Codable, Equatable {
    public let executable: [String]
    public let argvContains: [String]

    public init(executable: [String], argvContains: [String]) {
        self.executable = executable
        self.argvContains = argvContains
    }
}

public struct HookSpec: Sendable, Codable, Equatable {
    public let format: String
    public let config: String
    public let events: [String]

    public init(format: String, config: String, events: [String]) {
        self.format = format
        self.config = config
        self.events = events
    }
}

public struct AgentDefinition: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let match: MatchRule
    public let appBundleIDs: [String]
    public let hooks: HookSpec?

    public init(
        id: String,
        displayName: String,
        match: MatchRule,
        appBundleIDs: [String],
        hooks: HookSpec?
    ) {
        self.id = id
        self.displayName = displayName
        self.match = match
        self.appBundleIDs = appBundleIDs
        self.hooks = hooks
    }
}

public struct CustomAgentRule: Sendable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let executable: String

    public init(id: String, displayName: String, executable: String) {
        self.id = id
        self.displayName = displayName
        self.executable = executable
    }

    public var definition: AgentDefinition {
        AgentDefinition(
            id: id,
            displayName: displayName,
            match: MatchRule(executable: [executable], argvContains: []),
            appBundleIDs: [],
            hooks: nil
        )
    }
}

public enum RegistryLoadError: Error, Sendable {
    case missingBundledResource
}

public struct AgentRegistry: Sendable, Equatable {
    public let definitions: [AgentDefinition]

    public init(definitions: [AgentDefinition]) {
        self.definitions = definitions
    }

    public static func bundled() throws -> AgentRegistry {
        guard let url = Bundle.module.url(
            forResource: "agents",
            withExtension: "json",
            subdirectory: "Resources"
        ) else {
            throw RegistryLoadError.missingBundledResource
        }
        let data = try Data(contentsOf: url)
        let defs = try JSONDecoder().decode([AgentDefinition].self, from: data)
        return AgentRegistry(definitions: defs)
    }

    public func adding(_ custom: [CustomAgentRule]) -> AgentRegistry {
        let existingIDs = Set(definitions.map(\.id))
        let additions = custom
            .filter { !existingIDs.contains($0.id) }
            .map(\.definition)
        return AgentRegistry(definitions: definitions + additions)
    }

    public func definition(id: String) -> AgentDefinition? {
        definitions.first { $0.id == id }
    }
}
