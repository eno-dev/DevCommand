import XCTest
@testable import DevCommand

/// The type-to-filter matching used by the Ports and Projects panels, and the port-owner naming.
final class FilterTests: XCTestCase {
    private func port(_ number: Int, pid: Int = 100, command: String = "node") -> ListeningPort {
        ListeningPort(port: number, pid: pid, command: command, user: "me", address: "*")
    }

    private func project(_ name: String, kind: ProjectKind = .web, framework: String? = nil) -> DevProject {
        DevProject(name: name, path: "/dev/\(name)", kind: kind, hasIOS: false, hasPods: false,
                   supportsTV: false, framework: framework, devScript: "dev", bundleID: nil,
                   packageManager: .npm, scripts: [])
    }

    func testPortMatchesNumberCommandLabelAndOwner() {
        let metro = port(8081)
        XCTAssertTrue(metro.matches("808"))
        XCTAssertTrue(metro.matches("NODE"))                     // case-insensitive
        XCTAssertTrue(metro.matches("metro"))                    // the dev label for 8081
        XCTAssertTrue(metro.matches("shop", owner: "shop-app"))
        XCTAssertFalse(metro.matches("shop"))                    // no owner known
        XCTAssertFalse(metro.matches("postgres"))
    }

    /// PIDs are left out on purpose: their digits collide with port numbers ("80" would match
    /// pid 18012), which makes a port search noisy.
    func testPortFilterIgnoresPID() {
        XCTAssertFalse(port(3000, pid: 8081).matches("8081"))
    }

    func testHostsProjectOnlyForLanguageRuntimes() {
        XCTAssertTrue(port(3000, command: "node").hostsProject)
        XCTAssertTrue(port(8000, command: "Python").hostsProject)
        XCTAssertTrue(port(3000, command: "bun").hostsProject)
        XCTAssertFalse(port(5432, command: "postgres").hostsProject)
        XCTAssertFalse(port(27017, command: "mongod").hostsProject)
        XCTAssertFalse(port(7000, command: "ControlCe").hostsProject)
    }

    func testProjectNameForCwd() {
        XCTAssertEqual(PortCatalog.projectName(forCwd: "/Users/me/Dev/shop-app", home: "/Users/me"), "shop-app")
        XCTAssertEqual(PortCatalog.projectName(forCwd: "/Users/me/Dev/mono/apps/web", home: "/Users/me"), "web")
        XCTAssertNil(PortCatalog.projectName(forCwd: "", home: "/Users/me"))
        XCTAssertNil(PortCatalog.projectName(forCwd: "/", home: "/Users/me"))
        XCTAssertNil(PortCatalog.projectName(forCwd: "/Users/me", home: "/Users/me"))   // a daemon run from ~
    }

    func testProjectMatchesNameAndKindLabel() {
        let shop = project("shop-app", framework: "Next.js")
        XCTAssertTrue(shop.matches("SHOP"))
        XCTAssertTrue(shop.matches("next"))
        XCTAssertFalse(shop.matches("expo"))
        XCTAssertTrue(project("mobile", kind: .expo).matches("expo"))   // falls back to the kind name
    }

    func testOrphanServerMatchesFolderLabelAndPort() {
        let server = ActiveBundler(pid: 1, port: 5173, cwd: "/tmp/sandbox", projectName: "sandbox")
        XCTAssertTrue(server.matches("sand"))
        XCTAssertTrue(server.matches("vite"))
        XCTAssertTrue(server.matches("5173"))
        XCTAssertFalse(server.matches("metro"))
    }
}
