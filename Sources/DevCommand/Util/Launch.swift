import Foundation

/// In-memory map of project key → the Terminal window id DevCommand opened for it. Lets a later
/// "show terminal" raise *exactly* that window, even after the running program rewrites its
/// title (Vite, etc. do), which makes title-matching alone unreliable.
actor TerminalRegistry {
    static let shared = TerminalRegistry()
    private var byKey: [String: Int] = [:]
    func set(_ id: Int, for key: String) { byKey[key] = id }
    func id(for key: String) -> Int? { byKey[key] }
}

/// Helpers for launching external processes the user should *see* — long-running
/// builds open in Terminal so progress is visible, rather than being swallowed.
enum Launch {
    /// Open a new terminal window running `command` in `cwd`.
    ///
    /// Terminal and iTerm get the command *directly* via AppleScript (`do script` / `write text`),
    /// so there's no executable file for the terminal's "OK to run this script?" guard to catch —
    /// and it runs in an interactive login shell, so `~/.zshrc` (where many devs put their
    /// nvm/fnm/volta hook) is sourced. Other terminals fall back to a throwaway `.command` file,
    /// which is universal but trips that prompt. If the AppleScript path is blocked (Automation
    /// permission denied) we fall back too, so the command always runs.
    /// `key` (a project path) ties the opened window to a project, so showTerminal/hideTerminal
    /// can later raise that exact window.
    static func inTerminal(_ command: String, cwd: String, title: String? = nil, key: String? = nil) async {
        let line = terminalCommandLine(command, cwd: cwd, title: title)
        let customTitle = title.map { "DevCommand • \($0)" }
        switch Preferences.terminalApp {
        case "Terminal":
            if let id = await terminalDoScript(line, customTitle: customTitle) {
                if let key { await TerminalRegistry.shared.set(id, for: key) }
                return
            }
        case "iTerm", "iTerm2":
            if await runAppleScript(itermWriteText(line)).ok { return }
        default:
            break
        }
        await runViaCommandFile(line)
    }

    /// The one-line shell command shared by both launch paths: cd into the project, tag the window
    /// title (OSC 0, so showTerminal/hideTerminal can find it later), then run the command.
    private static func terminalCommandLine(_ command: String, cwd: String, title: String?) -> String {
        let titlePart = title.map { "printf '\\033]0;%s\\007' \(("DevCommand • " + $0).singleQuoted); " } ?? ""
        return "cd \(cwd.singleQuoted); \(titlePart)echo \"▶ DevCommand → running in $(pwd)\"; \(command)"
    }

