import SwiftUI
import AppKit

@MainActor
final class SimulatorsViewModel: ObservableObject {
    @Published var groups: [SimRuntimeGroup] = []
    @Published var devices: [PhysicalDevice] = []
    @Published var projects: [DevProject] = []
    @Published var activeProjects: [String: DevProject] = [:]  // udid -> project currently running on it
    @Published var isLoading = false
    @Published var busyUDID: String?
    @Published var banner: String?
    @Published var mismatch: RunMismatch?   // platform-mismatch dialog (full message + 1-click fix)

    private var activeBundleID: [String: String] = [:]  // udid -> the running app's bundle id (for reload)

    var totalDevices: Int { groups.reduce(0) { $0 + $1.devices.count } }
    var connectedDevices: Int { devices.lazy.filter(\.isConnected).count }

    func refresh() async {
        if groups.isEmpty && devices.isEmpty { isLoading = true }
        async let sims = SimulatorService.list()
        async let devs = DeviceService.list()
        async let scanned = ProjectService.scan(roots: Preferences.devRoots)
        groups = await sims
        devices = await devs
        projects = (await scanned).filter { $0.hasIOS }
        await detectActive()
        isLoading = false
    }

    /// Lightweight live poll: sim states + running-app detection, reusing the cached project scan.
    /// `includeDevices` runs the slow `devicectl` scan — only every few cycles, since physical
    /// devices change rarely, so it's wasteful to re-list them every 4s.
    func refreshActive(includeDevices: Bool) async {
        if includeDevices {
            async let sims = SimulatorService.list()
            async let devs = DeviceService.list()
            groups = await sims
            devices = await devs
        } else {
            groups = await SimulatorService.list()
        }
        await detectActive()
    }

    /// Match each booted sim's running apps against the scanned projects, so a sim
    /// reflects whatever it's actually running — however it was launched.
    private func detectActive() async {
        let booted = groups.flatMap(\.devices).filter(\.isBooted)
        let projs = projects
        var foundProjects: [String: DevProject] = [:]
        var foundIDs: [String: String] = [:]
        await withTaskGroup(of: (String, (project: DevProject, bundleID: String)?).self) { group in
            for sim in booted {
                group.addTask {
                    let running = await SimulatorService.runningApps(udid: sim.udid)
                    return (sim.udid, ProjectService.match(running: running, in: projs))
                }
            }
            for await (udid, hit) in group {
                if let hit { foundProjects[udid] = hit.project; foundIDs[udid] = hit.bundleID }
            }
        }
        activeProjects = foundProjects
        activeBundleID = foundIDs
    }

    func boot(_ sim: Simulator) async {
        busyUDID = sim.udid
        let result = await SimulatorService.boot(sim.udid)
        if !result.ok { report("Couldn't boot \(sim.name): \(result.briefError)") }
        await SimulatorService.openSimulatorApp()
        await refresh()
        busyUDID = nil
    }

    func shutdown(_ sim: Simulator) async {
        busyUDID = sim.udid
        let result = await SimulatorService.shutdown(sim.udid)
        if !result.ok { report("Couldn't shut down \(sim.name): \(result.briefError)") }
        await refresh()
        busyUDID = nil
    }

