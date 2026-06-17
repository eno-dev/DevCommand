import XCTest
@testable import DevCommand

final class PortServiceTests: XCTestCase {
    func testParsesProcessesAndPorts() {
        let output = """
        p123
        cnode
        Lme
        n*:8081
        p456
        cpostgres
        Lme
        n127.0.0.1:5432
        n[::1]:5432
        """
        let ports = PortService.parse(output)
        XCTAssertEqual(ports.count, 2)

        let metro = ports.first { $0.port == 8081 }
        XCTAssertEqual(metro?.pid, 123)
        XCTAssertEqual(metro?.command, "node")
        XCTAssertEqual(metro?.address, "*")
        XCTAssertEqual(metro?.devLabel, "Metro")
        XCTAssertTrue(metro?.isDev ?? false)

        let pg = ports.first { $0.port == 5432 }
        XCTAssertEqual(pg?.address, "127.0.0.1")   // IPv6 dup must not clobber the IPv4 address
        XCTAssertTrue(pg?.isLoopback ?? false)
        XCTAssertEqual(pg?.devLabel, "Postgres")
    }

    func testMergesDualStackToBroadestAddress() {
        // Same pid+port on 127.0.0.1 and * should collapse to one entry bound to "*".
        let output = "p10\ncnode\nLme\nn127.0.0.1:3000\nn*:3000"
        let ports = PortService.parse(output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports.first?.address, "*")
        XCTAssertFalse(ports.first?.isLoopback ?? true)
    }

    func testStripsIPv6Brackets() {
        let output = "p7\ncnode\nLme\nn[::1]:9229"
        let ports = PortService.parse(output)
        XCTAssertEqual(ports.first?.address, "::1")
        XCTAssertTrue(ports.first?.isLoopback ?? false)
        XCTAssertEqual(ports.first?.devLabel, "Node debug")
    }

    func testDevPortsSortBeforeNonDev() {
        // 22 (ssh, non-dev) should sort after 8081 (Metro, dev) despite the lower number.
        let output = "p1\ncsshd\nLme\nn*:22\np2\ncnode\nLme\nn*:8081"
        let ports = PortService.parse(output)
        XCTAssertEqual(ports.first?.port, 8081)
        XCTAssertEqual(ports.last?.port, 22)
    }

    func testSystemAndHelperClassification() {
        XCTAssertTrue(ListeningPort(port: 1, pid: 1, command: "rapportd", user: "me", address: "*").isSystem)
        XCTAssertTrue(ListeningPort(port: 1, pid: 1, command: "Cursor Helper", user: "me", address: "*").isAppHelper)
        XCTAssertFalse(ListeningPort(port: 8081, pid: 1, command: "node", user: "me", address: "*").isSystem)
    }

    func testExpoSchemeOnlyForMetroExpoPorts() {
        XCTAssertTrue(ListeningPort(port: 8081, pid: 1, command: "node", user: "me", address: "*").supportsExpoScheme)
        XCTAssertTrue(ListeningPort(port: 19000, pid: 1, command: "node", user: "me", address: "*").supportsExpoScheme)
        XCTAssertFalse(ListeningPort(port: 5432, pid: 1, command: "postgres", user: "me", address: "*").supportsExpoScheme)
    }
}
