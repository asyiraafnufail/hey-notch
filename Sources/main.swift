import Cocoa
import QuartzCore
import IOKit.ps
import Darwin
import CoreAudio

final class NotchView: NSView {
    var onNotchClick: (() -> Void)?
    var isExpanded: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    var cpuUsage: Double = 0.0
    var batteryPercent: Int = 100
    var isBatteryCharging: Bool = false
    var isCapsLockOn: Bool = false
    var isMediaPlaying: Bool = false
    var eqPhase: Double = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()

        let w = bounds.width
        let h = bounds.height
        let earRadius: CGFloat = isExpanded ? 9 : 6
        let bottomRadius: CGFloat = isExpanded ? 24 : 11
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

        // Indikator Standby (hanya muncul saat notch normal / tidak expanded)
        if !isExpanded {
            // 1. Hitung dimensi tiap elemen secara dinamis
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
            let batText = isBatteryCharging ? "⚡\(batteryPercent)%" : "\(batteryPercent)%"
            let batAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: batColor
            ]
            let batSize = (batText as NSString).size(withAttributes: batAttrs)

            let barWidth: CGFloat = 2.5
            let spacing: CGFloat = 2.0
            let totalEqWidth: CGFloat = (5.0 * barWidth) + (4.0 * spacing) // 20.5 pt

            // 2. Hitung dynamic gap (4 ikon + 5 interval/margin sama rata presisi)
            // Menjamin jarak: Margin Kiri = Gap 1 = Gap 2 = Gap 3 = Margin Kanan
            let totalContentWidth = heartbeatWidth + capsSize.width + batSize.width + totalEqWidth
            let gap = max(6.0, (w - totalContentWidth) / 5.0)

            // 3. Posisi X masing-masing elemen (otomatis bergeser saat charging/nambah ikon)
            let hbX = gap
            let capsX = hbX + heartbeatWidth + gap
            let batX = capsX + capsSize.width + gap
            let eqX = batX + batSize.width + gap

            // 4. Render elemen 1: CPU Heartbeat ECG Waveform (Statis, warna indikator stress CPU)
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

            // Render elemen 2: Caps Lock (Merah saat OFF, Hijau saat ON)
            capsString.draw(at: NSPoint(x: capsX, y: (h - capsSize.height) / 2), withAttributes: capsAttrs)

            // Render elemen 3: Baterai Dinamis (tetap simetris dan menyesuaikan otomatis)
            (batText as NSString).draw(at: NSPoint(x: batX, y: (h - batSize.height) / 2), withAttributes: batAttrs)

            // Render elemen 4: Equalizer 5 Bar
            let eqColor: NSColor = isMediaPlaying ? NSColor.white.withAlphaComponent(0.95) : NSColor.systemRed
            eqColor.setFill()

            let bars: [CGFloat]
            if isMediaPlaying {
                let t = eqPhase
                let h1 = 5.0 + 3.5 * CGFloat(sin(t))
                let h2 = 8.0 + 5.5 * CGFloat(sin(t + 1.25))
                let h3 = 10.0 + 5.0 * CGFloat(sin(t + 2.5))
                let h4 = 7.5 + 4.5 * CGFloat(sin(t + 3.75))
                let h5 = 4.5 + 3.0 * CGFloat(sin(t + 5.0))
                bars = [max(3.0, h1), max(3.0, h2), max(3.0, h3), max(3.0, h4), max(3.0, h5)]
            } else {
                bars = [3.5, 3.5, 3.5, 3.5, 3.5]
            }

            for (index, barH) in bars.enumerated() {
                let barX = eqX + CGFloat(index) * (barWidth + spacing)
                let barY = (h - barH) / 2
                let barPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barH), xRadius: 1.25, yRadius: 1.25)
                barPath.fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !isExpanded {
            onNotchClick?()
        }
    }
}

