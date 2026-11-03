import Foundation
import Observation

/// Which items the keyboard is talking about.
///
/// The tray gained a keyboard the moment it gained Delete and ⌘C, and a
/// keyboard needs a subject. Selection is deliberately separate from
/// `TrayPresentationState`: what the tray is *doing* and what the user has
/// *picked* are independent, and folding them together would put six new cases
/// into a state machine that reads well precisely because it has four.
@Observable
final class TraySelection {
    private(set) var ids: Set<TrayItem.ID> = []

    /// The item a range or a step should extend from — the last one touched.
    private(set) var anchor: TrayItem.ID?

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func contains(_ id: TrayItem.ID) -> Bool { ids.contains(id) }

    func select(_ id: TrayItem.ID) {
        ids = [id]
        anchor = id
    }

    /// ⌘-click: add or remove one item without disturbing the rest.
    func toggle(_ id: TrayItem.ID) {
        if ids.contains(id) {
            ids.remove(id)
            if anchor == id { anchor = ids.first }
        } else {
            ids.insert(id)
            anchor = id
        }
    }

    func selectAll(_ all: [TrayItem.ID]) {
        ids = Set(all)
        anchor = all.last
    }

    func clear() {
        ids = []
        anchor = nil
    }

    /// Drops ids that are no longer on the shelf.
    ///
    /// Called after anything removes items, so a selection can never refer to
    /// something that has gone — which is how a Delete ends up doing nothing,
    /// or worse, doing it twice.
    func prune(to existing: [TrayItem.ID]) {
        let live = Set(existing)
        guard !ids.isSubset(of: live) else { return }
        ids.formIntersection(live)
        if let anchor, !live.contains(anchor) { self.anchor = ids.first }
    }

    /// Moves the selection one step along the shelf, starting from the near
    /// end when nothing is selected yet.
    func step(by offset: Int, within order: [TrayItem.ID]) {
        guard !order.isEmpty else { return }

        guard let anchor, let current = order.firstIndex(of: anchor) else {
            select(offset < 0 ? order[order.count - 1] : order[0])
            return
        }

        let next = min(max(current + offset, 0), order.count - 1)
        select(order[next])
    }

    /// The selected items, in shelf order rather than in set order, so a copy
    /// arrives on the pasteboard the way it looked on screen.
    func items(from all: [TrayItem]) -> [TrayItem] {
        all.filter { ids.contains($0.id) }
    }
}
