import Foundation

public struct MyNotchPaths: Sendable, Equatable {
    public let root: URL
    public let inbox: URL
    public let bin: URL
    public let icons: URL
    public let reporter: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let root = home.appendingPathComponent(".mynotch", isDirectory: true)
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let icons = root.appendingPathComponent("icons", isDirectory: true)
        let reporter = bin.appendingPathComponent("notch-report", isDirectory: false)

        self.root = root
        self.inbox = inbox
        self.bin = bin
        self.icons = icons
        self.reporter = reporter
    }
}

public enum NotchReportScript {
    public static var url: URL {
        Bundle.module.url(forResource: "notch-report", withExtension: "sh", subdirectory: "Resources")!
    }
}
