import Foundation

/// What a project row shows about its repository.
struct GitInfo: Equatable, Sendable {
    var branch: String?   // current branch, or a short commit hash when HEAD is detached
    var webURL: URL?      // the origin remote as a browsable https URL, when it has one
}

/// Reads repository state straight from the files under `.git`: a couple of small reads per
/// project and no `git` subprocess, so it is cheap enough to refresh every time the panel opens.
enum GitService {
    /// Git info for each path that is a repository, keyed by path. Runs off the main thread.
    static func infos(forPaths paths: [String]) async -> [String: GitInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: [String: GitInfo] = [:]
                for path in paths { result[path] = info(forRepoAt: path) }
                continuation.resume(returning: result)
            }
        }
    }

    static func info(forRepoAt path: String, fm: FileManager = .default) -> GitInfo? {
        guard let gitDir = gitDirectory(for: path, fm: fm) else { return nil }
        let head = try? String(contentsOfFile: (gitDir as NSString).appendingPathComponent("HEAD"), encoding: .utf8)
        let configPath = (commonDirectory(for: gitDir) as NSString).appendingPathComponent("config")
        let config = try? String(contentsOfFile: configPath, encoding: .utf8)
        return GitInfo(branch: head.flatMap(branchName(fromHEAD:)),
                       webURL: config.flatMap(originURL(fromConfig:)).flatMap(webURL(fromRemote:)))
    }

    /// Where the repository's git data lives: `.git` itself, or the directory a `.git` *file*
    /// points at (that is how linked worktrees and submodules are laid out).
    private static func gitDirectory(for path: String, fm: FileManager) -> String? {
        let dotGit = (path as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        guard let pointer = try? String(contentsOfFile: dotGit, encoding: .utf8),
              let target = value(after: "gitdir:", in: pointer) else { return nil }
        return resolve(target, relativeTo: path)
    }

    /// A linked worktree keeps its own HEAD but shares `config` with the main repository,
    /// which a `commondir` file points back to.
    private static func commonDirectory(for gitDir: String) -> String {
        let pointer = (gitDir as NSString).appendingPathComponent("commondir")
        guard let text = try? String(contentsOfFile: pointer, encoding: .utf8) else { return gitDir }
        let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? gitDir : resolve(target, relativeTo: gitDir)
    }

    private static func resolve(_ target: String, relativeTo base: String) -> String {
        target.hasPrefix("/") ? target : ((base as NSString).appendingPathComponent(target) as NSString).standardizingPath
    }

    private static func value(after prefix: String, in text: String) -> String? {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: Pure parsing (unit-tested)

    /// `ref: refs/heads/feature/x` -> `feature/x`; a bare commit hash (detached HEAD) -> its
    /// first 7 characters.
    static func branchName(fromHEAD head: String) -> String? {
        let text = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        if text.hasPrefix(refPrefix) {
            let name = String(text.dropFirst(refPrefix.count))
            return name.isEmpty ? nil : name
        }
        guard text.count >= 7, text.allSatisfy(\.isHexDigit) else { return nil }
        return String(text.prefix(7))
    }

    /// The `url` of `[remote "origin"]` in a git config file.
    static func originURL(fromConfig config: String) -> String? {
        var inOrigin = false
        for rawLine in config.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "") == "[remote\"origin\"]"
            } else if inOrigin, let equals = line.firstIndex(of: "="),
                      line[..<equals].trimmingCharacters(in: .whitespaces) == "url" {
                let url = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                return url.isEmpty ? nil : url
            }
        }
        return nil
    }

    /// Turn a git remote into the https page for it: `git@github.com:me/app.git`,
    /// `ssh://git@github.com/me/app.git` and `https://github.com/me/app.git` all become
    /// `https://github.com/me/app`. Returns nil for local-path remotes and anything unparseable.
    /// The result is always https with no user or password, so a token embedded in the remote
    /// never reaches the browser.
    static func webURL(fromRemote remote: String) -> URL? {
        let text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        var host: String
        var path: String

        if text.contains("://") {
            guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
                  ["https", "http", "ssh", "git"].contains(scheme), let parsedHost = parts.host else { return nil }
            host = parsedHost
            path = parts.path
        } else if let at = text.firstIndex(of: "@"), let colon = text[at...].firstIndex(of: ":") {
            // scp-style: user@host:owner/repo.git
            host = String(text[text.index(after: at)..<colon])
            path = "/" + String(text[text.index(after: colon)...])
        } else {
            return nil
        }

        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let hostIsPlain = !host.isEmpty && host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        guard hostIsPlain, path.count > 1 else { return nil }

        var result = URLComponents()
        result.scheme = "https"
        result.host = host.lowercased()
        result.path = path
        return result.url
    }

    /// A short name for the hosting service, for the "Open on …" menu item.
    static func hostLabel(for url: URL) -> String {
        switch url.host ?? "" {
        case "github.com": return "GitHub"
        case "gitlab.com": return "GitLab"
        case "bitbucket.org": return "Bitbucket"
        case let host: return host
        }
    }
}
