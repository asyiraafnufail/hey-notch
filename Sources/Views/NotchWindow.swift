import Cocoa

final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

final class NotchView: NSView {
    var onNotchClick: (() -> Void)?
    var onDragOver: (() -> Void)?
    var onFileDropped: (([URL]) -> Void)?

    let standbyView = StandbyIndicatorsView()

    var cpuUsage: Double {
        get { standbyView.cpuUsage }
        set { standbyView.cpuUsage = newValue }
    }
    var batteryPercent: Int {
        get { standbyView.batteryPercent }
        set { standbyView.batteryPercent = newValue }
    }
    var isBatteryCharging: Bool {
        get { standbyView.isBatteryCharging }
        set { standbyView.isBatteryCharging = newValue }
    }
    var isCapsLockOn: Bool {
        get { standbyView.isCapsLockOn }
        set { standbyView.isCapsLockOn = newValue }
    }
    var isMediaPlaying: Bool {
        get { standbyView.isMediaPlaying }
        set { standbyView.isMediaPlaying = newValue }
    }
    var eqPhase: Double {
        get { standbyView.eqPhase }
        set { standbyView.eqPhase = newValue }
    }

    var isExpanded: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        registerForDraggedTypes([.fileURL])
        standbyView.wantsLayer = true
        standbyView.frame = bounds
        standbyView.autoresizingMask = [.width, .height]
        addSubview(standbyView)
    }

    override func layout() {
        super.layout()
        standbyView.frame = bounds
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !isExpanded {
            onDragOver?()
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return false
        }
        onFileDropped?(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()

        let w = bounds.width
        let h = bounds.height

        // Continuous corner radius interpolation (zero sudden jumps during expand/collapse)
        let progress = min(1.0, max(0.0, (h - 24.0) / (176.0 - 24.0)))
        let earRadius: CGFloat = 6.0 + (3.0 * progress)
        let bottomRadius: CGFloat = 11.0 + (13.0 * progress)
        let notchWidth = w - (2 * earRadius)

        let path = NSBezierPath()

        // 1. Sudut kiri atas
        path.move(to: NSPoint(x: 0, y: h))

        // 2. Telinga kiri atas (concave)
        path.appendArc(
            withCenter: NSPoint(x: 0, y: h - earRadius),
            radius: earRadius,
            startAngle: 90,
            endAngle: 0,
            clockwise: true
        )

        // 3. Garis vertikal kiri
        path.line(to: NSPoint(x: earRadius, y: bottomRadius))

        // 4. Sudut kiri bawah (convex)
        path.appendArc(
            withCenter: NSPoint(x: earRadius + bottomRadius, y: bottomRadius),
            radius: bottomRadius,
            startAngle: 180,
            endAngle: 270,
            clockwise: false
        )

        // 5. Garis horizontal bawah
        path.line(to: NSPoint(x: earRadius + notchWidth - bottomRadius, y: 0))

        // 6. Sudut kanan bawah (convex)
        path.appendArc(
            withCenter: NSPoint(x: earRadius + notchWidth - bottomRadius, y: bottomRadius),
            radius: bottomRadius,
            startAngle: 270,
            endAngle: 360,
            clockwise: false
        )

        // 7. Garis vertikal kanan
        path.line(to: NSPoint(x: earRadius + notchWidth, y: h - earRadius))

        // 8. Telinga kanan atas (concave)
        path.appendArc(
            withCenter: NSPoint(x: w, y: h - earRadius),
            radius: earRadius,
            startAngle: 180,
            endAngle: 90,
            clockwise: true
        )

        // 9. Tutup ke kiri atas
        path.line(to: NSPoint(x: 0, y: h))
        path.close()
        path.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onNotchClick?()
    }
}
