import AgentMonitorKit
import Darwin
import Foundation

enum ProcessScanner {
    static func snapshotAll() -> [ProcessSnapshot] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        let capacity = Int(estimatedCount) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesWritten = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard bytesWritten > 0 else { return [] }

        let count = Int(bytesWritten) / MemoryLayout<pid_t>.stride
        let currentUID = getuid()

        var snapshots: [ProcessSnapshot] = []
        snapshots.reserveCapacity(count)

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0, let snap = snapshot(pid: pid, expectedUID: currentUID) else {
                continue
            }
            snapshots.append(snap)
        }
        return snapshots
    }

    static func snapshot(pid: Int32) -> ProcessSnapshot? {
        snapshot(pid: pid, expectedUID: getuid())
    }

    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func snapshot(pid: Int32, expectedUID: uid_t) -> ProcessSnapshot? {
        var bsdInfo = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &bsdInfo) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, infoSize)
        }
        guard result == infoSize, bsdInfo.pbi_uid == expectedUID else {
            return nil
        }

        let ppid = Int32(bsdInfo.pbi_ppid)
        let startedAt = Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec))

        if let (exePath, args) = readProcArgs(pid: pid) {
            let executable = URL(fileURLWithPath: exePath).lastPathComponent
            if !executable.isEmpty {
                return ProcessSnapshot(
                    pid: pid,
                    ppid: ppid,
                    executable: executable,
                    arguments: args,
                    startedAt: startedAt
                )
            }
        }

        let fallbackExe = readExecutablePath(pid: pid).map {
            URL(fileURLWithPath: $0).lastPathComponent
        } ?? withUnsafePointer(to: bsdInfo.pbi_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                String(cString: $0)
            }
        }

        guard !fallbackExe.isEmpty else { return nil }
        return ProcessSnapshot(
            pid: pid,
            ppid: ppid,
            executable: fallbackExe,
            arguments: [],
            startedAt: startedAt
        )
    }

    private static func readExecutablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func readProcArgs(pid: Int32) -> (executablePath: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        let data = Data(buffer.prefix(size))
        let argc = data.withUnsafeBytes { raw -> Int32 in
            raw.load(as: Int32.self)
        }
        guard argc >= 0 else { return nil }

        var cursor = MemoryLayout<Int32>.size
        guard let execPath = readCString(in: data, from: &cursor), !execPath.isEmpty else {
            return nil
        }

        while cursor < data.count && data[cursor] == 0 {
            cursor += 1
        }

        var args: [String] = []
        args.reserveCapacity(Int(min(argc, 64)))
        for _ in 0..<argc {
            guard cursor < data.count, let arg = readCString(in: data, from: &cursor) else {
                break
            }
            args.append(arg)
        }

        return (execPath, args)
    }

    private static func readCString(in data: Data, from cursor: inout Int) -> String? {
        guard cursor < data.count else { return nil }
        let slice = data[cursor...]
        guard let nulIndex = slice.firstIndex(of: 0) else {
            let text = String(decoding: slice, as: UTF8.self)
            cursor = data.count
            return text
        }
        let text = String(decoding: data[cursor..<nulIndex], as: UTF8.self)
        cursor = nulIndex + 1
        return text
    }
}
