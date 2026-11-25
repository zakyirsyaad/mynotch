import AgentMonitorKit
import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct AgentsSettingsView: View {
    @Default(.agentCustomRules) private var customRules

    @ObservedObject private var manager = AgentMonitorManager.shared
    @ObservedObject private var installer = HookInstallerService.shared
    @ObservedObject private var iconProvider = AgentIconProvider.shared

    @State private var hookErrors: [String: String] = [:]
    @State private var iconError: String?
    @State private var showingProcessPicker = false

    private var hookCapableDefinitions: [AgentDefinition] {
        manager.registry.definitions.filter { $0.hooks != nil }
    }

    private var allDefinitions: [AgentDefinition] {
        manager.registry.definitions
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .agentMonitorEnabled) {
                    Text("Pantau agent")
                }
            } header: {
                Text("Umum")
            }

            Section {
                Defaults.Toggle(key: .agentNotifyWaiting) {
                    Text("Butuh input")
                }
                Defaults.Toggle(key: .agentNotifyError) {
                    Text("Error")
                }
                Defaults.Toggle(key: .agentNotifyDone) {
                    Text("Selesai")
                }
            } header: {
                Text("Notifikasi di notch tertutup")
            }

            Section {
                ForEach(hookCapableDefinitions) { def in
                    let isInstalled = installer.installed[def.id] ?? false
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(def.displayName)
                                    .font(.body)
                                Text(isInstalled ? "Terpasang" : "Belum terpasang")
                                    .font(.caption)
                                    .foregroundStyle(isInstalled ? .green : .secondary)
                            }
                            Spacer()
                            if isInstalled {
                                Button("Lepas hooks") {
                                    uninstallHooks(for: def)
                                }
                            } else {
                                Button("Pasang hooks") {
                                    installHooks(for: def)
                                }
                            }
                        }

                        if def.id == "codex" {
                            Text("Codex mungkin meminta persetujuan hook baru saat sesi berikutnya dimulai.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let err = hookErrors[def.id] {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Hooks")
            }

            Section {
                if customRules.isEmpty {
                    Text("Belum ada agent tambahan.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customRules, id: \.id) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.displayName)
                                Text(rule.executable)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                customRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button("Tambah dari proses yang berjalan") {
                    showingProcessPicker = true
                }
            } header: {
                Text("Agent tambahan")
            }

            Section {
                ForEach(allDefinitions) { def in
                    HStack(spacing: 10) {
                        agentIconPreview(for: def.id)
                            .frame(width: 20, height: 20)

                        Text(def.displayName)
                        Spacer()
                        Button("Pilih logo…") {
                            pickLogo(for: def.id)
                        }
                    }
                }

                if let iconError {
                    Text(iconError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Logo agent")
            }
        }
        .navigationTitle("Agents")
        .onAppear {
            installer.refresh()
        }
        .sheet(isPresented: $showingProcessPicker) {
            RunningProcessPickerSheet(
                existingRegistry: manager.registry,
                onSelect: { executable in
                    let newRule = CustomAgentRule(
                        id: executable,
                        displayName: executable,
                        executable: executable
                    )
                    if !customRules.contains(where: { $0.id == newRule.id }) {
                        customRules.append(newRule)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func agentIconPreview(for agentID: String) -> some View {
        let _ = iconProvider.revision
        if let nsImage = iconProvider.icon(for: agentID) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
        }
    }

    private func installHooks(for def: AgentDefinition) {
        do {
            try installer.install(def)
            hookErrors.removeValue(forKey: def.id)
        } catch {
            hookErrors[def.id] = error.localizedDescription
        }
    }

    private func uninstallHooks(for def: AgentDefinition) {
        do {
            try installer.uninstall(def)
            hookErrors.removeValue(forKey: def.id)
        } catch {
            hookErrors[def.id] = error.localizedDescription
        }
    }

    private func pickLogo(for agentID: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Pilih file gambar untuk logo \(manager.displayName(for: agentID))"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try iconProvider.setCustomIcon(url, for: agentID)
            iconError = nil
        } catch {
            iconError = error.localizedDescription
        }
    }
}

private struct RunningProcessPickerSheet: View {
    let existingRegistry: AgentRegistry
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var executables: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pilih proses yang berjalan")
                    .font(.headline)
                Spacer()
                Button("Tutup") {
                    dismiss()
                }
            }

            if executables.isEmpty {
                Text("Tidak ada proses baru yang tersedia.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(executables, id: \.self) { executable in
                    Button {
                        onSelect(executable)
                        dismiss()
                    } label: {
                        HStack {
                            Text(executable)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 360, height: 380)
        .onAppear {
            loadExecutables()
        }
    }

    private func loadExecutables() {
        let snapshots = ProcessScanner.snapshotAll()
        var unique: Set<String> = []
        for snap in snapshots where ProcessMatcher.agentID(for: snap, in: existingRegistry) == nil {
            if !snap.executable.isEmpty {
                unique.insert(snap.executable)
            }
        }
        executables = unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
