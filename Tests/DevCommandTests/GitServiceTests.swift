import XCTest
@testable import DevCommand

final class GitServiceTests: XCTestCase {
    func testBranchNameFromHEAD() {
        XCTAssertEqual(GitService.branchName(fromHEAD: "ref: refs/heads/main\n"), "main")
        XCTAssertEqual(GitService.branchName(fromHEAD: "ref: refs/heads/feature/login-form\n"), "feature/login-form")
        // Detached HEAD is a bare commit hash: show the short form.
        XCTAssertEqual(GitService.branchName(fromHEAD: "8ece8185ac8b3feea7478db2570edbf432dbcafa\n"), "8ece818")
        XCTAssertNil(GitService.branchName(fromHEAD: ""))
        XCTAssertNil(GitService.branchName(fromHEAD: "ref: refs/heads/"))
        XCTAssertNil(GitService.branchName(fromHEAD: "not a head file"))
    }

    func testOriginURLFromConfig() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/other/app.git
        [remote "origin"]
        \turl = git@github.com:me/app.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        """
        XCTAssertEqual(GitService.originURL(fromConfig: config), "git@github.com:me/app.git")
        XCTAssertNil(GitService.originURL(fromConfig: "[core]\n\tbare = false\n"))
    }

    func testWebURLFromCommonRemoteForms() {
        let expected = URL(string: "https://github.com/me/app")
        XCTAssertEqual(GitService.webURL(fromRemote: "git@github.com:me/app.git"), expected)
        XCTAssertEqual(GitService.webURL(fromRemote: "https://github.com/me/app.git"), expected)
        XCTAssertEqual(GitService.webURL(fromRemote: "https://github.com/me/app"), expected)
        XCTAssertEqual(GitService.webURL(fromRemote: "ssh://git@github.com/me/app.git"), expected)
        XCTAssertEqual(GitService.webURL(fromRemote: "ssh://git@github.com:22/me/app.git"), expected)
        XCTAssertEqual(GitService.webURL(fromRemote: "git@gitlab.com:group/sub/app.git"),
                       URL(string: "https://gitlab.com/group/sub/app"))
    }

    /// A token embedded in the remote must never end up in the URL we hand to the browser.
    func testWebURLDropsCredentials() {
        let url = GitService.webURL(fromRemote: "https://me:ghp_secret123@github.com/me/app.git")
        XCTAssertEqual(url, URL(string: "https://github.com/me/app"))
        XCTAssertFalse(url?.absoluteString.contains("ghp_secret123") ?? true)
    }

    func testWebURLRejectsLocalAndOddRemotes() {
        XCTAssertNil(GitService.webURL(fromRemote: "/Users/me/repos/app.git"))
        XCTAssertNil(GitService.webURL(fromRemote: "../app"))
        XCTAssertNil(GitService.webURL(fromRemote: "file:///Users/me/app.git"))
        XCTAssertNil(GitService.webURL(fromRemote: "javascript://github.com/x"))
        XCTAssertNil(GitService.webURL(fromRemote: "git@github.com:"))
        XCTAssertNil(GitService.webURL(fromRemote: ""))
    }

    func testHostLabel() {
        XCTAssertEqual(GitService.hostLabel(for: URL(string: "https://github.com/me/app")!), "GitHub")
        XCTAssertEqual(GitService.hostLabel(for: URL(string: "https://gitlab.com/me/app")!), "GitLab")
        XCTAssertEqual(GitService.hostLabel(for: URL(string: "https://git.example.com/me/app")!), "git.example.com")
    }

    // MARK: Reading a repository from disk

    private func makeTempDir() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("devcommand-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ text: String, to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testInfoReadsBranchAndRemoteFromDotGit() throws {
        let repo = try makeTempDir()
        try write("ref: refs/heads/develop\n", to: repo + "/.git/HEAD")
        try write("[remote \"origin\"]\n\turl = git@github.com:me/app.git\n", to: repo + "/.git/config")
        let info = GitService.info(forRepoAt: repo)
        XCTAssertEqual(info?.branch, "develop")
        XCTAssertEqual(info?.webURL, URL(string: "https://github.com/me/app"))
    }

    func testInfoIsNilOutsideARepository() throws {
        XCTAssertNil(GitService.info(forRepoAt: try makeTempDir()))
    }

    /// A linked worktree has a `.git` *file* pointing at its own git dir (own HEAD), which in
    /// turn points back at the main repository for the shared config.
    func testInfoFollowsWorktreePointers() throws {
        let root = try makeTempDir()
        let main = root + "/main", worktree = root + "/wt"
        try write("ref: refs/heads/main\n", to: main + "/.git/HEAD")
        try write("[remote \"origin\"]\n\turl = https://github.com/me/app.git\n", to: main + "/.git/config")
        try write("ref: refs/heads/hotfix\n", to: main + "/.git/worktrees/wt/HEAD")
        try write("../..\n", to: main + "/.git/worktrees/wt/commondir")
        try write("gitdir: \(main)/.git/worktrees/wt\n", to: worktree + "/.git")

        let info = GitService.info(forRepoAt: worktree)
        XCTAssertEqual(info?.branch, "hotfix")
        XCTAssertEqual(info?.webURL, URL(string: "https://github.com/me/app"))
    }
}
