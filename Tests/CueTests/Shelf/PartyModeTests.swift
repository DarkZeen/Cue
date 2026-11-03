import Foundation
import Testing

@testable import Cue

/// Party mode: the setting, the gradient's motion, and the two-colour lines.
@MainActor
struct PartyModeTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "PartyModeTests-\(UUID().uuidString)")!
    }

    @Test func `party mode is off until it is turned on`() {
        #expect(SettingsStore(defaults: defaults()).partyIntensity == 0)
    }

    @Test func `the strength is kept between launches, and kept in range`() {
        let store = defaults()
        let first = SettingsStore(defaults: store)
        first.partyIntensity = 0.6
        #expect(SettingsStore(defaults: store).partyIntensity == 0.6)

        first.partyIntensity = 7
        #expect(first.partyIntensity == 1)
        store.set(-3.0, forKey: "partyIntensity")
        #expect(SettingsStore(defaults: store).partyIntensity == 0)
    }

    @Test func `the gradient moves on by the rate, a frame at a time`() {
        let phase = PhaseIntegrator()
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        _ = phase.advance(to: start, turnsPerSecond: 1)

        let after = phase.advance(to: start.addingTimeInterval(0.05), turnsPerSecond: 1)
        #expect(abs(after - 0.05) < 1e-9)
    }

    @Test func `a long gap does not spin the gradient round`() {
        let phase = PhaseIntegrator()
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        _ = phase.advance(to: start, turnsPerSecond: 1)

        // The shelf was open for a minute: it picks up, it does not catch up.
        let after = phase.advance(to: start.addingTimeInterval(60), turnsPerSecond: 1)
        #expect(after <= 0.1 + 1e-9)
    }

    @Test func `long lines take one colour and short lines the other`() {
        #expect(MarkColouring.share(forLength: 0.1) == 0)
        #expect(MarkColouring.share(forLength: 1) == 1)

        let lengths = stride(from: 0.0, through: 1.0, by: 0.05).map { MarkColouring.share(forLength: $0) }
        #expect(lengths == lengths.sorted())
    }
}
