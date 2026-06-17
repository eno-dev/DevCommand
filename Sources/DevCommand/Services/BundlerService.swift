import Foundation

enum BundlerService {
    /// Ports a Metro/Expo/web dev server typically listens on.
    static let bundlerPorts: Set<Int> = [8081, 8082, 19000, 19001, 19006, 3000, 3001, 4000, 4321, 5173, 8080]

    /// JS runtimes that host a dev server (Metro/Expo/Vite/Next/…).
    static let runtimes = ["node", "bun", "deno"]

    /// Find running dev servers by cross-referencing listening ports with their process cwd.
    static func active() async -> [ActiveBundler] {
        let ports = await PortService.listening()
        let candidates = ports.filter { port in
            bundlerPorts.contains(port.port)
                && runtimes.contains { port.command.lowercased().contains($0) }
        }

        let byPID = Dictionary(grouping: candidates, by: { $0.pid })
        let cwds = await cwds(ofPIDs: Array(byPID.keys))   // one lsof for all PIDs, not N
        let result = byPID.map { pid, group -> ActiveBundler in
            let port = group.map(\.port).min() ?? group[0].port
            let dir = cwds[pid] ?? ""
            let name = dir.isEmpty ? "node" : (dir as NSString).lastPathComponent
            return ActiveBundler(pid: pid, port: port, cwd: dir, projectName: name)
        }
        return result.sorted { $0.port < $1.port }
    }

    /// Resolve several processes' working directories in a single `lsof` call.
    static func cwds(ofPIDs pids: [Int]) async -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let result = await Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fpn"])
        return parseCwds(result.stdout)
    }

    /// Parse `lsof -Fpn`: each process emits `p<pid>` then `n<cwd>`, so tag each cwd to its pid.
    static func parseCwds(_ output: String) -> [Int: String] {
        var map: [Int: String] = [:]
        var current = 0
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            if tag == "p" {
                current = Int(value) ?? 0
            } else if tag == "n", current != 0, map[current] == nil {
                map[current] = value
            }
        }
        return map
    }

    /// Start a dev server in Terminal so its logs are visible and interruptible.
    static func start(_ project: DevProject, clear: Bool) async {
        let pm = project.packageManager
        let command: String
        switch project.kind {
        case .expo:
            command = "\(pm.exec) expo start" + (clear ? " --clear" : "")
        case .reactNative:
            command = "\(pm.exec) react-native start" + (clear ? " --reset-cache" : "")
        case .web:
            command = "\(pm.run) \(project.devScript ?? "dev")"
        case .nativeApple:
            return
        }
        await Launch.inTerminal(command, cwd: project.path, title: project.name, key: project.path)
    }

    @discardableResult
    static func stop(pid: Int, force: Bool = false) async -> ShellResult {
        await PortService.kill(pid: pid, force: force)
    }
}
