import SwiftUI
import AppKit

@MainActor
final class NetworkBarViewModel: ObservableObject {
    @Published var localIP: String?
    @Published var publicIP: String?
    @Published var loadingPublic = false
    @Published var copied: String?

    /// Set once the user explicitly reveals the public IP this session, so a manual refresh
    /// re-fetches it instead of hiding it again.
    private var revealed = false

    func load(forceRefresh: Bool = false) async {
        localIP = NetworkService.primaryLocalIP()
        // Only reach the network if the user opted in (default) or has revealed it this session.
        if SettingsStore.shared.showPublicIP || revealed {
            await fetchPublicIP(forceRefresh: forceRefresh)
        } else {
            publicIP = nil
        }
    }

    /// User-initiated lookup — the only path that fetches the public IP while the setting is off.
    /// Makes exactly one outbound request (bypassing the cache).
    func revealPublicIP() async {
        revealed = true
        await fetchPublicIP(forceRefresh: true)
    }

    private func fetchPublicIP(forceRefresh: Bool) async {
        loadingPublic = true
        publicIP = await NetworkService.publicIP(forceRefresh: forceRefresh)
        loadingPublic = false
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = value
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copied == value { copied = nil }
        }
    }
}

/// Always-visible strip showing the LAN and public IP, each click-to-copy. When "Show public IP"
/// is off, the public field becomes a tap-to-reveal chip — no outbound request until you ask.
struct NetworkBar: View {
    @StateObject private var vm = NetworkBarViewModel()

    var body: some View {
        HStack(spacing: Theme.s8) {
            pill(icon: "network", label: "LAN", value: vm.localIP, loading: false)
            publicPill
            Spacer(minLength: 0)
            Button { Task { await vm.load(forceRefresh: true) } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Refresh IPs")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.s8)
        .task { await vm.load() }
    }

    /// Public IP: the copy chip once it's known (setting on, or revealed); otherwise a "Show" chip
    /// that fetches it on demand — making it obvious you can reveal it right where it'd appear.
    @ViewBuilder
    private var publicPill: some View {
        if vm.publicIP != nil || vm.loadingPublic {
            pill(icon: "globe", label: "Public", value: vm.publicIP, loading: vm.loadingPublic)
        } else {
            Button { Task { await vm.revealPublicIP() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(verbatim: "Public").font(Theme.mono(11)).foregroundStyle(.secondary)
                    Image(systemName: "eye").font(.system(size: 9)).foregroundStyle(Theme.accent)
                    Text(verbatim: "Show").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Show your public IP — looks it up with a single network request")
        }
    }

    @ViewBuilder
    private func pill(icon: String, label: String, value: String?, loading: Bool) -> some View {
        let isCopied = value != nil && vm.copied == value
        Button {
            if let value { vm.copy(value) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(verbatim: loading ? "···" : (value ?? "—"))
                    .font(Theme.mono(11))
                    .foregroundStyle(.primary)
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(isCopied ? Color.green : Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.chip, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(value == nil)
        .help(value.map { "Copy \(label) IP — \($0)" } ?? "\(label) IP unavailable")
    }
}
