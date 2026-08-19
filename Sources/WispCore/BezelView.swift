import AppKit

/// The translucent HUD content, in three zones:
///   • a header — source app, a direction-aware nav (← / → flanking the position
///     counter, labelled older/newer per the arrow-direction setting), and the
///     clip's size (lines · chars);
///   • a discreet framed container holding a scrolling preview of the copied text
///     (its inset reveals leading spaces against the edge);
///   • a footer legend of the three paste shortcuts, plus a scroll hint when the
///     clip is taller than the card.
///
/// The preview is a `ClipPreview` (scroll view), not a label, so a long clip
/// scrolls inside a fixed card instead of stretching the window past the bottom of
/// the screen — see `ClipPreview` for the whole story. Full text is always pasted
/// regardless of what the preview shows.
@MainActor
final class BezelView: BezelEffectView {
    static let size = NSSize(width: 506, height: 308) // 460×280 + 10%

    private let appLabel = NSTextField(labelWithString: "")
    private let nav = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let divider = NSView()
    private let container = NSView()
    private let preview = ClipPreview(fontSize: 12)
    private let legend = NSTextField(labelWithString: "")

    /// Just under `fittingSizeCompression`, the threshold above which a constraint
    /// starts contributing to `fittingSize` — and so to the minimum size AppKit will
    /// let the window be. Header constraints that are preferences, not requirements,
    /// live here so a long clip summary or app name can never resize the card.
    private static let belowFittingSize = NSLayoutConstraint.Priority(
        NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1)

    /// Whether the shown clip looks like terminal output — the legend brightens
    /// ⇧⏎ for it, and it is re-read whenever the scroll hint appears/disappears.
    private var highlightReflow = false

    init() {
        super.init(size: BezelView.size) // material, rounded mask & scrim live in the base

        // Header: app (left) · nav (center) · size (right), one baseline.
        configure(appLabel, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        appLabel.lineBreakMode = .byTruncatingTail
        // Below `fittingSizeCompression` (50) on purpose: a long app name must never
        // widen the *window* (a content view's fitting size is a floor the window
        // can't go under), only truncate. It still shows in full whenever there's room.
        appLabel.setContentCompressionResistancePriority(Self.belowFittingSize, for: .horizontal)

        configure(nav, font: .systemFont(ofSize: 12), color: .labelColor)
        nav.alignment = .center
        nav.setContentHuggingPriority(.required, for: .horizontal)
        nav.setContentCompressionResistancePriority(.required, for: .horizontal)

        configure(sizeLabel, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        sizeLabel.alignment = .right
        sizeLabel.lineBreakMode = .byTruncatingTail
        // Higher than the app name's: when a clip's summary is long ("1,928+ lines ·
        // 2.1 MB") something has to give, and the app name — already truncating, and
        // the least load-bearing of the three — is the right thing to shorten.
        sizeLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // Hairline under the header for structure.
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        // Discreet container framing the copied text — its inset reveals a leading
        // space as a gap from the edge.
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        container.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        // The hint only makes sense while there's something to scroll to.
        preview.onOverflowChange = { [weak self] _ in self?.refreshLegend() }

        configure(legend, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        legend.maximumNumberOfLines = 1
        legend.alignment = .center

        [appLabel, nav, sizeLabel, divider, container, legend].forEach(addSubview)
        container.addSubview(preview)

        // Centring the nav is a preference, not a rule: on a wide summary it slides
        // left rather than forcing the labels beside it to lose characters. Kept below
        // `fittingSizeCompression` so the symmetry it implies (equal space either
        // side) can't become a floor on the window's width — see `appLabel` above.
        let navCentre = nav.centerXAnchor.constraint(equalTo: centerXAnchor)
        navCentre.priority = Self.belowFittingSize

        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            navCentre,

            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            appLabel.firstBaselineAnchor.constraint(equalTo: nav.firstBaselineAnchor),
            appLabel.trailingAnchor.constraint(lessThanOrEqualTo: nav.leadingAnchor, constant: -10),

            sizeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            sizeLabel.firstBaselineAnchor.constraint(equalTo: nav.firstBaselineAnchor),
            sizeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nav.trailingAnchor, constant: 10),

            divider.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            container.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: legend.topAnchor, constant: -12),

            // The preview fills the frame; it has no intrinsic height, so a long
            // clip scrolls rather than pushing the card taller.
            preview.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),

            legend.centerXAnchor.constraint(equalTo: centerXAnchor),
            legend.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            legend.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            legend.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ field: NSTextField, font: NSFont, color: NSColor) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.allowsDefaultTighteningForTruncation = true
    }

    func update(item: ClipboardItem, index: Int, count: Int) {
        highlightReflow = TerminalText.looksLikeTerminalOutput(item.text)
        // Terminal output and code only read correctly in a fixed pitch, and that's
        // the same signal that brightens ⇧⏎ — so the card *looks* like what the
        // reflow key is offering to clean up.
        preview.show(text: item.text, monospaced: highlightReflow)
        nav.attributedStringValue = navLine(index: index, count: count)
        appLabel.stringValue = AppDisplayName.resolve(item.sourceBundleID) ?? ""
        sizeLabel.stringValue = ClipPreview.sizeSummary(item.text)
        refreshLegend()
    }

    // MARK: - Scrolling the preview (driven by BezelController)

    func scrollPreview(lines: Int) { preview.scroll(lines: lines) }
    func scrollPreview(pages: Int) { preview.scroll(pages: pages) }
    func scrollPreviewToEdge(start: Bool) { preview.scrollToEdge(start: start) }

    /// `←  older     3 of 10     newer  →`. The arrows stay physically left/right
    /// (matching the keys); the older/newer labels swap with the arrow-direction
    /// setting, so the user can read which key walks back vs forward.
    private func navLine(index: Int, count: Int) -> NSAttributedString {
        let previousIsLeft = Settings.previousArrow == .left
        let leftWord = previousIsLeft ? "older" : "newer"
        let rightWord = previousIsLeft ? "newer" : "older"

        let arrow: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
        let word: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]
        let counter: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: NSColor.labelColor]

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "←  ", attributes: arrow))
        s.append(NSAttributedString(string: leftWord + "     ", attributes: word))
        s.append(NSAttributedString(string: "\(index + 1) of \(count)", attributes: counter))
        s.append(NSAttributedString(string: "     " + rightWord, attributes: word))
        s.append(NSAttributedString(string: "  →", attributes: arrow))
        return s
    }

    private func refreshLegend() {
        legend.attributedStringValue = pasteLegend(highlightReflow: highlightReflow,
                                                   scrollable: preview.overflows)
    }

    /// The three paste shortcuts, always shown. ⇧⏎ reflow is brightened when the
    /// clip looks like terminal output — the case where it actually helps — and
    /// `⌥↕ scroll` joins the line only when the clip is taller than the card.
    private func pasteLegend(highlightReflow: Bool, scrollable: Bool) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        var reflow = normal
        if highlightReflow { reflow[.foregroundColor] = NSColor.labelColor }

        // Secondary actions are dimmed — they switch modes or move the view rather
        // than pasting, so they read as distinct from the three paste keys.
        let hint: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]

        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "⏎ plain      ⌥⏎ formatted      ", attributes: normal))
        line.append(NSAttributedString(string: "⇧⏎ reflow", attributes: reflow))
        line.append(NSAttributedString(string: "      / search", attributes: hint))
        if scrollable {
            line.append(NSAttributedString(string: "      ⌥↕ scroll", attributes: hint))
        }
        return line
    }
}
