import Cocoa

final class MediaControlCard: NSView {
    private let titleLabel = NSTextField(labelWithString: "Now Playing")
    let statusLabel = NSTextField(labelWithString: "● Idle")
    let trackTitleLabel = NSTextField(labelWithString: "No Media")
    let trackArtistLabel = NSTextField(labelWithString: "Paused")
    let prevBtn = NSButton()
    let playPauseBtn = NSButton()
    let nextBtn = NSButton()

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

        // Header: "Now Playing" & Status
        titleLabel.frame = NSRect(x: 12, y: bounds.height - 22, width: 85, height: 14)
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        addSubview(titleLabel)

        statusLabel.frame = NSRect(x: bounds.width - 82, y: bounds.height - 22, width: 70, height: 14)
        statusLabel.alignment = .right
        statusLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        statusLabel.textColor = NSColor.systemRed
        addSubview(statusLabel)

        // Track Title
        trackTitleLabel.frame = NSRect(x: 12, y: bounds.height - 42, width: bounds.width - 24, height: 16)
        trackTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        trackTitleLabel.textColor = .white
        trackTitleLabel.cell?.lineBreakMode = .byTruncatingTail
        trackTitleLabel.isBezeled = false
        trackTitleLabel.drawsBackground = false
        trackTitleLabel.isEditable = false
        trackTitleLabel.isSelectable = false
        addSubview(trackTitleLabel)

        // Track Artist
        trackArtistLabel.frame = NSRect(x: 12, y: bounds.height - 56, width: bounds.width - 24, height: 13)
        trackArtistLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        trackArtistLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        trackArtistLabel.cell?.lineBreakMode = .byTruncatingTail
        trackArtistLabel.isBezeled = false
        trackArtistLabel.drawsBackground = false
        trackArtistLabel.isEditable = false
        trackArtistLabel.isSelectable = false
        addSubview(trackArtistLabel)

        // Buttons
        let btnSize: CGFloat = 28
        let y: CGFloat = 8
        let totalBtnW = (btnSize * 3) + 20
        let startX = (bounds.width - totalBtnW) / 2

        func styleBtn(_ btn: NSButton, title: String, x: CGFloat) {
            btn.frame = NSRect(x: x, y: y, width: btnSize, height: btnSize)
            btn.title = title
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            btn.layer?.cornerRadius = btnSize / 2
            btn.layer?.cornerCurve = .continuous
            btn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            btn.contentTintColor = .white
            addSubview(btn)
        }

        styleBtn(prevBtn, title: "⏮", x: startX)
        styleBtn(playPauseBtn, title: "⏯", x: startX + btnSize + 10)
        styleBtn(nextBtn, title: "⏭", x: startX + (btnSize + 10) * 2)
    }

    func updateTrack(isPlaying: Bool, title: String?, artist: String?) {
        if isPlaying {
            statusLabel.stringValue = "● Playing"
            statusLabel.textColor = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
            trackTitleLabel.stringValue = (title != nil && !title!.isEmpty) ? title! : "Audio Playing"
            trackArtistLabel.stringValue = (artist != nil && !artist!.isEmpty) ? artist! : "System Media"
        } else {
            statusLabel.stringValue = "● Idle"
            statusLabel.textColor = NSColor.systemRed
            trackTitleLabel.stringValue = (title != nil && !title!.isEmpty) ? title! : "No Media"
            trackArtistLabel.stringValue = (artist != nil && !artist!.isEmpty) ? artist! : "Paused"
        }
    }
}
