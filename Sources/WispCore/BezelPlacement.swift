import CoreGraphics

/// Placement math for the bezel, factored out of `BezelController` so the
/// multi-display logic is unit-testable without real `NSScreen`s or a live
/// window server.
///
/// Why this exists: placement used to key off `NSScreen.main`, which Apple
/// documents as "the screen with the key window" — *not* the primary display and
/// not the display you're looking at. For Wisp's non-activating accessory panel
/// that resolves unpredictably across multiple displays, Sidecar, and
/// per-display Spaces, so the bezel could surface on a screen the user wasn't
/// watching. Instead the caller passes the mouse location — which tracks the
/// user's attention — and we centre the bezel on the screen containing it.
///
/// Note: which *Space* the bezel lands on is orthogonal to geometry (every Space
/// on a display shares the same coordinate rectangle, so no point can select a
/// Space). That's handled by the panel's `.canJoinAllSpaces` collection
/// behaviour, which makes the bezel a member of every Space — so it always shows
/// on whichever Space is current on its display.
enum BezelPlacement {
    /// One display: its full `frame` (used to locate the anchor) and its
    /// `visibleFrame` (the menu-bar/Dock-excluded area used for layout). Both in
    /// AppKit global coordinates (bottom-left origin).
    struct Screen: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// Breathing room kept between the card and the edge of the usable screen area
    /// when a card has to be clamped to fit.
    static let margin: CGFloat = 16

    /// The bezel's on-screen frame: `preferredSize` **clamped to fit** the screen
    /// containing `anchor`, centred there and nudged up by 8% of that screen's
    /// height so it sits a touch above centre.
    ///
    /// The clamp is what keeps a HUD on screen. The cards declare a fixed preferred
    /// size, but a small display (or a big Dock) can leave less room than that, and
    /// a card taller than the screen would hang off the bottom with its paste legend
    /// out of view. Both clamping *and* the final nudge are pinned inside
    /// `visibleFrame`, so the whole card is always visible — the content inside it
    /// scrolls instead (see `ClipPreview`).
    ///
    /// Falls back to the first screen when the anchor is inside none — the mouse
    /// pointer is effectively always on some display, so this is just
    /// belt-and-braces. Returns nil only when there are no screens at all.
    static func frame(preferredSize: CGSize, anchor: CGPoint, screens: [Screen]) -> CGRect? {
        guard !screens.isEmpty else { return nil }
        let target = screens.first { $0.frame.contains(anchor) } ?? screens[0]
        let visible = target.visibleFrame

        let size = CGSize(
            width: min(preferredSize.width, max(visible.width - margin * 2, 1)),
            height: min(preferredSize.height, max(visible.height - margin * 2, 1)))

        var origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.08)
        // Pin inside the usable area: on a short screen the 8% nudge would otherwise
        // push the top of a full-height card under the menu bar.
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - margin - size.width)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - margin - size.height)
        return CGRect(origin: origin, size: size)
    }
}
