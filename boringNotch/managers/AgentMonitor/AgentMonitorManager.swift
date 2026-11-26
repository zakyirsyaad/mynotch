import AgentMonitorKit
import AppKit
import Combine
import Defaults
import Foundation
import os

@MainActor
final class AgentMonitorManager: ObservableObject {
    static let shared = AgentMonitorManager()

    @Published private(set) var sessions: [AgentSession] = []
    private(set) var registry: AgentRegistry

    var notchContextProvider: (() -> (notchOpen: Bool, hiddenForFullscreen: Bool))?
    var onNotice: ((AgentNotice) -> Void)?

    private let logger = Logger(subsystem: bundleIdentifier, category: "AgentMonitor")
    private let resolver = HostAppResolver()
    private var state = AgentState()
    private var noticeQueue = NoticeQueue()
    private var isRunning = false
    private var watcher: InboxWatcher?
    private var scanTask: Task<Void, Never>?
    private var noticeDrainTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let baseRegistry = (try? AgentRegistry.bundled()) ?? AgentRegistry(definitions: [])
        self.registry = baseRegistry.adding(Defaults[.agentCustomRules])
        observeDefaults()
    }

    func start() {
        guard Defaults[.agentMonitorEnabled] else { return }
        guard !isRunning else { return }
        isRunning = true

        let watcher = InboxWatcher { [weak self] events in
            self?.handleInboxEvents(events)
        }
        self.watcher = watcher
        watcher.start()

        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.watcher?.drainNow()
                let scanned = await Task.detached(priority: .utility) {
                    ProcessScanner.snapshotAll()
                }.value
                guard !Task.isCancelled else { break }
                self?.applyScannedSnapshots(scanned)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func refreshNow() {
        guard isRunning else { return }
        watcher?.drainNow()
        Task { [weak self] in
            let scanned = await Task.detached(priority: .utility) {
                ProcessScanner.snapshotAll()
            }.value
            self?.applyScannedSnapshots(scanned)
        }
    }

    func stop() {
        isRunning = false
        watcher?.stop()
        watcher = nil
        scanTask?.cancel()
        scanTask = nil
        noticeDrainTask?.cancel()
        noticeDrainTask = nil
        noticeQueue = NoticeQueue()
        state = AgentState()
        sessions = []
    }

    func activateHost(of session: AgentSession) {
        if let app = resolver.hostApp(forAgentPID: session.pid) {
            app.activate(options: [.activateAllWindows])
            return
        }

        if let def = registry.definition(id: session.agentID) {
            for bundleID in def.appBundleIDs {
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    running.activate(options: [.activateAllWindows])
                    return
                }
            }
        }
    }

    func displayName(for agentID: String) -> String {
        registry.definition(id: agentID)?.displayName ?? agentID
    }

    private func observeDefaults() {
        Defaults.publisher(.agentMonitorEnabled)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.start()
                } else {
                    self.stop()
                    if BoringViewCoordinator.shared.currentView == .agents {
                        BoringViewCoordinator.shared.currentView = .home
                    }
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.agentCustomRules)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                let baseRegistry = (try? AgentRegistry.bundled()) ?? AgentRegistry(definitions: [])
                self.registry = baseRegistry.adding(change.newValue)
            }
            .store(in: &cancellables)
    }

    private func handleInboxEvents(_ events: [InboxEvent]) {
        guard isRunning else { return }

        var allChanges: [StatusChange] = []

        for inboxEvent in events {
            guard var agentEvent = ClaudeFormatAdapter.adapt(inboxEvent) else {
                continue
            }

            var resolvedPID = ProcessMatcher.resolveAgentPID(
                from: agentEvent.pid,
                agentID: agentEvent.agentID,
                lookup: ProcessScanner.snapshot,
                in: registry
            )
            if !ProcessScanner.isAlive(resolvedPID) {
                if let existingPID = state.sessions[agentEvent.sessionID]?.pid,
                   ProcessScanner.isAlive(existingPID)
                {
                    resolvedPID = existingPID
                } else if let matchingProcess = state.sessions.values.first(where: {
                    $0.agentID == agentEvent.agentID && ProcessScanner.isAlive($0.pid)
                }) {
                    resolvedPID = matchingProcess.pid
                }
            }
            if resolvedPID != agentEvent.pid {
                agentEvent = AgentEvent(
                    sessionID: agentEvent.sessionID,
                    agentID: agentEvent.agentID,
                    pid: resolvedPID,
                    cwdName: agentEvent.cwdName,
                    kind: agentEvent.kind,
                    at: agentEvent.at
                )
            }

            let result = state.reducing(agentEvent)
            state = result.state
            allChanges.append(contentsOf: result.changes)

            for change in result.changes {
                logger.debug("Agent \(change.session.agentID, privacy: .public) session \(change.session.id, privacy: .public) -> \(change.to.rawValue, privacy: .public)")
            }
        }

        sessions = state.sortedSessions

        for change in allChanges {
            let context = currentNoticeContext(forAgentPID: change.session.pid)
            let settings = currentNotifySettings()
            if let notice = NotificationPolicy.notice(
                for: change,
                displayName: displayName(for: change.session.agentID),
                settings: settings,
                context: context
            ) {
                noticeQueue = noticeQueue.enqueuing(notice)
            }
        }

        scheduleNoticeDrainIfNeeded()
    }

    private func applyScannedSnapshots(_ snapshots: [ProcessSnapshot]) {
        guard isRunning else { return }

        let previousPIDs = Set(state.sessions.values.map(\.pid))
        let matched = ProcessMatcher.scan(snapshots, in: registry)

        state = state
            .merging(scanned: matched, now: Date())
            .pruning(isAlive: ProcessScanner.isAlive)

        let currentPIDs = Set(state.sessions.values.map(\.pid))
        for vanishedPID in previousPIDs.subtracting(currentPIDs) {
            resolver.forget(pid: vanishedPID)
        }

        sessions = state.sortedSessions
    }

    private func currentNotifySettings() -> NotifySettings {
        NotifySettings(
            waiting: Defaults[.agentNotifyWaiting],
            error: Defaults[.agentNotifyError],
            done: Defaults[.agentNotifyDone]
        )
    }

    private func currentNoticeContext(forAgentPID pid: Int32) -> NoticeContext {
        let notchContext = notchContextProvider?() ?? (notchOpen: false, hiddenForFullscreen: false)
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let host = resolver.hostApp(forAgentPID: pid)?.bundleIdentifier
        return NoticeContext(
            frontmostBundleID: frontmost,
            hostBundleID: host,
            notchOpen: notchContext.notchOpen,
            hiddenForFullscreen: notchContext.hiddenForFullscreen
        )
    }

    private func scheduleNoticeDrainIfNeeded() {
        guard noticeDrainTask == nil, !noticeQueue.pending.isEmpty else { return }

        noticeDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.noticeDrainTask = nil }

            while !Task.isCancelled {
                let (nextNotice, remaining) = self.noticeQueue.dequeued()
                self.noticeQueue = remaining
                guard let notice = nextNotice else { break }

                let notchContext = self.notchContextProvider?() ?? (notchOpen: false, hiddenForFullscreen: false)
                if notchContext.notchOpen || notchContext.hiddenForFullscreen {
                    continue
                }

                self.onNotice?(notice)
                try? await Task.sleep(for: .seconds(notice.duration + 0.4))
            }
        }
    }
}
