import XCTest
@testable import DevCommand

final class TimedValueCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testReturnsValueWithinTTL() async {
        let cache = TimedValueCache<String>()
        await cache.set("hello", at: t0)
        let value = await cache.get(ttl: 300, now: t0.addingTimeInterval(299))
        XCTAssertEqual(value, "hello")
    }

    func testExpiresAtTTLBoundary() async {
        let cache = TimedValueCache<Int>()
        await cache.set(42, at: t0)
        let atBoundary = await cache.get(ttl: 300, now: t0.addingTimeInterval(300))  // not < ttl
        let past = await cache.get(ttl: 300, now: t0.addingTimeInterval(301))
        XCTAssertNil(atBoundary)
        XCTAssertNil(past)
    }

    func testEmptyReturnsNil() async {
        let cache = TimedValueCache<String>()
        let value = await cache.get(ttl: 300, now: t0)
        XCTAssertNil(value)
    }

    func testSetOverwrites() async {
        let cache = TimedValueCache<String>()
        await cache.set("a", at: t0)
        await cache.set("b", at: t0.addingTimeInterval(10))
        let value = await cache.get(ttl: 300, now: t0.addingTimeInterval(20))
        XCTAssertEqual(value, "b")
    }

    func testClear() async {
        let cache = TimedValueCache<String>()
        await cache.set("x", at: t0)
        await cache.clear()
        let value = await cache.get(ttl: 300, now: t0)
        XCTAssertNil(value)
    }
}
