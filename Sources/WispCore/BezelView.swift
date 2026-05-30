import AppKit

/// The translucent HUD content: a large preview of the current clip plus a small
/// position/source footer. Full text is always pasted regardless of truncation.
@MainActor
final class BezelView: NSVisualEffectView {
    static let size = NSSize(width: 460, height: 280)

    private let body = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "")

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

        addSubview(body)
        addSubview(footer)

        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            body.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
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
