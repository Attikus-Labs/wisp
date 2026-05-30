import AppKit

/// The translucent HUD content: a large preview of the current clip plus a small
/// position/source footer. Full text is always pasted regardless of truncation.
@MainActor
final class BezelView: NSVisualEffectView {
    static let size = NSSize(width: 460, height: 280)

    private let body = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let legend = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(origin: .zero, size: BezelView.size))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        configure(body, font: .systemFont(ofSize: 15), color: .labelColor)
        body.maximumNumberOfLines = 10
        body.lineBreakMode = .byTruncatingTail
        body.cell?.truncatesLastVisibleLine = true
        body.preferredMaxLayoutWidth = BezelView.size.width - 44

        configure(footer, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        footer.maximumNumberOfLines = 1
        footer.lineBreakMode = .byTruncatingMiddle
        footer.alignment = .center

        // Always-visible legend of the three paste shortcuts, so all of them — not
        // just ⌥⏎ — are discoverable. Centered on its own line below the info row.
        configure(legend, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        legend.maximumNumberOfLines = 1
        legend.alignment = .center

        addSubview(body)
        addSubview(footer)
        addSubview(legend)

        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            body.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -10),

            footer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
            footer.centerXAnchor.constraint(equalTo: centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: legend.topAnchor, constant: -5),

            legend.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            legend.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            legend.centerXAnchor.constraint(equalTo: centerXAnchor),
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
        body.stringValue = item.text.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts = ["\(index + 1) of \(count)"]
        if let app = appName(for: item.sourceBundleID) { parts.append(app) }
        parts.append(charCountText(item.text.count))
        footer.stringValue = parts.joined(separator: "   ·   ")

        legend.attributedStringValue = pasteLegend(
            highlightReflow: TerminalText.looksLikeTerminalOutput(item.text))
    }

    /// The three paste shortcuts, always shown. ⇧⏎ reflow is brightened when the
    /// clip looks like terminal output — the case where it actually helps.
    private func pasteLegend(highlightReflow: Bool) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        var reflow = normal
        if highlightReflow { reflow[.foregroundColor] = NSColor.labelColor }

        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "⏎ plain      ⌥⏎ formatted      ", attributes: normal))
        line.append(NSAttributedString(string: "⇧⏎ reflow", attributes: reflow))
        return line
    }

    private func charCountText(_ count: Int) -> String {
        count == 1 ? "1 char" : "\(count) chars"
    }

    private func appName(for bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
