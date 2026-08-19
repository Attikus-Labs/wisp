import AppKit

/// The search HUD, shown when you press `/` in the bezel (or the search hot key).
/// It mirrors the bezel's look — same `.hudWindow` material, 18pt rounded mask,
/// framed container and accent highlight — but trades the single-clip carousel for
/// a live-filtered list:
///
///   • a search field row (magnifier · query · "3 / 7" counter);
///   • a scrolling result list, each row a one-line snippet with the matched text
///     emphasised, and the source app plus the clip's line count on the right (so a
///     one-line row never hides that the clip runs on); the selected row is
///     accent-tinted;
///   • a framed preview pane showing the highlighted clip — wrapped, scrollable, and
///     scrolled to the first match, so a hit 30 lines into a clip is what you see;
///   • the same paste-shortcut legend as the bezel.
///
/// The view renders only; selection is driven from `BezelController` via the keyDown
/// monitor, and paste reads the selected row back. Full text is always pasted.
@MainActor
final class SearchView: BezelEffectView {
    static let size = NSSize(width: 506, height: 524)

    /// One displayable result: the entry to paste, its highlighted snippet, the
    /// character offsets that matched (so the preview can highlight and reveal them),
    /// and the source app's name.
    ///
    /// The right-hand meta line (source · line count) is assembled in
    /// `tableView(_:viewFor:)` rather than here, because counting a clip's lines
    /// means scanning it: doing that for every result while rebuilding the list on
    /// every keystroke cost ~21ms per keypress on a 200-entry ring of large clips.
    /// The table only builds views for the rows on screen, so this way about eight
    /// clips get scanned instead of two hundred.
    struct Row {
        let item: ClipboardItem
        let snippet: NSAttributedString
        let source: String
        let matchedOffsets: [Int]

        init(item: ClipboardItem, snippet: NSAttributedString, source: String, matchedOffsets: [Int] = []) {
            self.item = item
            self.snippet = snippet
            self.source = source
            self.matchedOffsets = matchedOffsets
        }
    }

    /// Fired as the query text changes (drives re-filtering in the controller).
    var onQueryChange: ((String) -> Void)?
    /// Fired on double-click of a row (controller pastes it plain).
    var onActivate: (() -> Void)?

    private let icon = NSImageView()
    private let queryField = NSTextField()
    private let counter = NSTextField(labelWithString: "")
    private let divider = NSView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let previewContainer = NSView()
    private let preview = ClipPreview(fontSize: 13)
    private let previewMeta = NSTextField(labelWithString: "")
    private let legend = NSTextField(labelWithString: "")

    private var rows: [Row] = []
    /// Legend state, kept so the scroll hint can be toggled without re-deriving the
    /// rest of the line: whether the highlighted clip looks like terminal output,
    /// and whether anything is highlighted at all.
    private var highlightReflow = false
    private var hasSelection = false

    /// The list is sized to its content (capped) rather than filling the panel, so
    /// the preview can claim the leftover space. Updated in `show(rows:)`.
    private var listHeight: NSLayoutConstraint!
    /// Floor for the preview pane, so the list can never squeeze it out of existence.
    private let minPreviewHeight: CGFloat = 96
    /// Row unit = row height + inter-row spacing; the list shows up to this many
    /// rows before it scrolls.
    private let rowUnit: CGFloat = 32
    private let maxVisibleRows = 8
    private let emptyListHeight: CGFloat = 64

    var query: String { queryField.stringValue }

    /// Index of the highlighted result, or nil when there are no matches.
    var selectedIndex: Int? { rows.isEmpty ? nil : tableView.selectedRow }

    /// The currently highlighted entry, if any.
    var selectedItem: ClipboardItem? {
        guard let i = selectedIndex, rows.indices.contains(i) else { return nil }
        return rows[i].item
    }

