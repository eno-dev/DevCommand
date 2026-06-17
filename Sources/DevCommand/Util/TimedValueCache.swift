import Foundation

/// A single value with a freshness window, safe to share across tasks. Used to avoid repeating
/// expensive work (a slow `du`, an outbound public-IP request) on every panel/menu open.
/// `now` is injected so the expiry logic is deterministic and unit-testable.
actor TimedValueCache<Value: Sendable> {
    private var value: Value?
    private var storedAt: Date?
    private var inFlight: Task<Value?, Never>?

    /// The cached value if it was stored within `ttl` of `now`, else nil.
    func get(ttl: TimeInterval, now: Date = Date()) -> Value? {
        guard let value, let storedAt else { return nil }
        // A backwards clock jump (sleep/wake, NTP) makes the age negative — treat that as expired
        // rather than "fresh forever", so a stale value can't outlive its TTL.
        let age = now.timeIntervalSince(storedAt)
        guard age >= 0, age < ttl else { return nil }
        return value
    }

    /// Return the fresh cached value, or run `fetch` once — concurrent callers that arrive while a
    /// fetch is in flight await the same result instead of each starting their own (single-flight).
    /// A nil result isn't cached.
    func value(ttl: TimeInterval, fetch: @Sendable @escaping () async -> Value?) async -> Value? {
        if let cached = get(ttl: ttl) { return cached }
        if let inFlight { return await inFlight.value }
        let task = Task { await fetch() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if let result { set(result) }
        return result
    }

    func set(_ value: Value, at: Date = Date()) {
        self.value = value
        self.storedAt = at
    }

    func clear() {
        value = nil
        storedAt = nil
    }
}
