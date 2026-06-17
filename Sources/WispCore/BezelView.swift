import AppKit

/// The translucent HUD content, in three zones:
///   • a header — source app, a direction-aware nav (← / → flanking the position
///     counter, labelled older/newer per the arrow-direction setting), and char count;
///   • a discreet framed container holding the copied text (its inset reveals
///     leading spaces against the edge);
///   • a footer legend of the three paste shortcuts.
/// Full text is always pasted regardless of truncation.
@MainActor
final class BezelView: BezelEffectView {
    static let size = NSSize(width: 506, height: 308) // 460×280 + 10%

    private let appLabel = NSTextField(labelWithString: "")
    private let nav = NSTextField(labelWithString: "")
    private let charLabel = NSTextField(labelWithString: "")
    private let divider = NSView()
    private let container = NSView()
    private let body = BezelEffectView.wrappingPreviewLabel(
        font: .systemFont(ofSize: 14), wrapWidth: BezelView.size.width - 32 - 24)
    private let legend = NSTextField(labelWithString: "")

    init() {
        super.init(size: BezelView.size) // material, rounded mask & scrim live in the base

        // Header: app (left) · nav (center) · chars (right), one baseline.
        configure(appLabel, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configure(nav, font: .systemFont(ofSize: 12), color: .labelColor)
        nav.alignment = .center
        nav.setContentHuggingPriority(.required, for: .horizontal)
        nav.setContentCompressionResistancePriority(.required, for: .horizontal)

        configure(charLabel, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        charLabel.alignment = .right
        charLabel.lineBreakMode = .byTruncatingTail
        charLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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

        // body comes preconfigured from BezelEffectView.wrappingPreviewLabel —
        // wrapping, container-capped, last-line ellipsis.

        configure(legend, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        legend.maximumNumberOfLines = 1
        legend.alignment = .center

        [appLabel, nav, charLabel, divider, container, legend].forEach(addSubview)
        container.addSubview(body)

        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            nav.centerXAnchor.constraint(equalTo: centerXAnchor),

            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            appLabel.firstBaselineAnchor.constraint(equalTo: nav.firstBaselineAnchor),
            appLabel.trailingAnchor.constraint(lessThanOrEqualTo: nav.leadingAnchor, constant: -10),

            charLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            charLabel.firstBaselineAnchor.constraint(equalTo: nav.firstBaselineAnchor),
            charLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nav.trailingAnchor, constant: 10),

            divider.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            container.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: legend.topAnchor, constant: -12),

            body.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -11),

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
        body.stringValue = PreviewText.trimmed(item.text)
        nav.attributedStringValue = navLine(index: index, count: count)
        appLabel.stringValue = AppDisplayName.resolve(item.sourceBundleID) ?? ""
        charLabel.stringValue = charCountText(item.text.count)
        legend.attributedStringValue = pasteLegend(
            highlightReflow: TerminalText.looksLikeTerminalOutput(item.text))
    }

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

    /// The three paste shortcuts, always shown. ⇧⏎ reflow is brightened when the
    /// clip looks like terminal output — the case where it actually helps.
    private func pasteLegend(highlightReflow: Bool) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        var reflow = normal
        if highlightReflow { reflow[.foregroundColor] = NSColor.labelColor }

        // The `/` hint is dimmed like a secondary action — it switches modes
        // rather than pasting, so it reads as distinct from the three paste keys.
        let hint: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]

        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "⏎ plain      ⌥⏎ formatted      ", attributes: normal))
        line.append(NSAttributedString(string: "⇧⏎ reflow", attributes: reflow))
        line.append(NSAttributedString(string: "      / search", attributes: hint))
        return line
    }

    private func charCountText(_ count: Int) -> String {
        count == 1 ? "1 char" : "\(count) chars"
    }

}