    init() {
        super.init(size: SearchView.size) // material, rounded mask & scrim live in the base

        buildSearchRow()
        buildList()
        buildPreview()
        buildLegend()
        activateConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API (driven by BezelController)

    /// Make the query field the window's first responder so typing lands in search.
    func focusQueryField() {
        window?.makeFirstResponder(queryField)
        // Put the caret at the end of any existing text.
        queryField.currentEditor()?.selectedRange = NSRange(location: query.count, length: 0)
    }

    /// Reset to an empty query (used when ⎋ clears the field before exiting search).
    func clearQuery() {
        queryField.stringValue = ""
    }

    /// Replace the result list. Selection resets to the top match; the preview and
    /// counter follow.
    func show(rows: [Row]) {
        self.rows = rows
        tableView.reloadData()
        emptyLabel.isHidden = !rows.isEmpty
        // Size the list to its content (capped) so the preview fills what's left.
        listHeight.constant = rows.isEmpty
            ? emptyListHeight
            : CGFloat(min(rows.count, maxVisibleRows)) * rowUnit
        if rows.isEmpty {
            emptyLabel.stringValue = query.isEmpty ? "No clips yet" : "No clips match “\(query)”"
            updatePreview()
            updateCounter()
        } else {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
            updatePreview()
            updateCounter()
        }
    }

    /// Move the highlight by `delta` rows, clamped to the list, and keep it visible.
    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + delta, 0), rows.count - 1)
        guard next != current else { return }
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        // (updatePreview/updateCounter run from the selection-change delegate.)
    }

    // MARK: - Scrolling the preview (driven by BezelController)

    func scrollPreview(lines: Int) { preview.scroll(lines: lines) }
    func scrollPreview(pages: Int) { preview.scroll(pages: pages) }
    func scrollPreviewToEdge(start: Bool) { preview.scrollToEdge(start: start) }

    // MARK: - Build

    private func buildSearchRow() {
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.font = .systemFont(ofSize: 16)
        queryField.textColor = .labelColor
        queryField.isBezeled = false
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.lineBreakMode = .byTruncatingTail
        queryField.cell?.usesSingleLineMode = true
        queryField.placeholderString = "Search clipboard…"
        queryField.delegate = self

        configureLabel(counter, font: .systemFont(ofSize: 11, weight: .semibold), color: .tertiaryLabelColor)
        counter.alignment = .right

        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        [icon, queryField, counter, divider].forEach(addSubview)
    }

    private func buildList() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 30
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        configureLabel(emptyLabel, font: .systemFont(ofSize: 13), color: .tertiaryLabelColor)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
    }

    private func buildPreview() {
        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 8
        previewContainer.layer?.borderWidth = 1
        previewContainer.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        previewContainer.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        // The hint only makes sense while there's something to scroll to.
        preview.onOverflowChange = { [weak self] _ in self?.refreshLegend() }

        configureLabel(previewMeta, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)

        addSubview(previewContainer)
        previewContainer.addSubview(preview)
        previewContainer.addSubview(previewMeta)
    }

    private func buildLegend() {
        configureLabel(legend, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
        legend.alignment = .center
        // One line, always: on a card clamped narrow the legend would otherwise wrap
        // and eat the preview's height instead of ellipsising.
        legend.maximumNumberOfLines = 1
        legend.lineBreakMode = .byTruncatingTail
        addSubview(legend)
    }

    private func activateConstraints() {
        listHeight = scrollView.heightAnchor.constraint(equalToConstant: emptyListHeight)
        // Deliberately below `fittingSizeCompression` (50): a window laid out with
        // Auto Layout can never be smaller than its content view's fitting size, so
        // any stronger height here would become a floor on the *window* — and on a
        // short screen the card would grow past the display rather than clamping to
        // it. At this priority the list still gets the height it asks for whenever
        // there's room, and gives way to the preview's minimum when there isn't (it
        // scrolls, so nothing is lost).
        listHeight.priority = NSLayoutConstraint.Priority(
            NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1)
        NSLayoutConstraint.activate([
            listHeight,
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            queryField.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            queryField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),

            counter.firstBaselineAnchor.constraint(equalTo: queryField.firstBaselineAnchor),
            counter.leadingAnchor.constraint(greaterThanOrEqualTo: queryField.trailingAnchor, constant: 10),
            counter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            divider.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // List: pinned at the top, sized to its content (listHeight, set in
            // show(rows:)) so the preview below can grow into the leftover space.
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            // Preview: fills from just below the list down to the legend.
            previewContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            previewContainer.bottomAnchor.constraint(equalTo: legend.topAnchor, constant: -12),

            previewContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: minPreviewHeight),

            // The preview fills the frame above the meta line; it has no intrinsic
            // height, so a long clip scrolls rather than pushing the card taller.
            preview.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            preview.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            preview.bottomAnchor.constraint(equalTo: previewMeta.topAnchor, constant: -8),

            previewMeta.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            previewMeta.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            previewMeta.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -10),

            legend.centerXAnchor.constraint(equalTo: centerXAnchor),
            legend.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            legend.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            legend.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Rendering

    private func updateCounter() {
        if rows.isEmpty {
            counter.stringValue = query.isEmpty ? "" : "no matches"
        } else {
            let sel = max(tableView.selectedRow, 0)
            counter.stringValue = "\(sel + 1) / \(rows.count)"
        }
    }

    private func updatePreview() {
        guard let index = selectedIndex, rows.indices.contains(index) else {
            preview.clear()
            previewMeta.stringValue = ""
            highlightReflow = false
            hasSelection = false
            refreshLegend()
            return
        }
        let row = rows[index]
        let item = row.item
        highlightReflow = TerminalText.looksLikeTerminalOutput(item.text)
        hasSelection = true
        // Highlight what matched and scroll it into view: a hit 30 lines down was
        // invisible when the pane always rendered from the top of the clip.
        preview.show(text: item.text, monospaced: highlightReflow, matchedOffsets: row.matchedOffsets)
        let source = AppDisplayName.resolve(item.sourceBundleID)
        previewMeta.stringValue = [source, ClipPreview.sizeSummary(item.text)]
            .compactMap { $0 }.joined(separator: "  ·  ")
        refreshLegend()
    }

    private func refreshLegend() {
        legend.attributedStringValue = legendLine(highlightReflow: highlightReflow,
                                                  enabled: hasSelection,
                                                  scrollable: preview.overflows)
    }

    /// `↑↓ move    ⏎ plain   ⌥⏎ formatted   ⇧⏎ reflow    esc`. ⇧⏎ brightens when the
    /// highlighted clip looks like terminal output (where reflow helps); the paste
    /// hints dim entirely when there's nothing to paste; `⌥↕ scroll` joins the line
    /// only when the highlighted clip is taller than the preview pane.
    private func legendLine(highlightReflow: Bool, enabled: Bool, scrollable: Bool) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let base = enabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: base]
        var reflow = normal
        if enabled, highlightReflow { reflow[.foregroundColor] = NSColor.labelColor }

        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "↑↓ move      ", attributes: dim))
        line.append(NSAttributedString(string: "⏎ plain    ⌥⏎ formatted    ", attributes: normal))
        line.append(NSAttributedString(string: "⇧⏎ reflow", attributes: reflow))
        if scrollable {
            line.append(NSAttributedString(string: "      ⌥↕ scroll", attributes: dim))
        }
        line.append(NSAttributedString(string: "      esc", attributes: dim))
        return line
    }

    private func configureLabel(_ field: NSTextField, font: NSFont, color: NSColor) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.allowsDefaultTighteningForTruncation = true
    }

    @objc private func rowDoubleClicked() {
        guard tableView.clickedRow >= 0 else { return }
        onActivate?()
    }
}

