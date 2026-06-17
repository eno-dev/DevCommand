import XCTest
@testable import DevCommand

final class MiscModelTests: XCTestCase {
    func testIsPlausibleIP() {
        XCTAssertTrue(NetworkService.isPlausibleIP("192.168.1.5"))
        XCTAssertTrue(NetworkService.isPlausibleIP("10.0.0.1"))
        XCTAssertTrue(NetworkService.isPlausibleIP("fe80::1"))      // IPv6
        XCTAssertFalse(NetworkService.isPlausibleIP("hello"))
        XCTAssertFalse(NetworkService.isPlausibleIP("1.2.3"))
        XCTAssertFalse(NetworkService.isPlausibleIP("a.b.c.d"))
    }

    func testPortCatalogLabels() {
        XCTAssertEqual(PortCatalog.devLabel(forPort: 8081), "Metro")
        XCTAssertEqual(PortCatalog.devLabel(forPort: 5173), "Vite")
        XCTAssertEqual(PortCatalog.devLabel(forPort: 5432), "Postgres")
        XCTAssertNil(PortCatalog.devLabel(forPort: 65000))
    }

    func testPackageManagerVerbs() {
        XCTAssertEqual(PackageManager.npm.exec, "npx")
        XCTAssertEqual(PackageManager.yarn.exec, "yarn")
        XCTAssertEqual(PackageManager.pnpm.run, "pnpm")
        XCTAssertEqual(PackageManager.bun.run, "bun run")
        XCTAssertEqual(PackageManager.bun.exec, "bunx")
        XCTAssertEqual(PackageManager.yarn.install, "yarn")
        XCTAssertEqual(PackageManager.pnpm.install, "pnpm install")
    }

    func testProjectDerivedFlags() {
        let expo = DevProject(name: "A", path: "/tmp/a", kind: .expo, hasIOS: true, hasPods: true,
                              supportsTV: false, framework: nil, devScript: nil, bundleID: nil,
                              packageManager: .npm, scripts: [])
        XCTAssertTrue(expo.isJavaScript)
        XCTAssertTrue(expo.usesMetro)

        let native = DevProject(name: "B", path: "/tmp/b", kind: .nativeApple, hasIOS: true, hasPods: false,
                                supportsTV: false, framework: nil, devScript: nil, bundleID: nil,
                                packageManager: .npm, scripts: [])
        XCTAssertFalse(native.isJavaScript)
        XCTAssertFalse(native.usesMetro)
    }
}
