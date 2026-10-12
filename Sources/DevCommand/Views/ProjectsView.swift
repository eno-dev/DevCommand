import SwiftUI
import AppKit

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [DevProject] = []
    @Published var isLoading = true
    @Published var running: [String: ActiveBundler] = [:]   // project.path -> its running dev server
    @Published var orphanServers: [ActiveBundler] = []      // running servers not tied to a project
    @Published var lanIP: String?                           // computed on poll, not per render
    @Published var banner: String?
    @Published var mismatch: RunMismatch?   // platform-mismatch dialog (full message + 1-click fix)
    @Published var restarting: Set<String> = []             // project paths in the middle of a restart

    var devRoots: [String] { SettingsStore.shared.devRoots }
    /// The folders the current list was scanned from; nil until the first scan finishes.
    private var scannedRoots: [String]?

    func refresh() async {
        let roots = SettingsStore.shared.devRoots
        projects = await ProjectService.scan(roots: roots)
        scannedRoots = roots
        await updateRunning()
        isLoading = false
    }

    /// Poller entry point: scan the disk on first open, or when the dev folders changed since
    /// the last scan; any other reopen just refreshes running servers.
    func resume() async {
        guard scannedRoots == SettingsStore.shared.devRoots else { return await refresh() }
        await updateRunning()
    }

    /// Rescan when the dev folders are edited (here or in Settings) while the panel exists.
    func rootsChanged() async {
        guard scannedRoots != SettingsStore.shared.devRoots else { return }
        isLoading = true
        await refresh()
    }

    func addRoot(_ path: String) { SettingsStore.shared.addRoot(path) }   // the view's onChange rescans

    /// Light refresh of just the running-server state — reuses the cached project list,
    /// so it can poll without re-hitting the filesystem. Publishes only what changed, so a poll
    /// that finds nothing new doesn't re-render every row.
    func updateRunning() async {
        let ip = NetworkService.primaryLocalIP()
        if ip != lanIP { lanIP = ip }
        let servers = await BundlerService.active()
        let (matched, orphans) = ProjectService.matchServers(servers, to: projects)
        if matched != running { running = matched }
        if orphans != orphanServers { orphanServers = orphans }
    }

    // MARK: Ordering & favorites

    /// Favorited projects, pinned to the top in the user's saved (drag-reorderable) order.
    var favoriteProjects: [DevProject] {
        SettingsStore.shared.favoritePaths.compactMap { path in projects.first { $0.path == path } }
    }

    /// Everything else: running (active) projects first, then alphabetical.
    var otherProjects: [DevProject] {
        let favorites = Set(SettingsStore.shared.favoritePaths)
        return projects.filter { !favorites.contains($0.path) }.sorted { lhs, rhs in
            let lr = running[lhs.path] != nil, rr = running[rhs.path] != nil
            if lr != rr { return lr }   // active first
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func toggleFavorite(_ project: DevProject) { SettingsStore.shared.toggleFavorite(project.path) }
    func moveFavorite(_ path: String, before target: String) {
        SettingsStore.shared.moveFavorite(path, before: target)
    }

    // MARK: Dev server

    func startServer(_ project: DevProject, clear: Bool) async {
        await BundlerService.start(project, clear: clear)
    }

    /// Bring this project's exact terminal window to the front (by the window id captured at launch).
    func showTerminal(_ project: DevProject) async {
        await Launch.showTerminal(key: project.path, title: project.name)
    }

    /// Hide (minimise) this project's exact terminal window.
    func hideTerminal(_ project: DevProject) async {
        await Launch.hideTerminal(key: project.path, title: project.name)
    }

    func stopServer(_ server: ActiveBundler) async {
        let result = await BundlerService.stop(pid: server.pid)
        if !result.ok { report("Couldn't stop \(server.label) on \(server.port): \(result.briefError)") }
        await updateRunning()
    }

    /// Stop the project's dev server, wait until it has really exited (so its port is free),
    /// then start it again. With `clear`, Metro / Expo come back with a cleared cache.
    func restartServer(_ project: DevProject, clear: Bool) async {
        guard let server = running[project.path], !restarting.contains(project.path) else { return }
        restarting.insert(project.path)
        defer { restarting.remove(project.path) }
        let stopped = await BundlerService.stop(pid: server.pid)
        guard stopped.ok, await BundlerService.waitForExit(pid: server.pid) else {
            report("Couldn't restart \(project.name): the server on \(server.port) didn't stop")
            await updateRunning()
            return
        }
        await BundlerService.start(project, clear: clear)
        await updateRunning()
    }

    // MARK: Build / run

    func run(_ project: DevProject, tv: Bool) async {
        let target: ApplePlatform = tv ? .tvOS : .iOS
        // Compute off the main actor — runOutcome reads the project's pbxproj from disk.
        let outcome = await Task.detached(priority: .userInitiated) {
            ProjectService.runOutcome(for: project, udid: nil, targetName: nil, target: target)
        }.value
        switch outcome {
        case .platformMismatch(let message, let fix):
            mismatch = RunMismatch(project: project, message: message, fix: fix)
        case .command(let command):
            if command.isEmpty { await openXcode(project) }
            else { await Launch.inTerminal(command, cwd: project.path, title: project.name) }
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

    func prebuild(_ project: DevProject, clean: Bool) async {
        await Launch.inTerminal(ProjectService.prebuildCommand(for: project, clean: clean),
                                cwd: project.path, title: project.name)
    }

    func podInstall(_ project: DevProject) async {
        await Launch.inTerminal(ProjectService.podInstallCommand(), cwd: project.path, title: project.name)
    }

    func install(_ project: DevProject) async {
        await Launch.inTerminal(project.packageManager.install, cwd: project.path, title: project.name)
    }

    func runScript(_ project: DevProject, _ script: String) async {
        await Launch.inTerminal(ProjectService.scriptCommand(for: project, script: script),
                                cwd: project.path, title: project.name)
    }

    func cleanCaches(_ project: DevProject) async {
        await Launch.inTerminal(ProjectService.cleanCachesCommand(), cwd: project.path, title: project.name)
    }

    // MARK: Open

    func openXcode(_ project: DevProject) async {
        if let artifact = ProjectService.xcodeArtifact(for: project) { await Launch.open(artifact) }
    }

    func openEditor(_ project: DevProject) async {
        await Launch.openWith(app: Preferences.editorApp, path: project.path)
    }

    func openTerminal(_ project: DevProject) async {
        await Launch.terminal(at: project.path)
    }

    func reveal(_ project: DevProject) async {
        await Launch.open(project.path)
    }

    func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func report(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if banner == message { banner = nil }
        }
    }
}

struct ProjectsView: View {
    @Binding var filter: String
    @StateObject private var vm = ProjectsViewModel()
    @ObservedObject private var settings = SettingsStore.shared   // re-sort on favorite changes
    @Environment(\.controlActiveState) private var activeState
    @State private var poller: Task<Void, Never>?
    @FocusState private var filterFocused: Bool

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
        // Full scan once, then poll just the running-server state — non-overlapping (each cycle
        // awaits the previous) and only while visible, so slow lsof calls can't stack up.
        .task { startPolling() }
        .onChange(of: activeState) { _, state in
            if state == .inactive { stopPolling() } else { startPolling() }
        }
        .onDisappear { stopPolling() }
        // Dev folders edited (here or in Settings): rescan instead of waiting for a manual Rescan.
        .onChange(of: settings.devRoots) { _, _ in Task { await vm.rootsChanged() } }
    }

    private func startPolling() {
        filterFocused = true   // so typing filters straight away, no click needed
        guard poller == nil else { return }
        poller = Task {
            await vm.resume()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                await vm.updateRunning()
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    private var rootSummary: String {
        let roots = vm.devRoots
        if roots.count == 1 { return (roots[0] as NSString).abbreviatingWithTildeInPath }
        return "\(roots.count) folders"
    }

    private var header: some View {
        HStack(spacing: Theme.s8) {
            FilterField(prompt: "Filter projects in \(rootSummary)", text: $filter, focused: $filterFocused)
                .help(vm.devRoots.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
            Button { pickFolder() } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 12))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Add a dev folder (manage in Settings)")
            Button { Task { await vm.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Rescan projects (⌘R)")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.s8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.projects.isEmpty && vm.orphanServers.isEmpty {
            EmptyStateView(icon: "folder.badge.questionmark", title: "No projects found")
        } else {
            let lanIP = vm.lanIP
            let query = filter.trimmingCharacters(in: .whitespaces)
            let favorites = vm.favoriteProjects.filter { query.isEmpty || $0.matches(query) }
            let others = vm.otherProjects.filter { query.isEmpty || $0.matches(query) }
            let orphans = vm.orphanServers.filter { query.isEmpty || $0.matches(query) }
            if favorites.isEmpty && others.isEmpty && orphans.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "No projects match “\(query)”")
            } else {
                projectList(favorites: favorites, orphans: orphans, others: others, lanIP: lanIP)
            }
        }
    }

    private func projectList(favorites: [DevProject], orphans: [ActiveBundler],
                             others: [DevProject], lanIP: String?) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !favorites.isEmpty {
                    SectionLabel("Favorites")
                    ForEach(favorites) { project in
                        ProjectRow(project: project, vm: vm, lanIP: lanIP, isFavorite: true)
                            .draggable(project.path)
                            .dropDestination(for: String.self) { items, _ in
                                for path in items { vm.moveFavorite(path, before: project.path) }
                                return true
                            }
                        Divider()
                    }
                }
                if !orphans.isEmpty {
                    SectionLabel("Other running servers")
                    ForEach(orphans) { server in
                        OrphanServerRow(server: server, lanIP: lanIP, vm: vm)
                        Divider()
                    }
                }
                if !others.isEmpty {
                    if !favorites.isEmpty || !orphans.isEmpty { SectionLabel("Projects") }
                    ForEach(others) { project in
                        ProjectRow(project: project, vm: vm, lanIP: lanIP, isFavorite: false)
                        Divider()
                    }
                }
            }
        }
    }

    private func pickFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: vm.devRoots.first ?? NSHomeDirectory())
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK {
            for url in panel.urls { vm.addRoot(url.path) }
        }
    }
}

