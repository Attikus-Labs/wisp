import Testing
import Foundation
@testable import WispCore

struct BezelPlacementTests {
    // The reported layout: laptop (primary, menu bar) at the origin, Sidecar to
    // its right. visibleFrame trims the menu bar on the primary.
    private let laptop = BezelPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1092))
    private let sidecar = BezelPlacement.Screen(
        frame: CGRect(x: 1728, y: 0, width: 1600, height: 1200),
        visibleFrame: CGRect(x: 1728, y: 0, width: 1600, height: 1200))
    // The real carousel panel size (BezelView.size), so the layout assertions run
    // against what actually ships rather than a fabricated size.
    private let bezel = CGSize(width: 506, height: 308)

    @Test func centresOnLaptopEightPercentAboveMidpoint() {
        let origin = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: 800, y: 500),
                                          screens: [laptop, sidecar])!.origin
        // Concrete expected placement — literal values pin the nudge's sign and
        // magnitude (a flipped or rescaled nudge would miss these), unlike
        // re-deriving the production formula in the assertion.
        #expect(abs(origin.x - 611) < 0.001)        // 864 - 506/2
        #expect(abs(origin.y - 479.36) < 0.001)     // 546 - 308/2 + 1092 * 0.08
        #expect(laptop.visibleFrame.contains(CGRect(origin: origin, size: bezel)))
    }

    @Test func anchorOnSidecarCentresOnSidecar() {
        // Mouse on screen 2 must place the bezel on screen 2 — clear of screen 1.
        let origin = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: 2500, y: 600),
                                          screens: [laptop, sidecar])!.origin
        #expect(sidecar.frame.contains(CGRect(origin: origin, size: bezel)))
        #expect(!laptop.frame.intersects(CGRect(origin: origin, size: bezel)))
    }

    @Test func anchorOutsideAllScreensFallsBackToFirst() {
        let origin = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: -9999, y: -9999),
                                          screens: [laptop, sidecar])!.origin
        #expect(laptop.visibleFrame.contains(CGRect(origin: origin, size: bezel)))
    }

    @Test func noScreensReturnsNil() {
        #expect(BezelPlacement.frame(preferredSize: bezel, anchor: .zero, screens: []) == nil)
    }

    // MARK: - Clamping to the screen

    @Test func normalScreenGetsTheFullPreferredSize() {
        let frame = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: 800, y: 500),
                                         screens: [laptop, sidecar])!
        #expect(frame.size == bezel)
    }

    @Test func cardIsClampedToFitASmallScreen() {
        // A display (or a display minus a large Dock) with less room than the card
        // asks for: the card shrinks — its content scrolls — rather than hanging off
        // the screen with the paste legend out of view.
        let small = BezelPlacement.Screen(
            frame: CGRect(x: 0, y: 0, width: 480, height: 280),
            visibleFrame: CGRect(x: 0, y: 0, width: 480, height: 260))
        let frame = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: 10, y: 10),
                                         screens: [small])!
        #expect(frame.width == 480 - BezelPlacement.margin * 2)
        #expect(frame.height == 260 - BezelPlacement.margin * 2)
        #expect(small.visibleFrame.contains(frame))
    }

    @Test func searchCardStaysOnScreenOnAShortDisplay() {
        // The taller of the two cards on a short screen — the case that used to put
        // the bottom of the HUD below the bottom of the display.
        let short = BezelPlacement.Screen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 420),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 400))
        let search = CGSize(width: 506, height: 524)
        let frame = BezelPlacement.frame(preferredSize: search, anchor: CGPoint(x: 10, y: 10),
                                         screens: [short])!
        #expect(frame.width == 506) // width was never the problem
        #expect(frame.height == 400 - BezelPlacement.margin * 2)
        #expect(short.visibleFrame.contains(frame))
    }

    @Test func upwardNudgeNeverPushesTheCardOffTheTop() {
        // The card sits 8% above centre; on a screen barely taller than the card that
        // nudge would run it under the menu bar, so the origin is pinned instead.
        let squat = BezelPlacement.Screen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 360),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 340))
        let frame = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: 10, y: 10),
                                         screens: [squat])!
        #expect(frame.size == bezel) // 308 still fits inside 340 - 2*16
        #expect(squat.visibleFrame.contains(frame))
        #expect(frame.maxY <= squat.visibleFrame.maxY - BezelPlacement.margin)
    }

    @Test func clampingHappensOnTheScreenUnderTheMouse() {
        // Big primary, small secondary: pointing at the secondary must clamp to *its*
        // size, not the primary's.
        let small = BezelPlacement.Screen(
            frame: CGRect(x: 1728, y: 0, width: 640, height: 300),
            visibleFrame: CGRect(x: 1728, y: 0, width: 640, height: 280))
        let frame = BezelPlacement.frame(preferredSize: bezel, anchor: CGPoint(x: 2000, y: 100),
                                         screens: [laptop, small])!
        #expect(frame.height == 280 - BezelPlacement.margin * 2)
        #expect(small.visibleFrame.contains(frame))
        #expect(!laptop.frame.intersects(frame))
    }
}
