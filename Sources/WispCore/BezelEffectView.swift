import AppKit

/// Shared skin for the bezel and the search HUD: the translucent `.hudWindow`
/// material, the 18pt rounded-corner mask, and a **scrim** layer that gives the
/// card definition on *any* desktop.
///
/// The material samples whatever is behind the window, so over a light desktop the
/// card turns pale and a white-alpha edge washes out. The scrim fixes that two ways,
/// both driven from Settings:
///   • **Appearance** — the card is forced Dark / Light / or Auto (follow the
///     system) regardless of the desktop, so a forced-Dark card always reads well.
///   • **Transparency** — a continuous fill from translucent (pure material) to
///     near-solid, so you can trade the blur for guaranteed contrast.
/// An always-on hairline border keeps the card's edge crisp even at full translucency.
@MainActor
class BezelEffectView: NSVisualEffectView {
    /// Sits behind all content, in front of the material: a rounded fill (alpha set
    /// by the Transparency setting) plus a permanent edge stroke.
    private let scrim = NSView()

    init(size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        // Round the corners by masking the *material* (maskImage), not the layer:
        // layer cornerRadius + masksToBounds leaves a light fringe in the corner
        // triangles of an NSVisualEffectView (visible over a light background). The
        // mask makes everything beyond the rounded edge fully transparent.
        maskImage = Self.roundedMaskImage(radius: 18)

        scrim.wantsLayer = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.layer?.cornerRadius = 18 // match the material mask, so the edge aligns
        scrim.layer?.borderWidth = 1
        addSubview(scrim) // first subview → behind everything the subclass adds
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Apply the current appearance + transparency settings. Call before each show
    /// so a change in the menu takes effect next time the bezel appears.
    func applyStyle() {
        let target = Settings.bezelAppearance.nsAppearance
        if appearance != target { appearance = target } // guard avoids re-entrancy via viewDidChange…
        applyScrim()
    }

    private func applyScrim() {
        // Resolve dark-vs-light from the *effective* appearance, so Auto picks up
        // the system setting and Dark/Light honour the forced value.
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != .aqua
        let fillBase = isDark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        let solid = CGFloat(min(max(Settings.bezelSolidness, 0), 1)) // 0 = translucent, 1 = solid
        scrim.layer?.backgroundColor = fillBase.withAlphaComponent(solid).cgColor
        let edge = isDark ? NSColor.white : NSColor.black
        scrim.layer?.borderColor = edge.withAlphaComponent(isDark ? 0.20 : 0.18).cgColor
    }

    /// Re-tint the scrim when the system appearance flips (matters in Auto mode).
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyScrim()
    }

    /// The label both previews show clip text in: wraps long paragraphs, fills
    /// whatever height its container leaves it, and ellipsizes the last visible
    /// line when the clip doesn't fit.
    ///
    /// The line-break mode is load-bearing: assigning any *truncating* mode to an
    /// NSCell silently sets `wraps = false`, collapsing every paragraph to a
    /// single clipped line — long logical lines (e.g. Claude Code's copy-on-select
    /// output) would run out of view instead of wrapping. Only word-wrap keeps
    /// `wraps = true`; `truncatesLastVisibleLine` supplies the ellipsis instead.
    /// New preview surfaces should come through here so the trap stays fixed in
    /// one place.
    ///
    /// No line cap (`maximumNumberOfLines = 0`): the container's bottom edge is
    /// the cap, via the low vertical compression resistance yielding to the
    /// container's required constraints. Callers bound the text they feed in with
    /// `PreviewText.trimmed`, so layout cost stays trivial.
    static func wrappingPreviewLabel(font: NSFont, wrapWidth: CGFloat) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = .labelColor
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.allowsDefaultTighteningForTruncation = true
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        field.preferredMaxLayoutWidth = wrapWidth
        return field
    }

    /// A resizable rounded-rect mask (opaque inside, transparent outside) for the
    /// visual effect view's `maskImage`, so the material is clipped to clean rounded
    /// corners with no fringe.
    static func roundedMaskImage(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

extension Settings.BezelAppearance {
    /// The `NSAppearance` to force on the card, or `nil` for Auto (inherit the app /
    /// system appearance).
    var nsAppearance: NSAppearance? {
        switch self {
        case .dark:  return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .auto:  return nil
        }
    }
}
