import Cocoa
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NotchPanel!
    var notchView: NotchView!
    var statusItem: NSStatusItem!
    var spacerStatusItem: NSStatusItem?

    // Timers
    private var visibilityTimer: Timer?
    private var statsTimer: Timer?
    private var audioCheckTimer: Timer?
    private var eqAnimationTimer: Timer?

    // UI Container Expanded (Hardware, Battery Power, Media & Drop Shelf)
    var expandedContainer: NSView!
    var closeButton: NSButton!
    var hwSummaryLabel: NSTextField!
    var batterySummaryLabel: NSTextField!
    var mediaCard: MediaControlCard!
    var dropShelf: DropShelfView!

    private var isNotchVisible: Bool = true
    private var isExpanded: Bool = false
    private var isTransitioning: Bool = false
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenuBarBarrier()
        setupNotchWindow()
        setupExpandedUI()
        setupObservers()

        // Initial fetch
        SystemStats.shared.updateCpuAverage()
        _ = SystemStats.shared.queryRamUsage(force: true)
        _ = SystemStats.shared.queryDetailedBatteryInfo(force: true)
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

        let expWidth: CGFloat = 440
        let expHeight: CGFloat = 176
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
        notchView.onDragOver = { [weak self] in
            self?.expandNotch()
        }
        notchView.onFileDropped = { [weak self] urls in
            self?.dropShelf.storedURLs = urls
        }
        window.contentView = notchView
        window.orderFrontRegardless()
    }

    private func setupExpandedUI() {
        let expWidth: CGFloat = 440
        let expHeight: CGFloat = 176
        expandedContainer = NSView(frame: NSRect(x: 0, y: 0, width: expWidth, height: expHeight))
        expandedContainer.wantsLayer = true
        expandedContainer.alphaValue = 0.0
        expandedContainer.isHidden = true

        let closeSize: CGFloat = 24

        // 1. Hardware Summary Strip (Centered & Symmetrical)
        hwSummaryLabel = NSTextField(labelWithString: "")
        hwSummaryLabel.alignment = .center
        hwSummaryLabel.frame = NSRect(x: 14, y: 144, width: expWidth - 28, height: 18)
        hwSummaryLabel.isBezeled = false
        hwSummaryLabel.drawsBackground = false
        hwSummaryLabel.isEditable = false
        hwSummaryLabel.isSelectable = false
        expandedContainer.addSubview(hwSummaryLabel)

        // 2. Battery & Charging Power Summary Strip (Centered & Symmetrical)
        batterySummaryLabel = NSTextField(labelWithString: "")
        batterySummaryLabel.alignment = .center
        batterySummaryLabel.frame = NSRect(x: 14, y: 122, width: expWidth - 28, height: 18)
        batterySummaryLabel.isBezeled = false
        batterySummaryLabel.drawsBackground = false
        batterySummaryLabel.isEditable = false
        batterySummaryLabel.isSelectable = false
        expandedContainer.addSubview(batterySummaryLabel)

        // Close Button (Right edge, vertically centered between 2 header rows)
        closeButton = NSButton(frame: NSRect(x: expWidth - closeSize - 14, y: 129, width: closeSize, height: closeSize))
        closeButton.title = "✕"
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        closeButton.layer?.cornerRadius = closeSize / 2
        closeButton.layer?.cornerCurve = .continuous
        closeButton.target = self
        closeButton.action = #selector(collapseNotch)
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        closeButton.contentTintColor = .white
        expandedContainer.addSubview(closeButton)

        // Concentric Card Alignment (14pt uniform margin & 10pt continuous squircle radius):
        // Outer notch arc center: (33, 24) and (407, 24), radius 24pt
        // Inner card arc center:  (23 + 10 = 33, 14 + 10 = 24), radius 10pt
        // Left clearance: 14pt (23 - 9)
        // Bottom clearance: 14pt (14 - 0)
        // Corner arc clearance: 14pt (24 - 10)
        // Inter-card gap: 14pt (227 - (23 + 190))
        // Right clearance: 14pt (431 - (227 + 190))
        // 3. Media Controller Card (Left)
        mediaCard = MediaControlCard(frame: NSRect(x: 23, y: 14, width: 190, height: 98))
        mediaCard.prevBtn.target = self
        mediaCard.prevBtn.action = #selector(handleMediaPrev)
        mediaCard.playPauseBtn.target = self
        mediaCard.playPauseBtn.action = #selector(handleMediaPlayPause)
        mediaCard.nextBtn.target = self
        mediaCard.nextBtn.action = #selector(handleMediaNext)
        expandedContainer.addSubview(mediaCard)

        // 4. Drop Shelf View (Right - Temporary Drag & Drop File Shelf)
        dropShelf = DropShelfView(frame: NSRect(x: 227, y: 14, width: 190, height: 98))
        expandedContainer.addSubview(dropShelf)

        notchView.addSubview(expandedContainer)
    }

    @objc private func handleMediaPrev() {
        sendSystemMediaKey(20)
    }

    @objc private func handleMediaPlayPause() {
        sendSystemMediaKey(16)
    }

    @objc private func handleMediaNext() {
        sendSystemMediaKey(19)
    }

    private func sendSystemMediaKey(_ key: Int32) {
        // ponytail: Universal HID media key event. Simulates keyboard F7/F8/F9 media keys without AppleScript permissions.
        func postKey(down: Bool) {
            let flags: Int32 = down ? 0xa00 : 0xb00
            let data1 = Int((key << 16) | flags)
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        postKey(down: true)
        postKey(down: false)
    }

    @objc private func expandNotch() {
        guard !isExpanded, !isTransitioning, isNotchVisible else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        isTransitioning = true
        isExpanded = true
        notchView.isExpanded = true
        stopEqAnimationTimer()

        // Immediate fresh query on expand
        _ = SystemStats.shared.queryRamUsage(force: true)
        _ = SystemStats.shared.queryDetailedBatteryInfo(force: true)
        updateExpandedHardwareStats()
        updateExpandedBatteryStats()

        let (_, _, expandedFrame) = calculateFrames(for: screen)
        expandedContainer.frame = NSRect(origin: .zero, size: expandedFrame.size)
        expandedContainer.alphaValue = 0.0
        expandedContainer.isHidden = false

        enableOutsideClickMonitor()

        // 1. Fade out standby indicators smoothly before expand begins (0.10s)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            notchView.standbyView.animator().alphaValue = 0.0
        }

        // 2. Morph notch shape with Apple fluid spring curve (0.32s)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.12, 0.95, 0.22, 1.0)
            window.animator().setFrame(expandedFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.notchView.standbyView.isHidden = true
            self.isTransitioning = false
        })

        // 3. Dissolve in expanded container (0.24s)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            expandedContainer.animator().alphaValue = 1.0
        }
    }

    @objc private func collapseNotch() {
        guard isExpanded, !isTransitioning else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        isTransitioning = true
        disableOutsideClickMonitor()

        let (shownFrame, _, _) = calculateFrames(for: screen)

        // 1. Fade out expanded content cleanly (0.10s)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            expandedContainer.animator().alphaValue = 0.0
        }

        // 2. Shrink notch frame back to standby pill (0.26s)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            window.animator().setFrame(shownFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isExpanded = false
            self.notchView.isExpanded = false
            self.expandedContainer.isHidden = true

            // Reset standbyView frame and prepare for smooth fade-in
            self.notchView.standbyView.frame = self.notchView.bounds
            self.notchView.standbyView.isHidden = false
            self.notchView.standbyView.alphaValue = 0.0

            // 3. Smooth fade-in of standby indicators into the collapsed pill (0.20s ease-out)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.notchView.standbyView.animator().alphaValue = 1.0
            }

            self.isTransitioning = false

            // Resume equalizer animation if audio is currently playing
            if self.notchView.standbyView.isMediaPlaying {
                self.startEqAnimationTimer()
            }
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

    // MARK: - Observer & Timer Setup (Full Energy Optimization)
    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(handleSpaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(triggerCheck), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(triggerCheck), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // 1. Visibility Fallback Heartbeat (0.5s instead of 0.08s — 84% reduction in WindowServer IPC)
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateVisibility()
        }

        // 2. Hardware Stats Timer: 2.0s interval for 10s rolling CPU average & 10s cached battery/RAM
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStandbyStats()
        }

        // 3. Audio status check: 1.5s interval fallback
        audioCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkCurrentMediaPlaying()
        }

        // 4. Native CoreAudio HAL Event Listener (instant 0ms trigger on play/pause)
        SystemStats.shared.setupAudioChangeListener { [weak self] isPlaying in
            self?.handleAudioStateChanged(isPlaying: isPlaying)
        }
    }

    private var eqFrameCount: Int = 0

    private func startEqAnimationTimer() {
        guard eqAnimationTimer == nil else { return }
        eqFrameCount = 0
        // 25 FPS smooth equalizer animation ONLY while media plays
        eqAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, self.isNotchVisible, !self.isExpanded, self.notchView.standbyView.isMediaPlaying else { return }

            // Sub-200ms active poll to stop animation immediately when audio pauses
            self.eqFrameCount += 1
            if self.eqFrameCount % 4 == 0 {
                if !SystemStats.shared.isSystemAudioPlaying() {
                    self.handleAudioStateChanged(isPlaying: false)
                    return
                }
            }

            self.notchView.standbyView.eqPhase += 0.28
            self.notchView.standbyView.needsDisplay = true
        }
    }

    private func stopEqAnimationTimer() {
        eqAnimationTimer?.invalidate()
        eqAnimationTimer = nil
        eqFrameCount = 0
    }

    private func handleAudioStateChanged(isPlaying: Bool) {
        guard notchView.standbyView.isMediaPlaying != isPlaying else { return }
        notchView.standbyView.isMediaPlaying = isPlaying
        if isPlaying {
            if !isExpanded {
                startEqAnimationTimer()
            }
        } else {
            stopEqAnimationTimer()
        }
        if !isExpanded {
            notchView.standbyView.needsDisplay = true
        } else {
            updateNowPlayingInfo(isPlaying: isPlaying)
        }
    }

    private func checkCurrentMediaPlaying() {
        let playing = SystemStats.shared.isSystemAudioPlaying()
        handleAudioStateChanged(isPlaying: playing)
    }

    private func refreshStandbyStats() {
        let avgCpu = SystemStats.shared.updateCpuAverage()
        let batInfo = SystemStats.shared.queryDetailedBatteryInfo()
        let capsOn = NSEvent.modifierFlags.contains(.capsLock)

        var needsRedraw = false
        if notchView.standbyView.isCapsLockOn != capsOn {
            notchView.standbyView.isCapsLockOn = capsOn
            needsRedraw = true
        }
        if notchView.standbyView.batteryPercent != batInfo.percent || notchView.standbyView.isBatteryCharging != batInfo.isCharging {
            notchView.standbyView.batteryPercent = batInfo.percent
            notchView.standbyView.isBatteryCharging = batInfo.isCharging
            needsRedraw = true
        }
        if Int(notchView.standbyView.cpuUsage) != Int(avgCpu) {
            notchView.standbyView.cpuUsage = avgCpu
            needsRedraw = true
        }

        if !isExpanded {
            if needsRedraw {
                notchView.standbyView.needsDisplay = true
            }
        } else {
            updateExpandedHardwareStats()
            updateExpandedBatteryStats()
        }
    }

    private func updateExpandedHardwareStats() {
        guard isExpanded else { return }

        let cpuInt = Int(SystemStats.shared.currentAverageCpu)
        let ram = SystemStats.shared.queryRamUsage()
        let temp = SystemStats.shared.queryCpuTemperature(cpu: SystemStats.shared.currentAverageCpu)
        let (throttleText, throttleColor) = SystemStats.shared.throttleStatusShort()

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        let text = NSMutableAttributedString()

        func append(_ str: String, color: NSColor = .white, bold: Bool = false) {
            let font: NSFont = bold ? .monospacedDigitSystemFont(ofSize: 11, weight: .bold) : .systemFont(ofSize: 11, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: centerStyle
            ]
            text.append(NSAttributedString(string: str, attributes: attrs))
        }

        let dim = NSColor.white.withAlphaComponent(0.45)
        append("Avg. CPU ", color: dim)
        let cpuColor: NSColor = cpuInt > 75 ? .systemRed : (cpuInt > 40 ? .systemOrange : NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0))
        append("\(cpuInt)%", color: cpuColor, bold: true)

        append("  •  ", color: dim)
        append("RAM ", color: dim)
        let ramColor: NSColor = ram.percent > 85 ? .systemRed : (ram.percent > 65 ? .systemOrange : NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0))
        append("\(ram.percent)%", color: ramColor, bold: true)

        append("  •  ", color: dim)
        append("Temp ", color: dim)
        let tempColor: NSColor = temp > 85 ? .systemRed : (temp > 70 ? .systemOrange : NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0))
        append("\(temp)°C", color: tempColor, bold: true)

        append("  •  ", color: dim)
        append("Throttle ", color: dim)
        append(throttleText, color: throttleColor, bold: true)

        hwSummaryLabel.attributedStringValue = text
        updateNowPlayingInfo(isPlaying: notchView.standbyView.isMediaPlaying)
    }

    private func updateExpandedBatteryStats() {
        guard isExpanded else { return }

        let batInfo = SystemStats.shared.queryDetailedBatteryInfo()

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        let text = NSMutableAttributedString()
        let dim = NSColor.white.withAlphaComponent(0.45)

        func append(_ str: String, color: NSColor = .white, bold: Bool = false) {
            let font: NSFont = bold ? .monospacedDigitSystemFont(ofSize: 10.5, weight: .bold) : .systemFont(ofSize: 10.5, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: centerStyle
            ]
            text.append(NSAttributedString(string: str, attributes: attrs))
        }

        let green = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
        let batColor: NSColor = batInfo.percent > 50 ? green : (batInfo.percent > 20 ? .systemYellow : .systemRed)

        if batInfo.isAC {
            if batInfo.percent >= 100 {
                append("⚡ 100% Fully Charged", color: green, bold: true)
                if let w = batInfo.watts {
                    append("  •  ", color: dim)
                    append("\(w)W Adapter", color: NSColor.white.withAlphaComponent(0.75))
                }
            } else if batInfo.isCharging {
                append("⚡ Charging ", color: green, bold: true)
                append("\(batInfo.percent)%", color: batColor, bold: true)
                if let w = batInfo.watts {
                    append(" (\(w)W)", color: NSColor.white.withAlphaComponent(0.85), bold: true)
                }
                append("  •  ", color: dim)
                if let ttf = batInfo.timeToFull {
                    let h = ttf / 60
                    let m = ttf % 60
                    let estStr = h > 0 ? "\(h)h \(m)m to full" : "\(m)m to full"
                    append(estStr, color: NSColor.white.withAlphaComponent(0.85))
                } else {
                    append("Calculating time...", color: dim)
                }
            } else {
                append("⚡ On AC Power ", color: green, bold: true)
                append("\(batInfo.percent)%", color: batColor, bold: true)
                if let w = batInfo.watts {
                    append(" (\(w)W)", color: NSColor.white.withAlphaComponent(0.85), bold: true)
                }
                append("  •  ", color: dim)
                append("Hold (Optimized)", color: NSColor.systemYellow)
            }
        } else {
            append("🔋 Battery ", color: dim)
            append("\(batInfo.percent)%", color: batColor, bold: true)
            append("  •  ", color: dim)
            if let tte = batInfo.timeToEmpty {
                let h = tte / 60
                let m = tte % 60
                let estStr = h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
                append(estStr, color: NSColor.white.withAlphaComponent(0.85))
            } else {
                append("Calculating time...", color: dim)
            }
        }

        batterySummaryLabel.attributedStringValue = text
    }

    private func updateNowPlayingInfo(isPlaying: Bool) {
        NowPlayingManager.shared.queryNowPlaying { [weak self] title, artist in
            self?.mediaCard.updateTrack(isPlaying: isPlaying, title: title, artist: artist)
        }
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
        stopEqAnimationTimer()

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
        let caps = NSEvent.modifierFlags.contains(.capsLock)
        if notchView.isCapsLockOn != caps {
            notchView.isCapsLockOn = caps
            if !isExpanded {
                notchView.standbyView.needsDisplay = true
            }
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
        visibilityTimer?.invalidate()
        statsTimer?.invalidate()
        audioCheckTimer?.invalidate()
        stopEqAnimationTimer()
        NSApplication.shared.terminate(nil)
    }
}
