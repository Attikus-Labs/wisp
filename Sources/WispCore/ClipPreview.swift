import AppKit

/// The scrollable, wrapping text surface both HUDs use to show clip content —
/// the bezel's body and the search HUD's detail pane.
///
/// **Why a scroll view and not a label.** Both HUDs used a wrapping `NSTextField`
/// whose `lineBreakMode` was set to `.byTruncatingTail`. In AppKit that flips the
/// cell's `wraps` off, which silently disabled two things at once:
///
///   • long text stopped wrapping — a paragraph laid out as one clipped line that
///     ran off the right edge, so most of it was simply invisible;
///   • `maximumNumberOfLines` stopped capping anything, so a 60-line clip gave the
///     label a ~1100pt intrinsic height. A window that lays out with Auto Layout
///     grows to satisfy its content view's required constraints, so the bezel grew
///     with it and ran off the bottom of the screen.
///
/// `NSScrollView` has **no intrinsic content size**, so the card's height is now
/// decided by the card alone: long clips scroll, they never stretch the window.
/// Wrapping is real (word wrap, breaking mid-token when a token — a JWT, a base64
/// blob — is longer than a line), and the arrow keys can walk through a long clip
/// instead of leaving it truncated.
///
/// Memory-only like everything else: this renders a *copy* of text already held in
/// RAM, never writes it anywhere, and the text view is non-editable, non-selectable
/// and has no context menu, so macOS text services (spelling, substitutions, data
/// detectors, Services) never see clipboard content.
@MainActor
final class ClipPreview: NSView {
    /// How many characters of a clip get laid out. Clips can be huge (`Settings.
    /// maxClipBytes` goes up to Unlimited), and laying out megabytes of text on the
    /// main thread to fill a 300pt card would stall the HUD. Mirrors the same
    /// pragmatism as `ClipboardSearch.maxSearchableChars`: a preview is a preview —
    /// the char count in the header still reports the clip's true length, and the
    /// paste path always uses the full text.
    nonisolated static let maxPreviewChars = 8_000

    /// How much of a clip is scanned when counting its lines. Every search result
    /// row carries a line count and the list is rebuilt on every keystroke, so this
    /// stays small; past it the count is reported as a floor ("1,024+ lines").
    nonisolated static let maxCountedBytes = 64 * 1024

    /// Past this size a clip's length is reported in bytes rather than characters —
    /// see `sizeSummary`.
    nonisolated static let maxMeasuredBytes = 1_000_000

    /// Height of the soft fade at the top/bottom edge that signals "more above /
    /// more below".
    private static let fadeHeight: CGFloat = 20

    private let scrollView = NSScrollView()
    private let textView = PreviewTextView()
    private let fadeMask = CAGradientLayer()

    private let bodyFont: NSFont
    private let monoFont: NSFont

    /// Set while a reveal is queued: the first match can only be located once the
    /// view has its real width (wrapping depends on it), so `show` records it and
    /// `layout` performs it.
    private var pendingReveal: NSRange?

    /// Whether the laid-out text is taller than the visible area — i.e. whether
    /// scrolling does anything. Updated on every layout pass.
    private(set) var overflows = false

    /// Fired when `overflows` flips, so the HUD can show/hide its scroll hint.
    var onOverflowChange: ((Bool) -> Void)?

