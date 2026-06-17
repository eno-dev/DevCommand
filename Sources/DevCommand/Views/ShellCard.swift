import SwiftUI
import AppKit

@MainActor
final class ShellCardViewModel: ObservableObject {
    @Published var info: ShellEnvService.Info?
    @Published var zshrc: String?
    @Published var loadingConfig = false

    func load() async {
        info = await ShellEnvService.load()
    }

    func loadConfig() {
        guard zshrc == nil else { return }
        loadingConfig = true
        zshrc = ShellEnvService.readZshrc() ?? "~/.zshrc not found."
        loadingConfig = false
    }
}

/// Shell-setup card shown at the top of the Doctor panel. Makes it obvious which Node a
/// launched command will use (and via which version manager), lists the rc files that exist,
/// lets you peek at ~/.zshrc inline, and opens it in your editor / Terminal / Finder.
struct ShellCard: View {
    @StateObject private var vm = ShellCardViewModel()
    @State private var showConfig = false

    private var zshrcPath: String { ShellEnvService.zshrcPath }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            HStack(spacing: Theme.s6) {
                Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text("SHELL")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { Task { await Launch.openWith(app: Preferences.editorApp, path: zshrcPath) } } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                }
                .buttonStyle(SubtleIconButtonStyle()).help("Edit ~/.zshrc in \(Preferences.editorApp)")
                Button { Task { await Launch.terminal(at: NSHomeDirectory()) } } label: {
                    Image(systemName: "apple.terminal").font(.system(size: 11))
                }
                .buttonStyle(SubtleIconButtonStyle()).help("Open Terminal in your home folder")
                Button { Task { await Launch.reveal(zshrcPath) } } label: {
                    Image(systemName: "folder").font(.system(size: 11))
                }
                .buttonStyle(SubtleIconButtonStyle()).help("Reveal ~/.zshrc in Finder")
            }

            if let info = vm.info {
                summary(info)
            } else {
                Text("Checking shell…").font(.caption).foregroundStyle(.tertiary)
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) { showConfig.toggle() }
                if showConfig { vm.loadConfig() }
            } label: {
                HStack(spacing: Theme.s4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showConfig ? 90 : 0))
                    Text("View ~/.zshrc").font(.caption)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())   // whole row is the hit target, not just the text
            }
            .buttonStyle(.plain)

            if showConfig {
                ScrollView {
                    Text(vm.zshrc ?? "…")
                        .font(Theme.mono(10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, Theme.s4)
                }
                .frame(maxHeight: 168)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.s12)
        .task { await vm.load() }
    }

    @ViewBuilder
    private func summary(_ info: ShellEnvService.Info) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Theme.s6) {
                if info.hasNode {
                    Text(verbatim: "node \(info.nodeVersion ?? "")").font(Theme.mono(12, .semibold))
                    Pill(info.managerSummary, color: info.managers.isEmpty ? .secondary : Theme.accent)
                } else {
                    Label("Node not found on the login shell PATH", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if let path = info.nodePath, !path.isEmpty {
                Text(verbatim: path)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            if !info.configFiles.isEmpty {
                Text(verbatim: "Config: " + info.configFiles.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
