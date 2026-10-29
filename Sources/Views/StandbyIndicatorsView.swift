import Cocoa
import QuartzCore

final class StandbyIndicatorsView: NSView {
    var cpuUsage: Double = 0.0
    var batteryPercent: Int = 100
    var isBatteryCharging: Bool = false
    var isCapsLockOn: Bool = false
    var isMediaPlaying: Bool = false
    var eqPhase: Double = 0.0

    private let eqBarLayers: [CALayer] = (0..<5).map { _ in
        let layer = CALayer()
        layer.cornerRadius = 1.25
        layer.cornerCurve = .continuous
        layer.backgroundColor = NSColor.systemRed.cgColor
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        guard let layer = self.layer else { return }
        layer.shouldRasterize = true
        layer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        for bar in eqBarLayers {
            layer.addSublayer(bar)
        }
    }

    override func layout() {
        super.layout()
        updateEqualizerBars()
    }

    var cpuTier: Int {
        if cpuUsage > 75 { return 2 }
        if cpuUsage > 40 { return 1 }
        return 0
    }

    // MARK: - Dirty Rect Calculators for Partial Redraw
    private func layoutMetrics() -> (gap: CGFloat, hbX: CGFloat, capsX: CGFloat, capsW: CGFloat, batX: CGFloat, batW: CGFloat, eqX: CGFloat, eqW: CGFloat) {
        let w = bounds.width
        let heartbeatWidth: CGFloat = 16.0
        let capsSize = ("⇪" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .bold)])
        let boltW: CGFloat = isBatteryCharging ? 6.0 : 0.0
        let boltSpacing: CGFloat = isBatteryCharging ? 3.0 : 0.0
        let batText = "\(batteryPercent)%" as NSString
        let batSize = batText.size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)])
        let totalBatWidth = boltW + boltSpacing + batSize.width

        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 2.0
        let totalEqWidth: CGFloat = (5.0 * barWidth) + (4.0 * spacing) // 20.5 pt

        let totalContentWidth = heartbeatWidth + capsSize.width + totalBatWidth + totalEqWidth
        let gap = max(6.0, (w - totalContentWidth) / 5.0)

        let hbX = gap
        let capsX = hbX + heartbeatWidth + gap
        let batX = capsX + capsSize.width + gap
        let eqX = batX + totalBatWidth + gap

        return (gap, hbX, capsX, capsSize.width, batX, totalBatWidth, eqX, totalEqWidth)
    }

    func setMediaPlayingState(_ playing: Bool) {
        isMediaPlaying = playing
        if playing {
            layer?.shouldRasterize = false
        } else {
            layer?.shouldRasterize = true
            layer?.rasterizationScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        }
        updateEqualizerBars()
    }

    func updateEqualizerBars() {
        let h = bounds.height
        guard h < 32 else { return }

        let metrics = layoutMetrics()
        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 2.0

        let bars: [CGFloat]
        let color: CGColor
        if isMediaPlaying {
            let t = eqPhase
            let h1 = 5.0 + 3.5 * CGFloat(sin(t))
            let h2 = 8.0 + 5.5 * CGFloat(sin(t + 1.25))
            let h3 = 10.0 + 5.0 * CGFloat(sin(t + 2.5))
            let h4 = 7.5 + 4.5 * CGFloat(sin(t + 3.75))
            let h5 = 4.5 + 3.0 * CGFloat(sin(t + 5.0))
            bars = [max(3.0, h1), max(3.0, h2), max(3.0, h3), max(3.0, h4), max(3.0, h5)]
            color = NSColor.white.withAlphaComponent(0.95).cgColor
        } else {
            bars = [3.5, 3.5, 3.5, 3.5, 3.5]
            color = NSColor.systemRed.cgColor
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, barLayer) in eqBarLayers.enumerated() {
            let barH = bars[index]
            let barX = metrics.eqX + CGFloat(index) * (barWidth + spacing)
            let barY = (h - barH) / 2
            barLayer.frame = NSRect(x: barX, y: barY, width: barWidth, height: barH)
            barLayer.backgroundColor = color
        }
        CATransaction.commit()
    }

    func invalidateEqualizer() {
        updateEqualizerBars()
    }

    func invalidateCapsLock() {
        let metrics = layoutMetrics()
        let rect = NSRect(x: metrics.capsX - 3.0, y: 0, width: metrics.capsW + 6.0, height: bounds.height)
        setNeedsDisplay(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        guard h < 32 else { return }

        // 1. Dynamic dimensions for each element
        let heartbeatWidth: CGFloat = 16.0

        let capsColor: NSColor = isCapsLockOn ? NSColor.systemGreen : NSColor.systemRed
        let capsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: capsColor
        ]
        let capsString = "⇪" as NSString
        let capsSize = capsString.size(withAttributes: capsAttrs)

        let batColor: NSColor
        if batteryPercent >= 50 {
            batColor = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
        } else if batteryPercent >= 20 {
            batColor = .systemYellow
        } else {
            batColor = .systemRed
        }

        let boltW: CGFloat = isBatteryCharging ? 6.0 : 0.0
        let boltSpacing: CGFloat = isBatteryCharging ? 3.0 : 0.0
        let batText = "\(batteryPercent)%" as NSString
        let batAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: batColor
        ]
        let batSize = batText.size(withAttributes: batAttrs)
        let totalBatWidth = boltW + boltSpacing + batSize.width

        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 2.0
        let totalEqWidth: CGFloat = (5.0 * barWidth) + (4.0 * spacing) // 20.5 pt

        // 2. Dynamic equidistant layout
        let totalContentWidth = heartbeatWidth + capsSize.width + totalBatWidth + totalEqWidth
        let gap = max(6.0, (w - totalContentWidth) / 5.0)

        let hbX = gap
        let capsX = hbX + heartbeatWidth + gap
        let batX = capsX + capsSize.width + gap

        // 3. CPU Heartbeat ECG Waveform (Static vector path, colored by load tier)
        let cpuColor: NSColor
        if cpuUsage > 75 {
            cpuColor = .systemRed
        } else if cpuUsage > 40 {
            cpuColor = .systemOrange
        } else {
            cpuColor = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
        }

        let midY = h / 2
        let peakR: CGFloat = 5.2

        let hbPath = NSBezierPath()
        hbPath.move(to: NSPoint(x: hbX, y: midY))
        hbPath.line(to: NSPoint(x: hbX + 3.5, y: midY))
        hbPath.line(to: NSPoint(x: hbX + 5.5, y: midY - 1.5))
        hbPath.line(to: NSPoint(x: hbX + 8.0, y: midY + peakR))
        hbPath.line(to: NSPoint(x: hbX + 10.5, y: midY - 3.2))
        hbPath.line(to: NSPoint(x: hbX + 12.5, y: midY + 1.4))
        hbPath.line(to: NSPoint(x: hbX + heartbeatWidth, y: midY))

        hbPath.lineWidth = 1.3
        hbPath.lineCapStyle = .round
        hbPath.lineJoinStyle = .round
        cpuColor.setStroke()
        hbPath.stroke()

        // 4. Caps Lock (Red = OFF, Green = ON)
        capsString.draw(at: NSPoint(x: capsX, y: (h - capsSize.height) / 2), withAttributes: capsAttrs)

        // 5. Dynamic Battery (Vector bolt polygon + percentage)
        if isBatteryCharging {
            let boltPath = NSBezierPath()
            let bx = batX
            let by = (h - 11.0) / 2
            boltPath.move(to: NSPoint(x: bx + 3.8, y: by + 11.0))
            boltPath.line(to: NSPoint(x: bx + 0.5, y: by + 4.8))
            boltPath.line(to: NSPoint(x: bx + 3.2, y: by + 4.8))
            boltPath.line(to: NSPoint(x: bx + 2.2, y: by + 0.0))
            boltPath.line(to: NSPoint(x: bx + 6.0, y: by + 6.2))
            boltPath.line(to: NSPoint(x: bx + 3.3, y: by + 6.2))
            boltPath.close()
            batColor.setFill()
            boltPath.fill()
        }
        batText.draw(at: NSPoint(x: batX + boltW + boltSpacing, y: (h - batSize.height) / 2), withAttributes: batAttrs)

        // 6. Update CALayer Equalizer Bars
        updateEqualizerBars()
    }
}
