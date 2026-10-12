import SwiftUI
import AppKit

@MainActor
final class ToolsViewModel: ObservableObject {
    enum Status { case idle, running, done, failed }

    @Published var generated: [String: String] = [:]
    @Published var status: [String: Status] = [:]
    @Published var copiedKey: String?

    func generate(_ tool: DevTool) {
        let value: String
        switch tool {
        case .uuid: value = ToolsService.uuid()
        case .secret: value = ToolsService.secretToken()
        default: return
        }
        generated[tool.id] = value
        copy(value, key: tool.id)
    }

    func copy(_ value: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedKey = key
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedKey == key { copiedKey = nil }
        }
    }

    func runMaintenance(_ tool: DevTool) async {
        status[tool.id] = .running
        let result = await ToolsService.runMaintenance(tool)
        status[tool.id] = result.ok ? .done : .failed
        let id = tool.id
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if status[id] != .running { status[id] = .idle }
        }
    }
}

struct ToolsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var vm = ToolsViewModel()

    private var enabled: [DevTool] { settings.orderedTools().filter { settings.toolEnabled($0) } }

    var body: some View {
        if enabled.isEmpty {
            EmptyStateView(icon: "wrench.and.screwdriver", title: "No tools enabled") {
                SettingsLink { Text("Open Settings") }.font(.caption)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(enabled) { tool in
                        row(for: tool)
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for tool: DevTool) -> some View {
        switch tool {
        case .uuid, .secret: GenerateRow(tool: tool, vm: vm)
        case .timestamp: TimestampRow(vm: vm)
        case .base64, .urlEncode, .jwt, .sha256, .json: ConvertRow(tool: tool, vm: vm)
        case .derivedData, .watchman, .npmCache, .killNode: MaintenanceRow(tool: tool, vm: vm)
        }
    }
}

private struct CopyButton: View {
    let isCopied: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(isCopied ? Color.green : Color.secondary)
        }
        .buttonStyle(.borderless).help("Copy")
    }
}

