import Cocoa

final class DropShelfView: NSView, NSDraggingSource {
    var storedURLs: [URL] = [] {
        didSet { updateUI() }
    }

    private var isHighlighted: Bool = false
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10.0
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        registerForDraggedTypes([.fileURL])

        iconView.frame = NSRect(x: (bounds.width - 32) / 2, y: 48, width: 32, height: 32)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.frame = NSRect(x: 10, y: 26, width: bounds.width - 20, height: 16)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        titleLabel.cell?.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        subLabel.frame = NSRect(x: 10, y: 10, width: bounds.width - 20, height: 14)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        subLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        addSubview(subLabel)

        clearButton.frame = NSRect(x: bounds.width - 24, y: bounds.height - 24, width: 18, height: 18)
        clearButton.title = "✕"
        clearButton.isBordered = false
        clearButton.wantsLayer = true
        clearButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        clearButton.layer?.cornerRadius = 9
        clearButton.layer?.cornerCurve = .continuous
        clearButton.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        clearButton.contentTintColor = .white
        clearButton.target = self
        clearButton.action = #selector(clearFiles)
        clearButton.isHidden = true
        addSubview(clearButton)

        updateUI()
    }

    @objc func clearFiles() {
        storedURLs.removeAll()
    }

    private func updateUI() {
        if let firstURL = storedURLs.first {
            iconView.image = NSWorkspace.shared.icon(forFile: firstURL.path)
            titleLabel.stringValue = firstURL.lastPathComponent
            titleLabel.textColor = .white

            let count = storedURLs.count
            if count > 1 {
                subLabel.stringValue = "\(count) files (Drag out)"
            } else {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: firstURL.path),
                   let size = attrs[.size] as? Int64 {
                    let mb = Double(size) / (1024.0 * 1024.0)
                    subLabel.stringValue = mb >= 1.0 ? String(format: "%.1f MB (Drag out)", mb) : String(format: "%.0f KB (Drag out)", Double(size) / 1024.0)
                } else {
                    subLabel.stringValue = "Drag out to apps"
                }
            }
            clearButton.isHidden = false
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        } else {
            iconView.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Drop") ?? NSImage(systemSymbolName: "doc", accessibilityDescription: "File")
            titleLabel.stringValue = "Drop Files Here"
            titleLabel.textColor = NSColor.white.withAlphaComponent(0.65)
            subLabel.stringValue = "Temporary shelf"
            clearButton.isHidden = true
            layer?.borderColor = isHighlighted ? NSColor.systemBlue.cgColor : NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    // MARK: - Dragging Destination
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        layer?.borderColor = NSColor.systemBlue.cgColor
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderColor = storedURLs.isEmpty ? NSColor.white.withAlphaComponent(0.12).cgColor : NSColor.systemBlue.withAlphaComponent(0.6).cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }
        storedURLs = urls
        return true
    }

    // MARK: - Dragging Source
    override func mouseDragged(with event: NSEvent) {
        guard !storedURLs.isEmpty else { return }
        let items = storedURLs.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let rect = NSRect(x: (self.bounds.width - 32) / 2, y: 48, width: 32, height: 32)
            item.setDraggingFrame(rect, contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2, let first = storedURLs.first {
            NSWorkspace.shared.open(first)
        }
    }
}
