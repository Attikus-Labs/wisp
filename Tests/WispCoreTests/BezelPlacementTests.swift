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
        let origin = BezelPlacement.origin(forSize: bezel, anchor: CGPoint(x: 800, y: 500),
                                           screens: [laptop, sidecar])!
        // Concrete expected placement — literal values pin the nudge's sign and
        // magnitude (a flipped or rescaled nudge would miss these), unlike
        // re-deriving the production formula in the assertion.
        #expect(abs(origin.x - 611) < 0.001)        // 864 - 506/2
        #expect(abs(origin.y - 479.36) < 0.001)     // 546 - 308/2 + 1092 * 0.08
        #expect(laptop.visibleFrame.contains(CGRect(origin: origin, size: bezel)))
    }

    @Test func anchorOnSidecarCentresOnSidecar() {
        // Mouse on screen 2 must place the bezel on screen 2 — clear of screen 1.
        let origin = BezelPlacement.origin(forSize: bezel, anchor: CGPoint(x: 2500, y: 600),
                                           screens: [laptop, sidecar])!
        #expect(sidecar.frame.contains(CGRect(origin: origin, size: bezel)))
        #expect(!laptop.frame.intersects(CGRect(origin: origin, size: bezel)))
    }

    @Test func anchorOutsideAllScreensFallsBackToFirst() {
        let origin = BezelPlacement.origin(forSize: bezel, anchor: CGPoint(x: -9999, y: -9999),
                                           screens: [laptop, sidecar])!
        #expect(laptop.visibleFrame.contains(CGRect(origin: origin, size: bezel)))
    }

    @Test func noScreensReturnsNil() {
        #expect(BezelPlacement.origin(forSize: bezel, anchor: .zero, screens: []) == nil)
    }
}