private struct ProjectRow: View {
    let project: DevProject
    @ObservedObject var vm: ProjectsViewModel
    let lanIP: String?
    let isFavorite: Bool
    @State private var hovering = false
    @State private var showingQR = false

    private var server: ActiveBundler? { vm.running[project.path] }

    var body: some View {
        HStack(spacing: Theme.s10) {
            Image(systemName: project.kind.icon)
                .frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(Theme.rowTitle)
                HStack(spacing: Theme.s4) {
                    Pill(project.kindLabel, color: .secondary)
                    if project.supportsTV { Pill("tvOS") }
                }
            }
            Spacer(minLength: Theme.s8)
            if isFavorite || hovering {
                Button { vm.toggleFavorite(project) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(isFavorite ? Theme.accent : Color.secondary)
                }
                .buttonStyle(SubtleIconButtonStyle())
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            if let server {
                runningControls(server)
            } else {
                primaryButton
            }
            menu
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private func runningControls(_ server: ActiveBundler) -> some View {
        Button { vm.openInBrowser("http://localhost:\(server.port)") } label: {
            HStack(spacing: Theme.s4) {
                StatusDot(active: true)
                Text(verbatim: ":\(server.port)").font(Theme.mono(11)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Running — open http://localhost:\(server.port)")
        if vm.restarting.contains(project.path) {
            ProgressView().controlSize(.small)
        } else {
            restartControl
            Button("Stop", role: .destructive) { Task { await vm.stopServer(server) } }.controlSize(.small)
        }
    }

    /// Restart the running server. Metro / Expo also offer a cache-clearing restart, so they get
    /// a two-item menu (the same shape as the simulator's reload menu); other servers a plain button.
    @ViewBuilder
    private var restartControl: some View {
        if project.usesMetro {
            Menu {
                Button("Restart") { Task { await vm.restartServer(project, clear: false) } }
                Button("Restart & Clear Cache") { Task { await vm.restartServer(project, clear: true) } }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Restart the dev server")
        } else {
            Button { Task { await vm.restartServer(project, clear: false) } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle())
            .help("Restart the dev server")
        }
    }

    /// LAN QR target for the running server, or nil when there's no server / LAN IP.
    private var qrURL: String? {
        guard let lanIP, let server else { return nil }
        return "http://\(lanIP):\(server.port)"
    }
    private var qrExpoURL: String? {
        guard let lanIP, let server, server.supportsExpoScheme else { return nil }
        return "exp://\(lanIP):\(server.port)"
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch project.kind {
        case .expo, .reactNative, .web:
            Button("Start") { Task { await vm.startServer(project, clear: false) } }
                .controlSize(.small)
                .help("Start the dev server (opens in \(Preferences.terminalApp))")
        case .nativeApple:
            Button("Xcode") { Task { await vm.openXcode(project) } }.controlSize(.small)
        }
    }

    private var menu: some View {
        Menu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { vm.toggleFavorite(project) }
            Divider()
            if server != nil {
                Button("Show terminal") { Task { await vm.showTerminal(project) } }
                Button("Hide terminal") { Task { await vm.hideTerminal(project) } }
                if qrURL != nil {
                    Button("Show QR code…") { showingQR = true }
                }
                Divider()
            }
            if project.usesMetro {
                Button("Run on iOS") { Task { await vm.run(project, tv: false) } }
                if project.supportsTV {
                    Button("Run on tvOS") { Task { await vm.run(project, tv: true) } }
                }
                Divider()
                Button("Prebuild") { Task { await vm.prebuild(project, clean: false) } }
                Button("Prebuild (clean)") { Task { await vm.prebuild(project, clean: true) } }
                if project.hasPods {
                    Button("Pod install") { Task { await vm.podInstall(project) } }
                }
                Divider()
            }
            if project.isJavaScript {
                Button("Start (clear cache)") { Task { await vm.startServer(project, clear: true) } }
                if !project.scripts.isEmpty {
                    Menu("Run script") {
                        ForEach(project.scripts, id: \.self) { script in
                            Button(script) { Task { await vm.runScript(project, script) } }
                        }
                    }
                }
                Button("Install (\(project.packageManager.label))") { Task { await vm.install(project) } }
                Button("Clean build caches") { Task { await vm.cleanCaches(project) } }
                Divider()
            }
            if project.hasIOS {
                Button("Open in Xcode") { Task { await vm.openXcode(project) } }
            }
            Button("Open in \(Preferences.editorApp)") { Task { await vm.openEditor(project) } }
            Button("Open in \(Preferences.terminalApp)") { Task { await vm.openTerminal(project) } }
            Button("Reveal in Finder") { Task { await vm.reveal(project) } }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Project actions")
        .popover(isPresented: $showingQR, arrowEdge: .bottom) {
            if let qrURL { QRPopover(url: qrURL, expoURL: qrExpoURL) }
        }
    }
}

/// A running dev server whose working directory isn't one of the scanned projects —
/// shown so a server started elsewhere (or outside the dev folder) is still visible/stoppable.
private struct OrphanServerRow: View {
    let server: ActiveBundler
    let lanIP: String?
    @ObservedObject var vm: ProjectsViewModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s10) {
            StatusDot(active: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.s6) {
                    Pill(server.label)
                    Text(verbatim: "\(server.port)").font(Theme.mono(11)).foregroundStyle(.secondary)
                }
                Text(verbatim: "\(server.projectName)  ·  PID \(server.pid)")
                    .font(Theme.rowSubtitle).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.s8)
            Button { vm.openInBrowser("http://localhost:\(server.port)") } label: {
                Image(systemName: "safari").font(.system(size: 13))
            }
            .buttonStyle(SubtleIconButtonStyle())
            .help("Open http://localhost:\(server.port) in your browser")
            if let lanIP {
                QRButton(url: "http://\(lanIP):\(server.port)",
                         expoURL: server.supportsExpoScheme ? "exp://\(lanIP):\(server.port)" : nil)
            }
            Button("Stop", role: .destructive) { Task { await vm.stopServer(server) } }.controlSize(.small)
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
