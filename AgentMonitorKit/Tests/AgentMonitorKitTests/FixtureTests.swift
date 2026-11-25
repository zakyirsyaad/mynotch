import Foundation
import Testing
@testable import AgentMonitorKit

func fixture(_ agent: String, _ event: String) throws -> InboxEvent {
    guard let url = Bundle.module.url(
        forResource: event,
        withExtension: "json",
        subdirectory: "Fixtures/\(agent)"
    ) else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try InboxEvent.decode(Data(contentsOf: url))
}

func fixtureFiles() -> [URL] {
    guard let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
        return []
    }
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
        return []
    }
    var urls: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "json" {
        urls.append(url)
    }
    return urls.sorted { $0.path < $1.path }
}

@Test(arguments: fixtureFiles())
func fixtureDecodes(url: URL) throws {
    let event = try InboxEvent.decode(Data(contentsOf: url))
    #expect(event.payload["session_id"]?.stringValue?.isEmpty == false)
}

@Test func fixtureFilesAreNonEmpty() {
    #expect(fixtureFiles().count == 15)
}
