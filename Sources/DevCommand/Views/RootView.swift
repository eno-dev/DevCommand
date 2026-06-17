import SwiftUI
import AppKit

enum DeckSection: String, CaseIterable, Identifiable {
    case ports = "Ports"
    case sims = "Sims"
    case projects = "Projects"
    case tools = "Tools"
    case doctor = "Doctor"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ports: return "bolt.horizontal"
        case .sims: return "iphone"
        case .projects: return "folder"
        case .tools: return "wrench.and.screwdriver"
        case .doctor: return "stethoscope"
        }
    }
}

struct RootView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.openSettings) private var openSettings
    @State private var section: DeckSection = .ports

    private var sections: [DeckSection] {
        settings.orderedSections().filter { settings.sectionEnabled($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Theme.hairline)
            NetworkBar()
            Divider().overlay(Theme.hairline)
            content
        }
        .frame(width: 400, height: 500)
        .background(backgroundWash)
        .tint(Theme.accent)
        .onAppear(perform: normalizeSection)
        .onChange(of: settings.enabledSections) { _, _ in normalizeSection() }
    }

    private var backgroundWash: some View {
        Color.clear
    }

    @ViewBuilder
    private var content: some View {
        let sections = self.sections
        if sections.isEmpty {
            EmptyStateView(icon: "square.dashed", title: "All panels are hidden") {
                SettingsLink { Text("Open Settings") }.font(.caption)
            }
        } else {
            Picker("", selection: $section) {
                ForEach(sections) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.s10)

            Divider().overlay(Theme.hairline)

            Group {
                switch (sections.contains(section) ? section : sections[0]) {
                case .ports: PortsView()
                case .sims: SimulatorsView()
                case .projects: ProjectsView()
                case .tools: ToolsView()
                case .doctor: DoctorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static let appLogo: NSImage? = Bundle.main.url(forResource: "Logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    private var headerBar: some View {
        HStack(spacing: Theme.s10) {
            Group {
                if let logo = Self.appLogo {
                    Image(nsImage: logo).resizable().interpolation(.high)
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.accent.opacity(0.16))
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text("DevCommand").font(.system(size: 14, weight: .semibold))
                Text("developer cockpit")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                // Standard behavior: close the dropdown, then open Settings up front.
                // A MenuBarExtra popover only auto-dismisses on an outside click, so we
                // close it explicitly — it's the key window while the gear is pressed.
                NSApp.keyWindow?.close()
                openSettings()
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
            }
            .buttonStyle(SubtleIconButtonStyle())
            .help("Settings — panels, tools, launch at login")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 14))
            }
            .buttonStyle(SubtleIconButtonStyle())
            .help("Quit DevCommand")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.s10)
    }

    private func normalizeSection() {
        if !sections.contains(section) { section = sections.first ?? .ports }
    }
}