final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NotchPanel!
    var notchView: NotchView!
    var statusItem: NSStatusItem!
    var spacerStatusItem: NSStatusItem?
    var timer: Timer?
    var statsTimer: Timer?

    // UI Kontainer Expanded (Hardware Details)
    var expandedContainer: NSView!
    var closeButton: NSButton!
    var titleLabel: NSTextField!
    var cpuValueLabel: NSTextField!
    var cpuFillView: NSView!
    var ramValueLabel: NSTextField!
    var ramFillView: NSView!
    var thermalValueLabel: NSTextField!

    private var isNotchVisible: Bool = true
    private var isExpanded: Bool = false
    private var isTransitioning: Bool = false
    private var outsideClickMonitor: Any?

    private var previousCpuInfo = host_cpu_load_info()
    private var hasPreviousCpu = false
    private var statsTick: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenuBarBarrier()
        setupNotchWindow()
        setupExpandedUI()
        setupObservers()
        refreshStandbyStats()
        updateVisibility()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⎊"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Hey Notch", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupMenuBarBarrier() {
        spacerStatusItem = NSStatusBar.system.statusItem(withLength: 20)
        if let button = spacerStatusItem?.button {
            button.title = ""
            button.appearsDisabled = true
        }
    }

    private func calculateFrames(for screen: NSScreen) -> (shown: NSRect, hidden: NSRect, expanded: NSRect) {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        let detectedMenuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let height: CGFloat = detectedMenuBarHeight > 0 ? detectedMenuBarHeight : 24
        let width: CGFloat = 176
        let x = (screenFrame.width - width) / 2

        let shownY = screenFrame.height - height
        let hiddenY = screenFrame.height + 40

        let shownFrame = NSRect(x: x, y: shownY, width: width, height: height)
        let hiddenFrame = NSRect(x: x, y: hiddenY, width: width, height: height)

        // Dimensi membesar (Expanded): 420x150pt
        let expWidth: CGFloat = 420
        let expHeight: CGFloat = 150
        let expX = (screenFrame.width - expWidth) / 2
        let expY = screenFrame.height - expHeight
        let expandedFrame = NSRect(x: expX, y: expY, width: expWidth, height: expHeight)

        return (shownFrame, hiddenFrame, expandedFrame)
    }

    private func setupNotchWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let (shownFrame, _, _) = calculateFrames(for: screen)

        window = NotchPanel(
            contentRect: shownFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.alphaValue = 1.0

        notchView = NotchView(frame: NSRect(origin: .zero, size: shownFrame.size))
        notchView.wantsLayer = true
        notchView.onNotchClick = { [weak self] in
            self?.expandNotch()
        }
        window.contentView = notchView
        window.orderFrontRegardless()
    }

    private func makeLabel(text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = font
        tf.textColor = color
        tf.alignment = alignment
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.isSelectable = false
        return tf
    }

    private func makeProgressBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> (track: NSView, fill: NSView) {
        let track = NSView(frame: NSRect(x: x, y: y, width: width, height: height))
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        track.layer?.cornerRadius = height / 2

        let fill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: height))
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.systemBlue.cgColor
        fill.layer?.cornerRadius = height / 2
        track.addSubview(fill)

        return (track, fill)
    }

    private func setupExpandedUI() {
        let expWidth: CGFloat = 420
        let expHeight: CGFloat = 150
        expandedContainer = NSView(frame: NSRect(x: 0, y: 0, width: expWidth, height: expHeight))
        expandedContainer.wantsLayer = true
        expandedContainer.alphaValue = 0.0
        expandedContainer.isHidden = true

        let btnSize: CGFloat = 24
        let btnY: CGFloat = expHeight - btnSize - 16

        // 1. Header: Judul & Tombol Close
        titleLabel = makeLabel(text: "Hardware Status", font: .systemFont(ofSize: 12.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.9))
        titleLabel.frame = NSRect(x: 22, y: btnY + 2, width: 200, height: 20)
        expandedContainer.addSubview(titleLabel)

        closeButton = NSButton(frame: NSRect(x: expWidth - btnSize - 20, y: btnY, width: btnSize, height: btnSize))
        closeButton.title = "✕"
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        closeButton.layer?.cornerRadius = btnSize / 2
        closeButton.target = self
        closeButton.action = #selector(collapseNotch)
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        closeButton.contentTintColor = .white
        expandedContainer.addSubview(closeButton)

        // 2. CPU Usage Bar
        let cpuTitle = makeLabel(text: "CPU Usage", font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.65))
        cpuTitle.frame = NSRect(x: 22, y: 86, width: 120, height: 16)
        expandedContainer.addSubview(cpuTitle)

        cpuValueLabel = makeLabel(text: "0%", font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: .white, alignment: .right)
        cpuValueLabel.frame = NSRect(x: 200, y: 86, width: 198, height: 16)
        expandedContainer.addSubview(cpuValueLabel)

        let (cpuTrack, cpuFill) = makeProgressBar(x: 22, y: 77, width: 376, height: 5)
        cpuFillView = cpuFill
        expandedContainer.addSubview(cpuTrack)

        // 3. RAM Usage Bar
        let ramTitle = makeLabel(text: "Memory (RAM)", font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.65))
        ramTitle.frame = NSRect(x: 22, y: 53, width: 120, height: 16)
        expandedContainer.addSubview(ramTitle)

        ramValueLabel = makeLabel(text: "0.0 / 0.0 GB (0%)", font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: .white, alignment: .right)
        ramValueLabel.frame = NSRect(x: 160, y: 53, width: 238, height: 16)
        expandedContainer.addSubview(ramValueLabel)

        let (ramTrack, ramFill) = makeProgressBar(x: 22, y: 44, width: 376, height: 5)
        ramFillView = ramFill
        expandedContainer.addSubview(ramTrack)

        // 4. Thermal & Throttle Status
        let thermalTitle = makeLabel(text: "Thermal / Throttle", font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.65))
        thermalTitle.frame = NSRect(x: 22, y: 16, width: 140, height: 18)
        expandedContainer.addSubview(thermalTitle)

        thermalValueLabel = makeLabel(text: "● Normal (Optimal)", font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0), alignment: .right)
        thermalValueLabel.frame = NSRect(x: 170, y: 16, width: 228, height: 18)
        expandedContainer.addSubview(thermalValueLabel)

        notchView.addSubview(expandedContainer)
    }

    @objc private func expandNotch() {
        guard !isExpanded, !isTransitioning, isNotchVisible else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        isTransitioning = true
        isExpanded = true
        notchView.isExpanded = true

        updateExpandedHardwareStats()

        let (_, _, expandedFrame) = calculateFrames(for: screen)
        expandedContainer.frame = NSRect(origin: .zero, size: expandedFrame.size)
        expandedContainer.isHidden = false

        enableOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            // Durasi 0.35s pegas Apple Fluid (mulus, elegan, presisi)
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(expandedFrame, display: true)
            expandedContainer.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            self?.isTransitioning = false
        })
    }

    @objc private func collapseNotch() {
        guard isExpanded, !isTransitioning else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        isTransitioning = true
        isExpanded = false
        notchView.isExpanded = false

        disableOutsideClickMonitor()

        let (shownFrame, _, _) = calculateFrames(for: screen)

        NSAnimationContext.runAnimationGroup({ context in
            // Durasi 0.28s menciut mulus kembali ke notch normal
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            expandedContainer.animator().alphaValue = 0.0
            window.animator().setFrame(shownFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.expandedContainer.isHidden = true
            self.isTransitioning = false
        })
    }

    private func enableOutsideClickMonitor() {
        disableOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.isExpanded else { return }
            let mouseLocation = NSEvent.mouseLocation
            if !self.window.frame.contains(mouseLocation) {
                DispatchQueue.main.async {
                    self.collapseNotch()
                }
            }
        }
    }

    private func disableOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(handleSpaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(triggerCheck), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(triggerCheck), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.updateVisibility()
        }

        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshStandbyStats()
        }
    }

    private func checkCurrentMediaPlaying() {
        let playing = isSystemAudioPlaying()
        if notchView.isMediaPlaying != playing {
            notchView.isMediaPlaying = playing
            if !isExpanded {
                notchView.needsDisplay = true
            }
        }
    }

    private func isSystemAudioPlaying() -> Bool {
        var defaultOutputDeviceID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )

        guard status == noErr && defaultOutputDeviceID != kAudioObjectUnknown else {
            return false
        }

        var isRunning: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let runStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &isRunning
        )

        return runStatus == noErr && isRunning > 0
    }

    private func refreshStandbyStats() {
        checkCurrentMediaPlaying()

        statsTick += 1
        if statsTick % 4 == 0 {
            let cpu = queryCpuUsage()
            let (bat, charging) = queryBatteryInfo()
            notchView.cpuUsage = cpu
            notchView.batteryPercent = bat
            notchView.isBatteryCharging = charging
            if !isExpanded {
                notchView.needsDisplay = true
            }
        }
    }

    private func queryCpuUsage() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0.0 }
        if !hasPreviousCpu {
            previousCpuInfo = cpuInfo
            hasPreviousCpu = true
            return 0.0
        }
        let userDiff = Int64(cpuInfo.cpu_ticks.0) - Int64(previousCpuInfo.cpu_ticks.0)
        let systemDiff = Int64(cpuInfo.cpu_ticks.1) - Int64(previousCpuInfo.cpu_ticks.1)
        let idleDiff = Int64(cpuInfo.cpu_ticks.2) - Int64(previousCpuInfo.cpu_ticks.2)
        let niceDiff = Int64(cpuInfo.cpu_ticks.3) - Int64(previousCpuInfo.cpu_ticks.3)
        previousCpuInfo = cpuInfo
        let total = userDiff + systemDiff + idleDiff + niceDiff
        guard total > 0 else { return 0.0 }
        return (Double(userDiff + systemDiff + niceDiff) / Double(total)) * 100.0
    }

    private func queryBatteryInfo() -> (percent: Int, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (100, false)
        }
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
                let max = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
                let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                let percent = max > 0 ? Int((Double(current) / Double(max)) * 100) : 100
                return (percent, isCharging)
            }
        }
        return (100, false)
    }

    @objc private func handleSpaceChange() {
        if isExpanded { collapseNotch() }
        isNotchVisible = false
        updateVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.updateVisibility()
        }
    }

    @objc private func triggerCheck() {
        updateVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.updateVisibility()
        }
    }

    private func isMissionControlActive() -> Bool {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }
        let dockPID = dockApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == dockPID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            if bounds.origin.y <= 5 && bounds.height >= 40 && bounds.height <= 220 && bounds.width > 300 {
                return true
            }
        }
        return false
    }

    private func isFullScreenActive(for screen: NSScreen) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let screenFrame = screen.frame

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            guard bounds.width > 150 else { continue }

            if bounds.height >= (screenFrame.height - 4) {
                return true
            }
        }
        return false
    }

    private func showNotch(screen: NSScreen) {
        guard !isNotchVisible, !isTransitioning, !isExpanded else { return }
        isNotchVisible = true

        let (shownFrame, hiddenFrame, _) = calculateFrames(for: screen)

        window.setFrame(hiddenFrame, display: true)
        window.alphaValue = 0.0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(shownFrame, display: true)
            window.animator().alphaValue = 1.0
        }
    }

    private func hideNotch(screen: NSScreen) {
        if isExpanded { collapseNotch() }
        guard isNotchVisible, !isTransitioning else { return }
        isNotchVisible = false

        let (_, hiddenFrame, _) = calculateFrames(for: screen)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.84, 0.15)
            window.animator().setFrame(hiddenFrame, display: true)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if !self.isNotchVisible {
                self.window.orderOut(nil)
            }
        })
    }

    private func updateVisibility() {
        // Cek status Caps Lock (zero-overhead bitmask check)
        let caps = NSEvent.modifierFlags.contains(.capsLock)
        if notchView.isCapsLockOn != caps {
            notchView.isCapsLockOn = caps
            if !isExpanded {
                notchView.needsDisplay = true
            }
        }

        // Animasi equalizer hanya berjalan saat audio aktif (0% GPU idle)
        if isNotchVisible && !isExpanded && notchView.isMediaPlaying {
            notchView.eqPhase += 0.28
            notchView.needsDisplay = true
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let shouldHide = isMissionControlActive() || isFullScreenActive(for: screen)

        if shouldHide {
            hideNotch(screen: screen)
        } else {
            showNotch(screen: screen)
        }
    }

    @objc private func quitApp() {
        disableOutsideClickMonitor()
        timer?.invalidate()
        statsTimer?.invalidate()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
