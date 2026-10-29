//
//  SplitMix64.swift
//  Sentient OS macOS
//
//  Moved verbatim from Views/Orb.swift (SPEC-00 3.15). The Knowledge graph seeds its star field and
//  mock graph with it. test_knowledge_retention.py stubs its own copy.
//

/// Tiny deterministic RNG so the ring's matter is identical every launch.
/// Internal (not private): the Night Sky graph view seeds its star field and mock graph with it too.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
