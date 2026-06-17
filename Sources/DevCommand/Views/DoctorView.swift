import SwiftUI

@MainActor
final class DoctorViewModel: ObservableObject {
    @Published var checks: [HealthCheck] = []
    @Published var isLoading = false

    var issues: Int { checks.filter { $0.status != .ok }.count }

    func refresh() async {
        if checks.isEmpty { isLoading = true }
        checks = await DoctorService.runAll()
        isLoading = false
    }

    func fix(_ check: HealthCheck) async {
        guard let command = check.fixCommand else { return }
        await Launch.inTerminal(command, cwd: NSHomeDirectory())
    }
}

struct DoctorView: View {
    @StateObject private var vm = DoctorViewModel()
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task { await vm.refresh() }
        .onChange(of: activeState) { _, state in
            if state != .inactive { Task { await vm.refresh() } }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.s8) {
            if vm.issues == 0 {
                Label("Everything looks healthy", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.caption)
            } else {
                Text(verbatim: "\(vm.issues) to look at")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await vm.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(SubtleIconButtonStyle()).help("Re-check")
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.s8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ShellCard()
                    Divider()
                    ForEach(vm.checks) { check in
                        DoctorRow(check: check) { Task { await vm.fix(check) } }
                        Divider()
                    }
                }
            }
        }
    }
}

private struct DoctorRow: View {
    let check: HealthCheck
    let onFix: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s10) {
            statusIcon.frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title).font(Theme.rowTitle)
                Text(verbatim: check.detail)
                    .font(Theme.rowSubtitle).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.s8)
            if let label = check.fixLabel {
                Button(label, action: onFix).controlSize(.small)
            }
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch check.status {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .fail: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