private struct GenerateRow: View {
    let tool: DevTool
    @ObservedObject var vm: ToolsViewModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s10) {
            Image(systemName: tool.icon).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(Theme.rowTitle)
                if let value = vm.generated[tool.id] {
                    Text(value).font(Theme.mono(11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                } else {
                    Text(tool.subtitle).font(Theme.rowSubtitle).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.s8)
            if let value = vm.generated[tool.id] {
                CopyButton(isCopied: vm.copiedKey == tool.id) { vm.copy(value, key: tool.id) }
            }
            Button(vm.generated[tool.id] == nil ? "Generate" : "New") { vm.generate(tool) }
                .controlSize(.small)
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct TimestampRow: View {
    @ObservedObject var vm: ToolsViewModel
    @State private var seconds = ""
    @State private var millis = ""
    @State private var hovering = false
    @State private var converting = false
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s6) {
            HStack(spacing: Theme.s10) {
                Image(systemName: "clock").frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Unix timestamp").font(Theme.rowTitle)
                    HStack(spacing: Theme.s6) {
                        chip(label: "s", value: seconds, key: "ts-s")
                        chip(label: "ms", value: millis, key: "ts-ms")
                    }
                }
                Spacer(minLength: Theme.s8)
                Button("Convert") { converting.toggle() }
                    .controlSize(.small)
                    .help("Turn a pasted timestamp into a date")
                Button("Now") {
                    let now = ToolsService.epochNow()
                    seconds = now.seconds
                    millis = now.millis
                }
                .controlSize(.small)
            }
            if converting { converter }
        }
        .rowInsets()
        .background(hovering ? Theme.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// Paste an epoch (seconds, ms, µs or ns) and read it back as a date; click a line to copy it.
    @ViewBuilder
    private var converter: some View {
        let converted = ToolsService.describeEpoch(input)
        VStack(alignment: .leading, spacing: Theme.s4) {
            TextField("Paste a timestamp…", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(11))
            if let converted {
                dateLine(converted.local, key: "ts-local")
                dateLine(converted.utc, key: "ts-utc")
            } else if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("⚠︎ not a timestamp").font(Theme.mono(10)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 20 + Theme.s10)   // line up under the title, past the icon
    }

    private func dateLine(_ value: String, key: String) -> some View {
        Button { vm.copy(value, key: key) } label: {
            HStack(spacing: Theme.s4) {
                Text(verbatim: value).font(Theme.mono(11))
                Image(systemName: vm.copiedKey == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(vm.copiedKey == key ? Color.green : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Copy")
    }

    @ViewBuilder
    private func chip(label: String, value: String, key: String) -> some View {
        Button {
            if !value.isEmpty { vm.copy(value, key: key) }
        } label: {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                Text(value.isEmpty ? "—" : value).font(Theme.mono(11))
                if vm.copiedKey == key {
                    Image(systemName: "checkmark").font(.system(size: 8)).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(value.isEmpty)
    }
}

private struct ConvertRow: View {
    let tool: DevTool
    @ObservedObject var vm: ToolsViewModel
    @State private var expanded = false
    @State private var input = ""
    @State private var decodeMode = false

    private var output: String {
        guard !input.isEmpty else { return "" }
        switch tool {
        case .base64:
            return decodeMode ? (ToolsService.base64Decode(input) ?? "⚠︎ invalid base64")
                              : ToolsService.base64Encode(input)
        case .urlEncode:
            return decodeMode ? (ToolsService.urlDecode(input) ?? "⚠︎ invalid percent-encoding")
                              : ToolsService.urlEncode(input)
        case .jwt:
            return ToolsService.decodeJWT(input) ?? "⚠︎ invalid JWT"
        case .sha256:
            return ToolsService.sha256(input)
        case .json:
            return ToolsService.prettyJSON(input) ?? "⚠︎ invalid JSON"
        default:
            return ""
        }
    }

    private var placeholder: String {
        switch tool {
        case .jwt: return "Paste JWT…"
        case .json: return "Paste JSON…"
        default: return "Text…"
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: Theme.s6) {
                let output = self.output   // computed once per render (it hashes / parses the input)
                if tool.hasDecodeMode {
                    Picker("", selection: $decodeMode) {
                        Text("Encode").tag(false)
                        Text("Decode").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                TextField(placeholder, text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...(tool == .json ? 6 : 3))
                    .font(Theme.mono(11))
                if !output.isEmpty {
                    ScrollView {
                        Text(output)
                            .font(Theme.mono(10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    HStack {
                        Spacer()
                        CopyButton(isCopied: vm.copiedKey == tool.id) { vm.copy(output, key: tool.id) }
                    }
                }
            }
            .padding(.top, Theme.s4)
        } label: {
            HStack(spacing: Theme.s10) {
                Image(systemName: tool.icon).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title).font(Theme.rowTitle)
                    Text(tool.subtitle).font(Theme.rowSubtitle).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.s8)
    }
}

private struct MaintenanceRow: View {
    let tool: DevTool
    @ObservedObject var vm: ToolsViewModel
    @State private var confirming = false
    @State private var hovering = false

    private var status: ToolsViewModel.Status { vm.status[tool.id] ?? .idle }

    var body: some View {
        HStack(spacing: Theme.s10) {
            Image(systemName: tool.icon).frame(width: 20)
                .foregroundStyle(tool.isDestructive ? Color.red : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(Theme.rowTitle)
                Text(tool.subtitle).font(Theme.rowSubtitle).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Theme.s8)
            statusIcon
            Button("Run") {
                if tool.isDestructive { confirming = true }
                else { Task { await vm.runMaintenance(tool) } }
            }
            .controlSize(.small)
            .confirmationDialog("Run “\(tool.title)”?", isPresented: $confirming) {
                Button(tool.title, role: .destructive) { Task { await vm.runMaintenance(tool) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(tool.subtitle)
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
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .idle: EmptyView()
        }
    }
}
