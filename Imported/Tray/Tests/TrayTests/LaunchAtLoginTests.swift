import Testing

@testable import Tray

/// The startup reconciliation table from §34.
///
/// Every row here is a state these two things really get into: the user's
/// stored wish, and what `SMAppService` says is actually registered. They
/// diverge for ordinary reasons — a rebuild with a different signature, an
/// approval revoked in System Settings — and the app has to pick a side
/// without inventing a preference.
@MainActor
struct LaunchAtLoginTests {
    typealias Service = LaunchAtLoginService

    @Test func `an unexpressed wish is never invented, even when the system says enabled`() {
        // The row that matters most. A fresh install reports `.enabled` from
        // SMAppService before the user has touched anything; recording that as
        // a wish would enable launch-at-login on their behalf.
        #expect(Service.decide(intent: nil, state: .enabled) == .keep(nil))
    }

    @Test func `an unexpressed wish stays unexpressed when nothing is registered`() {
        #expect(Service.decide(intent: nil, state: .disabled) == .keep(nil))
    }

    @Test func `an item the system lost is registered again`() {
        // The usual cause is a rebuild with a different code signature, which
        // macOS treats as a different application.
        #expect(Service.decide(intent: true, state: .disabled) == .reregister)
    }

    @Test func `switching it on in System Settings is adopted`() {
        #expect(Service.decide(intent: false, state: .enabled) == .adopt)
    }

    @Test func `agreement is left alone`() {
        #expect(Service.decide(intent: true, state: .enabled) == .keep(true))
        #expect(Service.decide(intent: false, state: .disabled) == .keep(false))
    }

    @Test func `an approval the user has not given does not count as lost`() {
        // `.requiresApproval` means the item exists and is switched off in
        // System Settings. Re-registering over it looks like success and does
        // nothing, so the wish is kept and the UI explains instead.
        #expect(Service.decide(intent: true, state: .requiresApproval) == .keep(true))
    }

    @Test func `a location registration cannot survive does not trigger a rewrite`() {
        #expect(Service.decide(intent: true, state: .unstableLocation) == .keep(true))
        #expect(Service.decide(intent: nil, state: .unstableLocation) == .keep(nil))
    }

    @Test func `every failure the user can act on explains itself`() {
        #expect(Service.State.requiresApproval.explanation != nil)
        #expect(Service.State.unstableLocation.explanation != nil)
        #expect(Service.State.failed("disk full").explanation == "disk full")
        // Working states say nothing, because there is nothing to say.
        #expect(Service.State.enabled.explanation == nil)
        #expect(Service.State.disabled.explanation == nil)
    }
}
