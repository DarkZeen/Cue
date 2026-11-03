import SwiftUI

/// The geometry read-out from §71, enabled with `TRAY_DEBUG=1`.
///
/// Notch positioning is the kind of problem that is nearly impossible to
/// reason about and trivial to see, so this prints the numbers the layout is
/// actually using next to the thing they produced. It cannot appear in a
/// release build — `Diagnostics.isDebugOverlayEnabled` is compiled to `false`
/// there.
struct TrayDebugOverlay: View {
    let presenter: TrayPresenter
    let store: TrayStore
    let geometry: ScreenGeometry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("screen", "\(Int(geometry.frame.width))×\(Int(geometry.frame.height))")
            row("display", "\(geometry.id)")
            row("safeArea.top", String(format: "%.1f", geometry.topInset))
            row("menuBar", String(format: "%.1f", geometry.menuBarHeight))
            row("notch", geometry.notchSize.map {
                "\(Int($0.width))×\(Int($0.height))"
            } ?? "none")
            row("state", "\(presenter.state)")
            row("drag", presenter.isDragApproaching ? "approaching" : "—")
            row("collapse", presenter.isCollapseScheduled ? "scheduled" : "—")
            row("items", "\(store.count)")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .padding(6)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .foregroundStyle(.green)
        .padding(.top, TrayItemMetrics.maximumExpandedHeight(
            screenHeight: geometry.usableHeight
        ) + 8)
        .allowsHitTesting(false)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").foregroundStyle(.green.opacity(0.55))
            Text(value)
        }
    }
}
