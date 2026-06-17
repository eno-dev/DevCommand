import SwiftUI
import AppKit

@MainActor
final class PortsViewModel: ObservableObject {
    @Published var ports: [ListeningPort] = []
    @Published var isLoading = false
    @Published var hideSystem = true
    @Published var lanIP: String?
    @Published var banner: String?

    var visible: [ListeningPort] {
        hideSystem ? ports.filter { !$0.isSystem && !$0.isAppHelper } : ports
    }

    func refresh() async {
        if ports.isEmpty { isLoading = true }
        lanIP = NetworkService.primaryLocalIP()
        ports = await PortService.listening()
        isLoading = false
    }

    func kill(_ port: ListeningPort, force: Bool) async {
        let result = await PortService.kill(pid: port.pid, force: force)
        if !result.ok {
            report("Couldn't \(force ? "force-kill" : "stop") PID \(port.pid) (\(port.command)): \(result.briefError)")
        }
        await refresh()
    }

    /// Show a dismissable error, auto-clearing after a few seconds so it doesn't linger.
    private func report(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if banner == message { banner = nil }
        }
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PortsView: View {
    @StateObject private var vm = PortsViewModel()
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
        // Poll only while the panel is visible, and never overlap: each cycle awaits the
        // previous refresh before sleeping, so a slow lsof can't stack up tasks.
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
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { break }
                await vm.refresh()
            }
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    private var header: some View {
        HStack(spacing: Theme.s8) {
            Text(verbatim: "\(vm.visible.count) listening")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle("Hide system", isOn: $vm.hideSystem)
                .toggleStyle(.checkbox).font(.caption)
            Button { Task { await vm.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Refresh ports")
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.s8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.visible.isEmpty {
            EmptyStateView(icon: "bolt.horizontal.circle", title: "No listening ports")
        } else {
            let lanIP = vm.lanIP
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.visible) { port in
                        PortRow(
                            port: port,
                            lanIP: lanIP,
                            onCopy: { vm.copy($0) },
                            onOpen: { vm.openInBrowser($0) },
                            onKill: { force in Task { await vm.kill(port, force: force) } }
                        )
                        Divider()
                    }
                }
            }
        }
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let lanIP: String?
    let onCopy: (String) -> Void
    let onOpen: (String) -> Void
    let onKill: (Bool) -> Void

    @State private var hovering = false

    private var localURL: String { "http://localhost:\(port.port)" }
    // A loopback-only port isn't reachable from a phone, so don't offer a LAN URL/QR for it.
    private var lanURL: String? {
        guard let lanIP, !port.isLoopback else { return nil }
        return "http://\(lanIP):\(port.port)"
    }
    private var expoURL: String? {
        guard let lanIP, !port.isLoopback, port.supportsExpoScheme else { return nil }
        return "exp://\(lanIP):\(port.port)"
    }

    var body: some View {
        HStack(spacing: Theme.s10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.s6) {
                    Text(verbatim: "\(port.port)")
                        .font(Theme.mono(15, .semibold))
                        .foregroundStyle(.primary)
                    if let label = port.devLabel {
                        Pill(label, color: port.isStorybook ? Theme.storybook : Theme.accent)
                    }
                }
                Text(verbatim: "\(port.command)  ·  PID \(port.pid)  ·  \(port.address)")
                    .font(Theme.rowSubtitle).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.s8)
            if let lanURL { QRButton(url: lanURL, expoURL: expoURL) }
            Menu { actions } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Port actions")
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        let header = "PID \(port.pid) · \(port.command)"
        Section(header) {
            Button { onOpen(localURL) } label: { Label("Open in Browser", systemImage: "safari") }
            Button { onCopy(localURL) } label: { Label("Copy URL", systemImage: "doc.on.doc") }
            if let lanURL {
                Button { onCopy(lanURL) } label: { Label("Copy LAN URL", systemImage: "wifi") }
            }
            Button { onCopy(String(port.pid)) } label: { Label("Copy PID", systemImage: "number") }
        }
        Divider()
        Button(role: .destructive) { onKill(false) } label: {
            Label("Terminate (SIGTERM)", systemImage: "stop.circle")
        }
        Button(role: .destructive) { onKill(true) } label: {
            Label("Force Kill (SIGKILL)", systemImage: "bolt.trianglebadge.exclamationmark")
        }
    }
}