// MARK: - Query field

extension SearchView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onQueryChange?(queryField.stringValue)
    }
}

// MARK: - Table data source / delegate

extension SearchView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("accentRow")
        let view = (tableView.makeView(withIdentifier: id, owner: self) as? AccentRowView) ?? {
            let v = AccentRowView()
            v.identifier = id
            return v
        }()
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("clipCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ClipCellView)
            ?? ClipCellView(identifier: id)
        // Assembled here, for visible rows only — see `Row`.
        let entry = rows[row]
        let meta = [entry.source.isEmpty ? nil : entry.source, ClipPreview.lineLabel(of: entry.item.text)]
            .compactMap { $0 }.joined(separator: "  ·  ")
        cell.configure(snippet: entry.snippet, meta: meta)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
        updateCounter()
    }
}

/// A result row whose selection fill matches the bezel's active-hint accent (the
/// system blue at 0.30 alpha, rounded) rather than the default list highlight.
private final class AccentRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let inset = bounds.insetBy(dx: 2, dy: 0)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.30).setFill()
        path.fill()
    }
}

/// One result line: a highlighted one-line snippet on the left, the source app and
/// the clip's line count on the right.
private final class ClipCellView: NSTableCellView {
    private let snippetField = NSTextField(labelWithString: "")
    private let metaField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        for field in [snippetField, metaField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isBezeled = false
            field.drawsBackground = false
            field.isSelectable = false
            field.lineBreakMode = .byTruncatingTail
            addSubview(field)
        }
        snippetField.font = .systemFont(ofSize: 13)
        snippetField.textColor = .labelColor
        metaField.font = .systemFont(ofSize: 11)
        metaField.textColor = .tertiaryLabelColor
        metaField.alignment = .right
        metaField.setContentHuggingPriority(.required, for: .horizontal)
        metaField.setContentCompressionResistancePriority(.required, for: .horizontal)
        snippetField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            snippetField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            snippetField.centerYAnchor.constraint(equalTo: centerYAnchor),
            snippetField.trailingAnchor.constraint(lessThanOrEqualTo: metaField.leadingAnchor, constant: -10),

            metaField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            metaField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(snippet: NSAttributedString, meta: String) {
        // A label draws an attributed string with that string's *own* paragraph
        // style, which defaults to word wrapping — so a snippet wider than the row
        // wrapped and spilled over the row below it (rows are a fixed 30pt). The
        // field's own `lineBreakMode` doesn't override that, so stamp the style on.
        let line = NSMutableAttributedString(attributedString: snippet)
        line.addAttribute(.paragraphStyle, value: Self.singleLine,
                          range: NSRange(location: 0, length: line.length))
        snippetField.attributedStringValue = line
        metaField.stringValue = meta
    }

    /// One line, ellipsised at the tail — see `configure`.
    private static let singleLine: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
}
