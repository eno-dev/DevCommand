import SwiftUI

/// Shared, persisted settings — which panels/tools are enabled, their order, plus general prefs.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var enabledSections: Set<String> {
        didSet { defaults.set(Array(enabledSections), forKey: Keys.sections) }
    }
    @Published var enabledTools: Set<String> {
        didSet { defaults.set(Array(enabledTools), forKey: Keys.tools) }
    }
    @Published var sectionOrder: [String] {
        didSet { defaults.set(sectionOrder, forKey: Keys.sectionOrder) }
    }
    @Published var toolOrder: [String] {
        didSet { defaults.set(toolOrder, forKey: Keys.toolOrder) }
    }
    @Published var devRoots: [String] {
        didSet { Preferences.devRoots = devRoots }
    }
    @Published var favoritePaths: [String] {
        didSet { Preferences.favoriteProjects = favoritePaths }
    }
    @Published var editorApp: String {
        didSet { Preferences.editorApp = editorApp }
    }
    @Published var terminalApp: String {
        didSet { Preferences.terminalApp = terminalApp }
    }
    @Published var showPublicIP: Bool {
        didSet { Preferences.showPublicIP = showPublicIP }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let sections = "enabledSections"
        static let tools = "enabledTools"
        static let sectionOrder = "sectionOrder"
        static let toolOrder = "toolOrder"
    }

    private init() {
        let allSections = DeckSection.allCases.map(\.rawValue)
        let allTools = DevTool.allCases.map(\.rawValue)
        enabledSections = Set((defaults.array(forKey: Keys.sections) as? [String]) ?? allSections)
        enabledTools = Set((defaults.array(forKey: Keys.tools) as? [String]) ?? allTools)
        sectionOrder = (defaults.array(forKey: Keys.sectionOrder) as? [String]) ?? allSections
        toolOrder = (defaults.array(forKey: Keys.toolOrder) as? [String]) ?? allTools
        devRoots = Preferences.devRoots
        favoritePaths = Preferences.favoriteProjects
        editorApp = Preferences.editorApp
        terminalApp = Preferences.terminalApp
        showPublicIP = Preferences.showPublicIP

        // Panels/tools added in a later version appear enabled by default.
        for section in DeckSection.allCases where !sectionOrder.contains(section.rawValue) {
            sectionOrder.append(section.rawValue)
            enabledSections.insert(section.rawValue)
        }
        for tool in DevTool.allCases where !toolOrder.contains(tool.rawValue) {
            toolOrder.append(tool.rawValue)
            enabledTools.insert(tool.rawValue)
        }
        // Property observers don't fire during init, so persist the reconciliation explicitly.
        defaults.set(sectionOrder, forKey: Keys.sectionOrder)
        defaults.set(toolOrder, forKey: Keys.toolOrder)
        defaults.set(Array(enabledSections), forKey: Keys.sections)
        defaults.set(Array(enabledTools), forKey: Keys.tools)
    }

    // MARK: Order (stored ids in user order; unknown ids dropped, new ones appended)

    func orderedSections() -> [DeckSection] {
        let known = sectionOrder.compactMap { DeckSection(rawValue: $0) }
        return known + DeckSection.allCases.filter { !known.contains($0) }
    }
    func orderedTools() -> [DevTool] {
        let known = toolOrder.compactMap { DevTool(rawValue: $0) }
        return known + DevTool.allCases.filter { !known.contains($0) }
    }
    func moveSections(from: IndexSet, to: Int) {
        var arr = orderedSections().map(\.rawValue)
        arr.move(fromOffsets: from, toOffset: to)
        sectionOrder = arr
    }
    func moveTools(from: IndexSet, to: Int) {
        var arr = orderedTools().map(\.rawValue)
        arr.move(fromOffsets: from, toOffset: to)
        toolOrder = arr
    }

    // MARK: Enabled

    func sectionEnabled(_ section: DeckSection) -> Bool { enabledSections.contains(section.rawValue) }
    func toggleSection(_ section: DeckSection, _ on: Bool) {
        if on { enabledSections.insert(section.rawValue) } else { enabledSections.remove(section.rawValue) }
    }
    func toolEnabled(_ tool: DevTool) -> Bool { enabledTools.contains(tool.rawValue) }
    func toggleTool(_ tool: DevTool, _ on: Bool) {
        if on { enabledTools.insert(tool.rawValue) } else { enabledTools.remove(tool.rawValue) }
    }

    // MARK: Dev folders

    func addRoot(_ path: String) {
        guard !devRoots.contains(path) else { return }
        devRoots.append(path)
    }
    func removeRoot(_ path: String) {
        devRoots.removeAll { $0 == path }
        if devRoots.isEmpty { devRoots = [Preferences.defaultDevRoot] }  // never leave it empty
    }

    // MARK: Favorites

    func isFavorite(_ path: String) -> Bool { favoritePaths.contains(path) }

    func toggleFavorite(_ path: String) {
        if let index = favoritePaths.firstIndex(of: path) { favoritePaths.remove(at: index) }
        else { favoritePaths.append(path) }
    }

    /// Move `path` to sit just before `target` in the favorites order (drag-to-reorder).
    func moveFavorite(_ path: String, before target: String) {
        guard path != target, let from = favoritePaths.firstIndex(of: path) else { return }
        favoritePaths.remove(at: from)
        if let to = favoritePaths.firstIndex(of: target) { favoritePaths.insert(path, at: to) }
        else { favoritePaths.append(path) }
    }
}
