import AppKit
// `QLPreviewPanel` lives in Quartz on macOS; the `QuickLook` module only
// vends the file-preview types.
import Quartz

/// Native Quick Look for tray items (§24).
///
/// `QLPreviewPanel` and nothing else — the spec is explicit that a custom
/// preview engine is out of scope, and it would be a worse preview besides.
///
/// One deliberate compromise: Quick Look needs a key window and a responder
/// chain, and the tray's panel is non-activating precisely so it never takes
/// focus (§28). So this activates the app — but only in response to an
/// explicit request (a double click, or Space on a selected item). Focus is
/// never taken by hovering or dropping, which is what §28 is protecting.
final class QuickLookService: NSObject {
    private var items: [TrayItem] = []
    private var index: Int = 0

    var isPreviewing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    /// Shows `item`, with the rest of the shelf available as neighbours so the
    /// arrow keys walk the tray the way Quick Look does in Finder.
    func preview(_ item: TrayItem, within all: [TrayItem]) {
        let available = all.filter(\.isAvailable)
        guard let start = available.firstIndex(where: { $0.id == item.id }) else { return }

        items = available
        index = start

        NSApp.activate()

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = index
    }

    func dismiss() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }
}

extension QuickLookService: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        // Guarded rather than subscripted: the shelf can change while a
        // preview is open, and a stale index must not crash the app (§80).
        guard items.indices.contains(index) else { return NSURL() }
        return items[index].url as NSURL
    }
}

extension QuickLookService: QLPreviewPanelDelegate {}