    init(fontSize: CGFloat) {
        bodyFont = .systemFont(ofSize: fontSize)
        // Terminal output and code line up only in a fixed pitch; a hair smaller so
        // the same card still fits a comparable number of columns.
        monoFont = .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        buildTextView()
        buildScrollView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Build

    private func buildTextView() {
        textView.isEditable = false
        textView.isSelectable = false // also keeps it out of the responder chain
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Clipboard content can hold secrets and is read-only here, so keep every
        // system text service away from it.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
    }

    private func buildScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay // floats over the text, claims no width
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.wantsLayer = true // the edge fade is a mask on this layer
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        fadeMask.colors = []
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)

        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidScroll),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    // MARK: - Content

    /// Render `text`, highlighting the characters at `matchedOffsets` (offsets into
    /// `text`, as `ClipboardSearch` reports them) and scrolling the first match into
    /// view. `monospaced` switches to a fixed-pitch face — used for clips that look
    /// like terminal output, where alignment carries meaning.
    func show(text: String, monospaced: Bool = false, matchedOffsets: [Int] = []) {
        // Slice the head off *before* trimming: only the first `maxPreviewChars` can
        // ever be shown, and materialising a multi-megabyte clip on every ←/→ press
        // just to take 8k off the front would stall the HUD.
        let head = text.prefix(Self.maxPreviewChars + 64)
        // Trim the same way both HUDs always have: drop leading blank lines and all
        // trailing whitespace (they'd only waste preview height), but keep leading
        // spaces on the first kept line so indentation is visible against the edge.
        let (preview, dropped) = Self.trimmedPreview(head)
        let capped = String(preview.prefix(Self.maxPreviewChars))

        let paragraph = NSMutableParagraphStyle()
        // Word wrapping breaks mid-token when a token is wider than the line, so an
        // unbroken 5,000-char JWT or base64 blob wraps instead of running off-card.
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1
        // Indent the continuation of a wrapped line, so a line that ran past the
        // card's width reads as a continuation rather than as a new line of the clip.
        paragraph.headIndent = 16
        paragraph.tabStops = []
        paragraph.defaultTabInterval = (monospaced ? monoFont : bodyFont).boundingRectForFont.width * 4

        let attributed = NSMutableAttributedString(string: capped, attributes: [
            .font: monospaced ? monoFont : bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])

        // Matched offsets index the *clip*; the preview dropped `dropped` leading
        // characters and may be capped, so shift and clip them before use.
        let ranges = Self.highlightRanges(in: capped, matchedOffsets: matchedOffsets, dropped: dropped)
        for range in ranges {
            attributed.addAttributes([
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.35),
                .foregroundColor: NSColor.labelColor,
            ], range: range)
        }

        // Say so when the preview stops short of the clip. The header advertises the
        // whole clip's size and the legend offers to scroll it, so without this ⌘↓
        // lands on character 8,000 looking exactly like the end of the text.
        if preview.count > Self.maxPreviewChars {
            let note = NSMutableParagraphStyle()
            note.paragraphSpacingBefore = 10
            attributed.append(NSAttributedString(
                string: "\n… preview truncated — pasting still sends the whole clip",
                attributes: [
                    .font: NSFont.systemFont(ofSize: bodyFont.pointSize - 1, weight: .medium),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: note,
                ]))
        }

        textView.textStorage?.setAttributedString(attributed)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pendingReveal = ranges.first
        needsLayout = true
    }

    /// Clear the preview (nothing highlighted).
    func clear() {
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        pendingReveal = nil
        needsLayout = true
    }

    // MARK: - Scrolling (driven from the key handlers)

    /// Scroll by whole lines: negative = up (toward the start), positive = down.
    func scroll(lines: Int) {
        scrollBy(CGFloat(lines) * lineHeight)
    }

    /// Scroll by most of a visible page, keeping a couple of lines of overlap so the
    /// reader keeps their place.
    func scroll(pages: Int) {
        let page = max(scrollView.contentView.bounds.height - lineHeight * 2, lineHeight)
        scrollBy(CGFloat(pages) * page)
    }

    /// Jump to the very start / very end of the preview.
    func scrollToEdge(start: Bool) {
        scrollTo(start ? 0 : maxScrollOffset)
    }

    private var lineHeight: CGFloat {
        let font = textView.font ?? bodyFont
        return textView.layoutManager?.defaultLineHeight(for: font) ?? font.boundingRectForFont.height
    }

    private var maxScrollOffset: CGFloat {
        max(textView.frame.height - scrollView.contentView.bounds.height, 0)
    }

    private func scrollBy(_ delta: CGFloat) {
        scrollTo(scrollView.contentView.bounds.origin.y + delta)
    }

    private func scrollTo(_ y: CGFloat) {
        let clamped = min(max(y, 0), maxScrollOffset)
        guard abs(clamped - scrollView.contentView.bounds.origin.y) > 0.5 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func clipViewDidScroll() {
        updateFade()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // The container's width is final now, so the text has wrapped to its real
        // height: reveal whatever `show` queued, then refresh the edge fades.
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        performPendingReveal()
        updateFade()
    }

    /// Scroll the first match into view — a third of the way down, so the line above
    /// it gives context. Without this, a match 30 lines into a clip would sit off
    /// the bottom of the preview and the pane would look like it showed nothing
    /// relevant.
    private func performPendingReveal() {
        guard let range = pendingReveal,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              bounds.width > 0 else { return }
        pendingReveal = nil
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let visible = scrollView.contentView.bounds.height
        guard rect.maxY > visible else { return } // already on screen
        scrollTo(rect.minY - visible / 3)
    }

    /// Recompute "is there more to see" and reflect it: the HUD's scroll hint, and
    /// a soft fade at whichever edge has content beyond it.
    private func updateFade() {
        let offset = scrollView.contentView.bounds.origin.y
        let maxOffset = maxScrollOffset
        let didOverflow = overflows
        overflows = maxOffset > 0.5
        if overflows != didOverflow { onOverflowChange?(overflows) }

        // The fade is a layer mask, so it only applies where there is a layer — the
        // overflow state above is deliberately computed first, since the HUD's hint
        // must be right whether or not this view has been layer-backed yet.
        guard let layer = scrollView.layer, bounds.height > 0 else { return }
        let moreAbove = offset > 0.5
        let moreBelow = offset < maxOffset - 0.5
        guard moreAbove || moreBelow else {
            layer.mask = nil
            return
        }

        let stop = min(Self.fadeHeight / bounds.height, 0.4)
        let opaque = NSColor.black.cgColor
        let clear = NSColor.black.withAlphaComponent(0).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true) // the mask must track scrolling instantly
        fadeMask.frame = scrollView.bounds
        fadeMask.locations = [0, NSNumber(value: Double(stop)), NSNumber(value: Double(1 - stop)), 1]
        fadeMask.colors = [
            moreAbove ? clear : opaque, opaque, opaque, moreBelow ? clear : opaque,
        ]
        layer.mask = fadeMask
        CATransaction.commit()
    }

    // MARK: - Text helpers

    /// How many lines a clip has, ignoring the leading blank lines and trailing
    /// whitespace the preview drops — and whether that number is only a floor
    /// (`partial`), because the clip is longer than `maxCountedBytes`.
    ///
    /// Counts UTF-8 bytes rather than `Character`s on purpose: the search list asks
    /// for this once per result on every keystroke, and grapheme-breaking megabyte
    /// clips there would stall typing. A newline is a single byte that cannot occur
    /// inside a multi-byte scalar, so the count is exact for everything scanned.
    /// Lone carriage returns are not counted — terminal output uses them to redraw a
    /// line in place, not to start a new one.
    nonisolated static func lineCount(of text: String) -> (lines: Int, partial: Bool) {
        let bytes = text.utf8
        var index = bytes.startIndex
        let end = bytes.endIndex
        var lines = 0
        var pendingBreaks = 0 // newlines seen with no content after them yet
        var scanned = 0

        while index < end {
            if scanned >= maxCountedBytes { return (lines, true) }
            let byte = bytes[index]
            scanned += 1
            switch byte {
            case 0x0A: // \n — only counts once something follows it
                if lines > 0 { pendingBreaks += 1 }
            case 0x20, 0x09, 0x0D: // space, tab, \r — not content on their own
                break
            default:
                lines = lines == 0 ? 1 : lines + pendingBreaks
                pendingBreaks = 0
            }
            index = bytes.index(after: index)
        }
        return (lines, false)
    }

    /// A clip's size, as both HUDs report it: `42 lines  ·  1,234 chars` (the line
    /// count is dropped for a one-liner). Describes the *whole* clip, so the label
    /// stays honest even though the preview itself is capped.
    ///
    /// Past `maxMeasuredBytes` it switches to a byte size — both because "12,345,678
    /// chars" tells you less than "12.3 MB", and because `String.count` walks grapheme
    /// clusters, which is work worth skipping on a clip that large.
    nonisolated static func sizeSummary(_ text: String) -> String {
        let size = text.utf8.count > maxMeasuredBytes
            ? text.utf8.count.formatted(.byteCount(style: .file))
            : (text.count == 1 ? "1 char" : "\(text.count.formatted()) chars")
        return [lineLabel(of: text), size].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// `42 lines` / `1,024+ lines`, or nil for a one-liner (where a line count says
    /// nothing). Shown in the bezel header, the search preview's meta line, and on
    /// every search result row — a one-line row would otherwise look identical
    /// whether the clip behind it is one line or two hundred.
    nonisolated static func lineLabel(of text: String) -> String? {
        let count = lineCount(of: text)
        guard count.lines > 1 else { return nil }
        return count.partial ? "\(count.lines.formatted())+ lines" : "\(count.lines.formatted()) lines"
    }

    /// The preview form of a clip — leading blank lines and trailing whitespace
    /// dropped, leading spaces on the first kept line preserved — plus how many
    /// leading characters were dropped, so match offsets can be shifted to match.
    /// Returns a slice, not a copy: callers cap it before materialising a `String`.
    /// The full text is still what gets pasted.
    nonisolated static func trimmedPreview(_ text: Substring) -> (text: Substring, dropped: Int) {
        var s = text
        var dropped = 0
        // "\r\n" is a *single* Character, so it has to be matched in its own right —
        // and it counts as one dropped character, which is exactly how
        // `ClipboardSearch` counts it when it reports matched offsets.
        while let f = s.first, f == "\n" || f == "\r" || f == "\r\n" {
            s = s.dropFirst()
            dropped += 1
        }
        while let l = s.last, l.isWhitespace { s = s.dropLast() }
        return (s, dropped)
    }

    nonisolated static func trimmedPreview(_ text: String) -> (text: Substring, dropped: Int) {
        trimmedPreview(text[...])
    }

    /// Turn per-character match offsets (into the original clip) into `NSRange`s
    /// over `preview`: shift by the trimmed prefix, drop anything past the preview
    /// cap, and merge runs of adjacent characters into one range each.
    nonisolated static func highlightRanges(in preview: String, matchedOffsets: [Int], dropped: Int) -> [NSRange] {
        guard !matchedOffsets.isEmpty, !preview.isEmpty else { return [] }
        let count = preview.count
        let shifted = matchedOffsets.map { $0 - dropped }.filter { $0 >= 0 && $0 < count }.sorted()
        guard !shifted.isEmpty else { return [] }

        // Merge adjacent offsets into runs, then convert each run once.
        var runs: [(start: Int, length: Int)] = []
        for offset in shifted {
            if var last = runs.last, last.start + last.length == offset {
                last.length += 1
                runs[runs.count - 1] = last
            } else {
                runs.append((offset, 1))
            }
        }
        return runs.compactMap { run in
            guard let lower = preview.index(preview.startIndex, offsetBy: run.start, limitedBy: preview.endIndex),
                  let upper = preview.index(lower, offsetBy: run.length, limitedBy: preview.endIndex)
            else { return nil }
            return NSRange(lower..<upper, in: preview)
        }
    }
}

/// The preview's text view: never takes focus (so the panel keeps receiving arrow
/// keys after a click) and offers no context menu over clipboard content.
private final class PreviewTextView: NSTextView {
    override var acceptsFirstResponder: Bool { false }
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}
