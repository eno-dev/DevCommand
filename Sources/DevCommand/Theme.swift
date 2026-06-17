import SwiftUI

/// Central design tokens — one source of truth for the app's visual language.
enum Theme {
    /// Brand accent: a warm amber, used sparingly — tags, the app glyph, and interactive controls.
    static let accent = Color(.sRGB, red: 0.95, green: 0.66, blue: 0.24, opacity: 1)

    /// Storybook brand pink (#FF4785) — used for the Storybook port badge.
    static let storybook = Color(.sRGB, red: 1.0, green: 0.278, blue: 0.522, opacity: 1)

    // Surfaces
    static let rowHover = Color.primary.opacity(0.08)
    static let hairline = Color.primary.opacity(0.11)
    static let chip = Color.primary.opacity(0.08)

    // Spacing scale
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s14: CGFloat = 14
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20

    // Layout
    /// The one horizontal content inset — header bars, the section picker, section labels,
    /// and every list row use this so all left edges line up down the panel.
    static let gutter: CGFloat = s16
    /// Vertical padding inside a list row (comfortable tap target in a dense popover).
    static let rowV: CGFloat = 11

    // Typography roles — keep rows reading consistently across panels.
    /// Primary line of a list row (project / sim / device / tool / check name).
    static let rowTitle = Font.callout.weight(.medium)
    /// Secondary line of a list row (status, path, metadata). Pair with `.secondary`.
    static let rowSubtitle = Font.caption

    // Mono fonts for numbers / code-ish values
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Standard list-row insets: the shared horizontal gutter + comfortable vertical rhythm.
    /// Use on every panel row so they share one left edge and one height.
    func rowInsets() -> some View {
        padding(.horizontal, Theme.gutter).padding(.vertical, Theme.rowV)
    }
}

/// Secondary icon button that lifts to primary with a soft background on hover.
struct SubtleIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }
    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .padding(5)
                .background(hovering ? Theme.rowHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { hovering = $0 }
                .opacity(configuration.isPressed ? 0.55 : 1)
                .animation(.easeOut(duration: 0.10), value: hovering)
        }
    }
}

/// Uppercase, tracked, tertiary section heading.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.s12)
            .padding(.bottom, Theme.s4)
    }
}

/// Small capsule tag (dev-port labels, project kinds, …).
struct Pill: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color = Theme.accent) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Status indicator dot with a soft glow when active.
struct StatusDot: View {
    let active: Bool
    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 7, height: 7)
            .shadow(color: active ? Color.green.opacity(0.6) : .clear, radius: 3)
    }
}

/// Dismissable inline error strip — used to surface a failed action (kill, boot, stop…)
/// instead of letting it fail silently. Tap anywhere on it to dismiss.
struct InlineBanner: View {
    let text: String
    var onClose: () -> Void = {}

    var body: some View {
        HStack(spacing: Theme.s6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
            Text(text).font(.caption).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.s4)
            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, Theme.gutter).padding(.vertical, Theme.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .help("Dismiss")
    }
}

extension View {
    /// Presents a platform-mismatch as a dialog showing the full message (no truncation),
    /// with a one-click in-app fix when a corrective command exists. `onFix`/`onCopy` fire
    /// for the presented `RunMismatch`.
    func runMismatchAlert(_ mismatch: Binding<RunMismatch?>,
                          onFix: @escaping (RunMismatch) -> Void,
                          onCopy: @escaping (RunMismatch) -> Void) -> some View {
        alert("Can’t run here",
              isPresented: Binding(get: { mismatch.wrappedValue != nil },
                                   set: { if !$0 { mismatch.wrappedValue = nil } }),
              presenting: mismatch.wrappedValue) { m in
            if m.fix != nil {
                Button("Prebuild & Run") { onFix(m) }
                Button("Copy Command") { onCopy(m) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { m in
            Text(m.message)
        }
    }
}

/// Centered empty / zero-state.
struct EmptyStateView<Action: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: Theme.s8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(title).font(.callout).foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

extension EmptyStateView where Action == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}