    private func report(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if banner == message { banner = nil }
        }
    }

    func run(project: DevProject, on sim: Simulator) async {
        let target: ApplePlatform = sim.isTV ? .tvOS : .iOS
        let outcome = await Task.detached(priority: .userInitiated) {
            ProjectService.runOutcome(for: project, udid: sim.udid, targetName: sim.name, target: target)
        }.value
        switch outcome {
        case .platformMismatch(let message, let fix):
            mismatch = RunMismatch(project: project, message: message, fix: fix)
        case .command(let command):
            if !sim.isBooted { _ = await SimulatorService.boot(sim.udid) }
            await SimulatorService.openSimulatorApp()
            if command.isEmpty {
                if let artifact = ProjectService.xcodeArtifact(for: project) { await Launch.open(artifact) }
            } else {
                await Launch.inTerminal(command, cwd: project.path)
            }
        }
    }

    /// Build-and-run a project on a physical device, targeting it by UDID (no boot needed).
    func run(project: DevProject, onDevice device: PhysicalDevice) async {
        let target: ApplePlatform = device.isTV ? .tvOS : .iOS
        let outcome = await Task.detached(priority: .userInitiated) {
            ProjectService.runOutcome(for: project, udid: device.udid, targetName: device.name, target: target)
        }.value
        switch outcome {
        case .platformMismatch(let message, let fix):
            mismatch = RunMismatch(project: project, message: message, fix: fix)
        case .command(let command):
            if command.isEmpty {
                if let artifact = ProjectService.xcodeArtifact(for: project) { await Launch.open(artifact) }
            } else {
                await Launch.inTerminal(command, cwd: project.path)
            }
        }
    }

    /// Run the corrective prebuild-and-run command in Terminal (same channel as a normal run),
    /// so the user fixes a platform mismatch from inside the app with one click.
    func applyFix(_ m: RunMismatch) async {
        guard let fix = m.fix else { return }
        await Launch.inTerminal(fix, cwd: m.project.path, title: m.project.name)
    }

    func copyFix(_ m: RunMismatch) {
        guard let fix = m.fix else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fix, forType: .string)
    }

    /// Reload the running app by restarting it on the simulator (terminate + relaunch),
    /// which re-pulls the JS bundle from Metro. Reliable and needs no extra permissions.
    func reload(_ sim: Simulator) async {
        guard let bundleID = activeBundleID[sim.udid] else { return }
        busyUDID = sim.udid
        await SimulatorService.reloadApp(udid: sim.udid, bundleID: bundleID)
        await detectActive()      // refresh the running-app state after relaunch
        busyUDID = nil
    }

    /// Restart the bundler with a cleared Metro cache, in a Terminal window.
    func reloadClearCache(_ sim: Simulator) async {
        guard let project = activeProjects[sim.udid],
              let command = ProjectService.clearCacheCommand(for: project) else { return }
        busyUDID = sim.udid
        await Launch.inTerminal(command, cwd: project.path)
        busyUDID = nil
    }
}

