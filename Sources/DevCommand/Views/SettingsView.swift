import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            PanelsSettings().tabItem { Label("Panels", systemImage: "square.grid.2x2") }
            ToolsSettings().tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 460)
        .tint(Theme.accent)
    }
}

private struct PanelsSettings: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        List {
            Section {
                ForEach(settings.orderedSections()) { section in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Label(section.rawValue, systemImage: section.icon)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.sectionEnabled(section) },
                            set: { settings.toggleSection(section, $0) }
                        )).labelsHidden()
                    }
                }
                .onMove { settings.moveSections(from: $0, to: $1) }
            } header: {
                Text("Drag to reorder · toggle to show or hide")
            }
        }
    }
}

private struct ToolsSettings: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        List {
            Section {
                ForEach(settings.orderedTools()) { tool in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.title)
                                Text(tool.subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: tool.icon)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.toolEnabled(tool) },
                            set: { settings.toggleTool(tool, $0) }
                        )).labelsHidden()
                    }
                }
                .onMove { settings.moveTools(from: $0, to: $1) }
            } header: {
                Text("Drag to reorder · toggle to show or hide")
            }
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmingUninstall = false

    /// Read from the bundle's Info.plist so it can't drift from the actual build.
    /// Falls back to "dev" when run via `swift run` (no bundle).
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "dev"
        }
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }
            Section("Privacy") {
                Toggle("Show public IP", isOn: $settings.showPublicIP)
                Text("Off by default: DevCommand makes no outbound request until you ask. Leave it off "
                   + "and reveal your IP on demand by clicking the Public chip, or turn it on to always show it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dev folders") {
                ForEach(settings.devRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text((root as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button {
                            settings.removeRoot(root)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this folder")
                        .disabled(settings.devRoots.count == 1)
                    }
                }
                Button {
                    pickFolders()
                } label: {
                    Label("Add folder…", systemImage: "folder.badge.plus")
                }
            }
            Section("Apps") {
                LabeledContent("Editor") { EditorPicker() }
                LabeledContent("Terminal") { TerminalPicker() }
            }
            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
                Button("Check for Updates…") { update() }
                Button("Uninstall DevCommand…", role: .destructive) { confirmingUninstall = true }
                Text("A light, native menu-bar cockpit for React / React Native / web / backend / iOS / tvOS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .confirmationDialog("Uninstall DevCommand?", isPresented: $confirmingUninstall) {
            Button("Move to Trash & Quit", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes DevCommand.app, its preferences, and the launch-at-login item.")
        }
    }

    /// From a source checkout: pull + reinstall in Terminal (it relaunches the new build).
    /// Otherwise open the Releases page.
    private func update() {
        if let repo = Preferences.sourceRepo,
           FileManager.default.fileExists(atPath: (repo as NSString).appendingPathComponent(".git")) {
            Task { await Launch.inTerminal("git pull --ff-only && zsh scripts/install.sh",
                                           cwd: repo, title: "DevCommand update") }
        } else if let url = URL(string: "https://github.com/eno-dev/DevCommand/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// One-click clean removal: drop the login item, wipe prefs, move the app to the Trash, quit.
    private func uninstall() {
        LoginItem.setEnabled(false)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        NSApp.terminate(nil)
    }

    private func pickFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: settings.devRoots.first ?? NSHomeDirectory())
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK {
            for url in panel.urls { settings.addRoot(url.path) }
        }
    }
}

/// A dropdown of installed editors, each shown with its real app icon.
private struct EditorPicker: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var apps: [EditorApp] = []

    var body: some View {
        Menu {
            ForEach(apps) { app in
                Button {
                    settings.editorApp = app.name
                } label: {
                    Image(nsImage: EditorApps.icon(forName: app.name))
                    Text(app.name)
                }
            }
            Divider()
            Button("Choose…") { choose() }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: EditorApps.icon(forName: settings.editorApp))
                Text(settings.editorApp.isEmpty ? "Choose…" : settings.editorApp)
            }
        }
        .fixedSize()
        .onAppear(perform: reload)
    }

    private func reload() {
        var found = EditorApps.installed()
        if !settings.editorApp.isEmpty, !found.contains(where: { $0.name == settings.editorApp }) {
            let path = EditorApps.path(forName: settings.editorApp) ?? settings.editorApp
            found.insert(EditorApp(id: path, name: settings.editorApp), at: 0)
        }
        apps = found
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use Editor"
        if panel.runModal() == .OK, let url = panel.url {
            settings.editorApp = url.deletingPathExtension().lastPathComponent
            reload()
        }
    }
}

/// A dropdown of installed terminals, each shown with its real app icon. Defaults to Terminal.
private struct TerminalPicker: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var apps: [TerminalApp] = []

    var body: some View {
        Menu {
            ForEach(apps) { app in
                Button {
                    settings.terminalApp = app.name
                } label: {
                    Image(nsImage: TerminalApps.icon(forName: app.name))
                    Text(app.name)
                }
            }
            Divider()
            Button("Choose…") { choose() }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: TerminalApps.icon(forName: settings.terminalApp))
                Text(settings.terminalApp.isEmpty ? "Terminal" : settings.terminalApp)
            }
        }
        .fixedSize()
        .onAppear(perform: reload)
    }

    private func reload() {
        var found = TerminalApps.installed()
        if !settings.terminalApp.isEmpty, !found.contains(where: { $0.name == settings.terminalApp }) {
            let path = TerminalApps.path(forName: settings.terminalApp) ?? settings.terminalApp
            found.insert(TerminalApp(id: path, name: settings.terminalApp), at: 0)
        }
        apps = found
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Use Terminal"
        if panel.runModal() == .OK, let url = panel.url {
            settings.terminalApp = url.deletingPathExtension().lastPathComponent
            reload()
        }
    }
}