    /// Run `line` in a new Terminal window, give it a stable custom title, and return that
    /// window's id (so we can later raise exactly it). Returns nil if scripting is blocked,
    /// so the caller can fall back to the universal `.command` path.
    private static func terminalDoScript(_ line: String, customTitle: String?) async -> Int? {
        let titleLine = customTitle.map {
            "\n    set custom title of (selected tab of front window) to \"\(appleScriptEscaped($0))\""
        } ?? ""
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscaped(line))"\(titleLine)
            return id of front window
        end tell
        """
        let result = await runAppleScript(script)
        guard result.ok else { return nil }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func itermWriteText(_ line: String) -> String {
        """
        tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window to write text "\(appleScriptEscaped(line))"
        end tell
        """
    }

    /// Universal fallback: write the command to a throwaway executable `.command` and open it in the
    /// chosen terminal. `-l` = login shell so version managers initialise. We strip the quarantine
    /// flag so a downloaded build doesn't stack Gatekeeper's prompt on top of the terminal's.
    private static func runViaCommandFile(_ line: String) async {
        let file = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("devcommand-\(UUID().uuidString).command")
        let script = "#!/bin/zsh -l\n\(line)\n"
        do {
            try script.write(toFile: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file)
            _ = await Shell.run("/usr/bin/xattr", ["-d", "com.apple.quarantine", file])
            let result = await Shell.run("/usr/bin/open", ["-a", Preferences.terminalApp, file])
            if !result.ok { _ = await Shell.run("/usr/bin/open", [file]) }
        } catch {
            NSLog("DevCommand: failed to launch terminal command: \(error.localizedDescription)")
        }
    }

    /// Open a file/folder with the default app (e.g. an .xcworkspace in Xcode, a folder in Finder).
    static func open(_ path: String) async {
        _ = await Shell.run("/usr/bin/open", [path])
    }

    /// Open a path with a specific app by name (e.g. "Cursor", "Visual Studio Code").
    static func openWith(app: String, path: String) async {
        _ = await Shell.run("/usr/bin/open", ["-a", app, path])
    }

    /// Open the user's chosen terminal at `path` (new window). Falls back to Terminal.app.
    static func terminal(at path: String) async {
        let result = await Shell.run("/usr/bin/open", ["-a", Preferences.terminalApp, path])
        if !result.ok { _ = await Shell.run("/usr/bin/open", ["-a", "Terminal", path]) }
    }

    /// Reveal (and select) a file or folder in Finder — works for hidden dotfiles too.
    static func reveal(_ path: String) async {
        _ = await Shell.run("/usr/bin/open", ["-R", path])
    }

    // MARK: Terminal window control

    /// Bring the exact terminal window DevCommand opened for `key` to the front. Uses the captured
    /// window id (precise — survives the program rewriting its title); falls back to title
    /// matching only when no id was recorded. Needs Automation permission.
    static func showTerminal(key: String, title: String) async {
        let marker = "DevCommand • \(title)"
        switch Preferences.terminalApp {
        case "Terminal":
            if let id = await TerminalRegistry.shared.id(for: key) {
                await runAppleScript(terminalByID(id, raise: true))
            } else {
                await runAppleScript(terminalScript(marker: marker, raise: true))
            }
        case "iTerm", "iTerm2":
            await runAppleScript(itermShowScript(marker: marker))
        default:
            _ = await Shell.run("/usr/bin/open", ["-a", Preferences.terminalApp])
        }
    }

    /// Hide (minimise) the exact terminal window DevCommand opened for `key`.
    static func hideTerminal(key: String, title: String) async {
        let marker = "DevCommand • \(title)"
        switch Preferences.terminalApp {
        case "Terminal":
            if let id = await TerminalRegistry.shared.id(for: key) {
                await runAppleScript(terminalByID(id, raise: false))
            } else {
                await runAppleScript(terminalScript(marker: marker, raise: false))
            }
        default:
            let app = appleScriptEscaped(Preferences.terminalApp)
            await runAppleScript("tell application \"System Events\" to set visible of (first process whose name is \"\(app)\") to false")
        }
    }

    /// Raise or minimise a Terminal window by its id. `try` guards the case where the user
    /// already closed it.
    private static func terminalByID(_ id: Int, raise: Bool) -> String {
        if raise {
            return """
            tell application "Terminal"
                activate
                try
                    set miniaturized of window id \(id) to false
                    set index of window id \(id) to 1
                end try
            end tell
            """
        }
        return """
        tell application "Terminal"
            try
                set miniaturized of window id \(id) to true
            end try
        end tell
        """
    }

    @discardableResult
    private static func runAppleScript(_ source: String) async -> ShellResult {
        await Shell.run("/usr/bin/osascript", ["-e", source])
    }

    private static func appleScriptEscaped(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func terminalScript(marker: String, raise: Bool) -> String {
        let m = appleScriptEscaped(marker)
        if raise {
            return """
            tell application "Terminal"
                activate
                repeat with w in windows
                    if name of w contains "\(m)" then
                        set miniaturized of w to false
                        set index of w to 1
                        exit repeat
                    end if
                end repeat
            end tell
            """
        }
        return """
        tell application "Terminal"
            repeat with w in windows
                if name of w contains "\(m)" then
                    set miniaturized of w to true
                    exit repeat
                end if
            end repeat
        end tell
        """
    }

    private static func itermShowScript(marker: String) -> String {
        let m = appleScriptEscaped(marker)
        return """
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if name of s contains "\(m)" then
                            select w
                            select t
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }
}

extension String {
    /// Single-quote a string for safe embedding inside a shell command.
    var singleQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
