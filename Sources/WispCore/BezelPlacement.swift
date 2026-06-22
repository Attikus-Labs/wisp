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

    /// Bottom-left origin that centres `size` on the screen containing `anchor`,
    /// nudged up by 8% of that screen's height so the bezel sits a touch above
    /// centre. Falls back to the first screen when the anchor is inside none — the
    /// mouse pointer is effectively always on some display, so this is just
    /// belt-and-braces. Returns nil only when there are no screens at all.
    static func origin(forSize size: CGSize, anchor: CGPoint, screens: [Screen]) -> CGPoint? {
        guard !screens.isEmpty else { return nil }
        let target = screens.first { $0.frame.contains(anchor) } ?? screens[0]
        let visible = target.visibleFrame
        return CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.08
        )
    }
}