struct SimulatorsView: View {
    @StateObject private var vm = SimulatorsViewModel()
    @Environment(\.controlActiveState) private var activeState
    @State private var poller: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let banner = vm.banner {
                InlineBanner(text: banner) { vm.banner = nil }
                Divider()
            }
            content
        }
        .runMismatchAlert($vm.mismatch,
                          onFix: { m in Task { await vm.applyFix(m) } },
                          onCopy: { vm.copyFix($0) })
        // Poll running-app state only while the panel is open: start on appear/reopen,
        // stop the moment it closes so nothing runs in the background.
        .task { startPolling() }
        .onChange(of: activeState) { _, state in
            if state == .inactive { stopPolling() } else { startPolling() }
        }
        .onDisappear { stopPolling() }
    }

    private func startPolling() {
        guard poller == nil else { return }
        poller = Task {
            await vm.refresh()
            var cycle = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                cycle += 1
                await vm.refreshActive(includeDevices: cycle % 4 == 0)   // devicectl every ~16s
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    private var headerSummary: String {
        var parts = ["\(vm.totalDevices) simulators"]
        if vm.connectedDevices > 0 {
            parts.append("\(vm.connectedDevices) device\(vm.connectedDevices == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: Theme.s8) {
            Text(verbatim: headerSummary)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await SimulatorService.openSimulatorApp() } } label: {
                Image(systemName: "macwindow").font(.system(size: 12))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Open Simulator.app")
            Button { Task { await vm.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Refresh simulators")
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.s8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.groups.isEmpty && vm.devices.isEmpty {
            EmptyStateView(icon: "iphone.slash", title: "No simulators or devices found")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !vm.devices.isEmpty {
                        SectionLabel("Physical Devices")
                        ForEach(vm.devices) { device in
                            DeviceRow(device: device,
                                      projects: vm.projects,
                                      onRun: { project in Task { await vm.run(project: project, onDevice: device) } })
                            Divider()
                        }
                    }
                    ForEach(vm.groups) { group in
                        SectionLabel("\(group.platform) \(group.version)")
                        ForEach(group.devices) { sim in
                            SimRow(sim: sim,
                                   projects: vm.projects,
                                   activeProject: vm.activeProjects[sim.udid],
                                   busy: vm.busyUDID == sim.udid,
                                   onBoot: { Task { await vm.boot(sim) } },
                                   onShutdown: { Task { await vm.shutdown(sim) } },
                                   onRun: { project in Task { await vm.run(project: project, on: sim) } },
                                   onReload: { Task { await vm.reload(sim) } },
                                   onReloadClearCache: { Task { await vm.reloadClearCache(sim) } })
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct SimRow: View {
    let sim: Simulator
    let projects: [DevProject]
    let activeProject: DevProject?
    let busy: Bool
    let onBoot: () -> Void
    let onShutdown: () -> Void
    let onRun: (DevProject) -> Void
    let onReload: () -> Void
    let onReloadClearCache: () -> Void
    @State private var hovering = false

    private var subtitle: String {
        if let active = activeProject { return "Running \(active.name)" }
        return sim.isBooted ? "Booted" : "Shutdown"
    }

    var body: some View {
        HStack(spacing: Theme.s10) {
            StatusDot(active: sim.isBooted)
            VStack(alignment: .leading, spacing: 1) {
                Text(sim.name).font(Theme.rowTitle)
                Text(subtitle)
                    .font(Theme.rowSubtitle).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.s8)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                if sim.isBooted, let active = activeProject, active.usesMetro {
                    Menu {
                        Button("Reload") { onReload() }
                        Button("Reload & Clear Cache") { onReloadClearCache() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Reload \(active.name)")
                }
                if !projects.isEmpty {
                    Menu {
                        ForEach(projects) { project in Button(project.name) { onRun(project) } }
                    } label: {
                        Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                            .help("Run a project here")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Run a project on this simulator")
                }
                Button(sim.isBooted ? "Stop" : "Boot") {
                    if sim.isBooted { onShutdown() } else { onBoot() }
                }
                .controlSize(.small)
            }
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A real, paired device (iPhone/iPad/Apple TV/Watch). Connected ones lead, lit; a
/// disconnected device shows dimmed so its absence is obvious at a glance.
private struct DeviceRow: View {
    let device: PhysicalDevice
    let projects: [DevProject]
    let onRun: (DevProject) -> Void
    @State private var hovering = false
    @State private var copied = false

    private var subtitle: String {
        guard device.isConnected else { return "Not connected" }
        let os = device.osVersion.isEmpty ? "" : "\(device.platform) \(device.osVersion)"
        return os.isEmpty ? device.displayModel : "\(device.displayModel) · \(os)"
    }

    var body: some View {
        HStack(spacing: Theme.s10) {
            Image(systemName: device.symbol)
                .font(.system(size: 14))
                .frame(width: 18)
                .foregroundStyle(device.isConnected ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.s6) {
                    Text(device.name).font(Theme.rowTitle)
                    if let label = device.connectionLabel { Pill(label, color: .green) }
                }
                Text(subtitle)
                    .font(Theme.rowSubtitle).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.s8)
            if device.isRunnable, !projects.isEmpty {
                Menu {
                    ForEach(projects) { project in Button(project.name) { onRun(project) } }
                } label: {
                    Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Run a project on this device")
            }
            Button { copyUDID() } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle())
            .help("Copy device UDID")
        }
        .opacity(device.isConnected ? 1 : 0.55)
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func copyUDID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(device.udid, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}
