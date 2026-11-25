import AgentMonitorKit
import AppKit
import Foundation

@MainActor
final class HostAppResolver {
    private var cache: [Int32: NSRunningApplication] = [:]

    func hostApp(forAgentPID pid: Int32) -> NSRunningApplication? {
        if let cached = cache[pid], !cached.isTerminated {
            return cached
        }
        cache.removeValue(forKey: pid)

        let chain = ProcessMatcher.ancestors(of: pid, lookup: ProcessScanner.snapshot)
        for snap in chain {
            if let app = NSRunningApplication(processIdentifier: snap.pid),
               app.bundleIdentifier != nil
            {
                cache[pid] = app
                return app
            }
        }
        return nil
    }

    func forget(pid: Int32) {
        cache.removeValue(forKey: pid)
    }
}
