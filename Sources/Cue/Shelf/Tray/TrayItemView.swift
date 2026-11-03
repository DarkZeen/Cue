import AppKit
import SwiftUI

/// One item on the shelf (§18, §19, §46).
///
/// A tile, not a row in a file browser. The tray shows what a thing *is* and
/// lets you pick it up; anything more belongs in Finder.
struct TrayItemView: View {
    let item: TrayItem
    let thumbnails: FileThumbnailProvider
    let metrics: TrayItemMetrics
    let isBeingDragged: Bool
    let isSelected: Bool

    /// Every item this drag should carry — the whole selection when this item
    /// is part of it, just this one when it is not.
    let dragTargets: () -> [TrayItem]
    let onDragBegan: ([TrayItem]) -> Void
    let onDragEnded: ([TrayItem], Bool) -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onQuickLook: () -> Void
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onCopy: () -> Void

    @Environment(\.trayPalette) private var palette
    @Environment(\.trayMotion) private var motion

    @State private var image: NSImage?
    @State private var isHovering = false

    private var displayImage: NSImage {
        image ?? thumbnails.immediateImage(for: item, size: metrics.thumbnailSize)
    }

    var body: some View {
        VStack(spacing: TrayMetrics.labelSpacing) {
            thumbnail

            if metrics.showsFilename {
                Text(item.filename)
                    .font(.system(size: 9.5, weight: .medium))
                    // Slight positive tracking: small type over a translucent
                    // surface needs the extra air to stay legible.
                    .tracking(0.1)
                    .foregroundStyle(palette.ink(item.isAvailable ? 0.62 : 0.34))
                    .lineLimit(1)
                    // Middle truncation keeps the extension visible, which is
                    // usually the most identifying part of a filename.
                    .truncationMode(.middle)
                    .frame(width: metrics.itemWidth)
            }
        }
        .frame(width: metrics.itemWidth)
        .scaleEffect(scale)
        .opacity(isBeingDragged ? 0.32 : 1)
        .animation(motion.hover, value: isHovering)
        .animation(motion.hover, value: isSelected)
        .animation(motion.itemShift, value: isBeingDragged)
        .overlay { interactionLayer }
        .help(item.url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: TaskKey(identity: item.identity, size: metrics.thumbnailSize)) {
            image = await thumbnails.previewImage(
                for: item,
                size: CGSize(width: metrics.thumbnailSize, height: metrics.thumbnailSize)
            )
        }
    }

    // MARK: - Pieces

    /// The island's artwork treatment: a squircle whose radius is a fixed share
    /// of its size — 19%, so a 32pt icon and an 88pt one are the same shape at
    /// two scales rather than one rounded tile and one nearly-square one — over
    /// a hairline that keeps a pale thumbnail from dissolving into the black.
    private var plateRadius: CGFloat { metrics.thumbnailSize * 0.19 }

    private var plate: RoundedRectangle {
        RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
    }

    private var thumbnail: some View {
        Image(nsImage: displayImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: metrics.thumbnailSize, height: metrics.thumbnailSize)
            .opacity(item.isAvailable ? 1 : 0.4)
            .background {
                // Hover is a whisper; selection is a statement. Both live on
                // the same shape so one becomes the other rather than a second
                // thing appearing next to it. The island's own two values:
                // 9% under the pointer, 12% for what is chosen.
                plate
                    .fill(selectionFill)
                    .padding(-4)
            }
            .overlay {
                plate.strokeBorder(
                    isSelected ? palette.ink(0.5) : palette.artworkEdge,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if !item.isAvailable { unavailableBadge }
            }
    }

    /// The file went away behind our back (§52). Say so quietly; do not remove
    /// the item out from under the user, and do not crash.
    private var unavailableBadge: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primaryInk, Color(red: 0.85, green: 0.4, blue: 0.3))
            .offset(x: 2, y: 2)
    }

    /// Re-fetches the preview when either the file or the size changes, so a
    /// bigger thumbnail is actually rendered bigger rather than scaled up.
    private struct TaskKey: Equatable {
        var identity: String
        var size: CGFloat
    }

    private var selectionFill: Color {
        // Ink rather than the accent colour: the island tints everything in it
        // white, and one blue tile in a black cutout turns the whole thing
        // back into a panel.
        if isSelected { return palette.controlFill(selected: true) }
        return palette.hoverFill(isHovering)
    }

    private var scale: CGFloat {
        if isBeingDragged { return TrayScale.itemLifted }
        return isHovering ? TrayScale.itemHover : TrayScale.resting
    }

    private var interactionLayer: some View {
        ItemInteractionLayer(
            item: item,
            onHoverChanged: { isHovering = $0 },
            dragPayload: dragTargets,
            onDragBegan: onDragBegan,
            onDragEnded: onDragEnded,
            onOpenQuickLook: onQuickLook,
            onClick: onClick,
            menuBuilder: buildMenu,
            dragImage: { carried in
                // Each carried file gets its own picture, not this row's.
                carried.id == item.id
                    ? displayImage
                    : thumbnails.immediateImage(for: carried, size: metrics.thumbnailSize)
            }
        )
    }

    /// Short, and it stays short (§23). The tray is not Finder.
    ///
    /// Copy is the one addition beyond the three §23 lists, added because the
    /// shelf now has ⌘C and a command with no visible home is a command nobody
    /// finds. The rest of §23's list — Rename, Compress, Share, Open With,
    /// Move, Delete — stays out.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addAction(title: "Remove from Tray", handler: onRemove)
        menu.addAction(title: "Copy", isEnabled: item.isAvailable, handler: onCopy)
        menu.addAction(title: "Reveal in Finder", isEnabled: item.isAvailable, handler: onReveal)
        menu.addAction(title: "Quick Look", isEnabled: item.isAvailable, handler: onQuickLook)
        return menu
    }
}
