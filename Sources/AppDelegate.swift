import Cocoa
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NotchPanel!
    var notchView: NotchView!
    var statusItem: NSStatusItem!
    var spacerStatusItem: NSStatusItem?

    // Timers
    private var statsTimer: Timer?
    private var audioCheckTimer: Timer?
    private var eqAnimationTimer: Timer?

    // UI Container Expanded (Hardware, Battery Power, Media & Drop Shelf)
    var expandedContainer: NSView!
    var hwSummaryLabel: NSTextField!
    var batterySummaryLabel: NSTextField!
    var mediaCard: MediaControlCard!
    var dropShelf: DropShelfView!

    private var isNotchVisible: Bool = true
    private var isExpanded: Bool = false
    private var isTransitioning: Bool = false
    private var isSpaceTransitioning: Bool = false
    private var isMissionControlOpen: Bool = false
    private var spaceTransitionWorkItems: [DispatchWorkItem] = []

    private func cancelSpaceTransitionWorkItems() {
        spaceTransitionWorkItems.forEach { $0.cancel() }
        spaceTransitionWorkItems.removeAll()
    }
    private var isUserPausing: Bool = false
    private var pauseCooldownUptime: TimeInterval = 0
    private var outsideClickMonitor: Any?
    private var flagsMonitor: Any?

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
        let hiddenY = screenFrame.height + height // Exactly hidden above top screen bezel

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
            guard let self = self else { return }
            if self.isExpanded {
                self.collapseNotch()
            } else {
                self.expandNotch()
            }
        }
        notchView.onDragOver = { [weak self] in
            self?.expandNotch()
        }
        notchView.onFileDropped = { [weak self] urls in
            self?.dropShelf.storedURLs = urls
        }
        window.contentView = notchView
        window.orderFrontRegardless()
        isNotchVisible = true
    }

    private func setupExpandedUI() {
        let expWidth: CGFloat = 440
        let expHeight: CGFloat = 176
        expandedContainer = NSView(frame: NSRect(x: 0, y: 0, width: expWidth, height: expHeight))
        expandedContainer.wantsLayer = true
        expandedContainer.alphaValue = 0.0
        expandedContainer.isHidden = true

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
        if !NowPlayingManager.shared.previousTrack() {
            sendSystemMediaKey(20)
        }
    }

    @objc private func handleMediaPlayPause() {
        // Proactive instant freeze if currently playing
        if notchView.standbyView.isMediaPlaying {
            isUserPausing = true
            pauseCooldownUptime = ProcessInfo.processInfo.systemUptime + 1.0
            notchView.standbyView.setMediaPlayingState(false)
            stopEqAnimationTimer()
            mediaCard.updateTrack(isPlaying: false, title: mediaCard.trackTitleLabel.stringValue, artist: mediaCard.trackArtistLabel.stringValue)
        } else {
            isUserPausing = false
        }

        if !NowPlayingManager.shared.togglePlayPause() {
            sendSystemMediaKey(16)
        }
    }

    @objc private func handleMediaNext() {
        if !NowPlayingManager.shared.nextTrack() {
            sendSystemMediaKey(19)
        }
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

        // Disable rasterization during animation for crisp vector rendering
        notchView.standbyView.layer?.shouldRasterize = false

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

        // 1. Fast fade-out of standby indicators (0.06s)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            notchView.standbyView.animator().alphaValue = 0.0
        }

        // 2. Fluid morph of notch frame (0.24s, Apple spring curve)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(expandedFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.notchView.standbyView.isHidden = true
            self.isTransitioning = false
        })

        // 3. Smooth fade-in of expanded container as frame opens up (0.18s ease-out)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self = self, self.isExpanded else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.expandedContainer.animator().alphaValue = 1.0
            }
        }
    }

    @objc private func collapseNotch() {
        guard isExpanded, !isTransitioning else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        isTransitioning = true
        disableOutsideClickMonitor()

        let (shownFrame, _, _) = calculateFrames(for: screen)

        // 1. Fast fade-out of expanded content (0.06s) to avoid clipping during shrink
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            expandedContainer.animator().alphaValue = 0.0
        }

        // 2. Snappy shrink of notch frame back to standby pill (0.20s)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            window.animator().setFrame(shownFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isExpanded = false
            self.notchView.isExpanded = false
            self.expandedContainer.isHidden = true

            // Restore standbyView frame and fade in cleanly
            self.notchView.standbyView.frame = self.notchView.bounds
            self.notchView.standbyView.isHidden = false
            self.notchView.standbyView.alphaValue = 0.0

            // 3. Clean fade-in of standby indicators into the resting pill (0.12s ease-out)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.notchView.standbyView.animator().alphaValue = 1.0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                if !self.notchView.standbyView.isMediaPlaying {
                    self.notchView.standbyView.layer?.shouldRasterize = true
                    self.notchView.standbyView.layer?.rasterizationScale = self.window.backingScaleFactor
                }
            })

            self.isTransitioning = false

            // Resume equalizer animation if audio is currently playing
            if self.notchView.standbyView.isMediaPlaying {
                self.startEqAnimationTimer()
            }
        })
    }

    private func collapseNotchInstantly() {
        guard isExpanded else { return }
        disableOutsideClickMonitor()
        isExpanded = false
        isTransitioning = false
        notchView.isExpanded = false

        expandedContainer.isHidden = true
        expandedContainer.alphaValue = 0.0

        notchView.standbyView.isHidden = false
        notchView.standbyView.alphaValue = 1.0

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let (shownFrame, _, _) = calculateFrames(for: screen)
        notchView.frame = NSRect(origin: .zero, size: shownFrame.size)
        notchView.standbyView.frame = notchView.bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(shownFrame, display: false)
        CATransaction.commit()

        if !notchView.standbyView.isMediaPlaying {
            notchView.standbyView.layer?.shouldRasterize = true
            notchView.standbyView.layer?.rasterizationScale = window.backingScaleFactor
        }
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
        // 1. Workspace Event Listeners (Zero Polling, Event-Driven WindowServer IPC)
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(handleSpaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(triggerCheck), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(triggerCheck), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(triggerCheck), name: NSWorkspace.didHideApplicationNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(triggerCheck), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(triggerCheck), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Distributed observers for Mission Control & Desktop gestures (Zero Polling, Event-Driven)
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(self, selector: #selector(handleMissionControlStart), name: NSNotification.Name("com.apple.expose.awake"), object: nil)
        distCenter.addObserver(self, selector: #selector(handleMissionControlEnd), name: NSNotification.Name("com.apple.expose.destroy"), object: nil)
        distCenter.addObserver(self, selector: #selector(handleMissionControlStart), name: NSNotification.Name("com.apple.expose.front.awake"), object: nil)
        distCenter.addObserver(self, selector: #selector(handleMissionControlEnd), name: NSNotification.Name("com.apple.expose.front.destroy"), object: nil)
        distCenter.addObserver(self, selector: #selector(handleMissionControlStart), name: NSNotification.Name("com.apple.showdesktop.awake"), object: nil)
        distCenter.addObserver(self, selector: #selector(handleMissionControlEnd), name: NSNotification.Name("com.apple.showdesktop.destroy"), object: nil)

        // 2. Hardware Stats Timer: 2.0s interval for 10s rolling CPU average only
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

        // 5. Native IOKit Power Source Listener (0ms latency, zero polling overhead)
        SystemStats.shared.setupPowerSourceListener { [weak self] batInfo in
            self?.handleBatteryChanged(batInfo: batInfo)
        }

        // 6. Native Caps Lock Event Monitor (0ms latency, zero polling overhead)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] _ in
            self?.handleFlagsChanged()
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged()
            return event
        }
    }

    @objc private func handleMissionControlStart() {
        isMissionControlOpen = true
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if isExpanded {
            collapseNotchInstantly()
        }
        hideNotch(screen: screen, animated: true)
    }

    @objc private func handleMissionControlEnd() {
        isMissionControlOpen = false
        cancelSpaceTransitionWorkItems()
        isSpaceTransitioning = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.updateVisibility(animatedHide: false)
        }
    }

    private func handleFlagsChanged() {
        let caps = NSEvent.modifierFlags.contains(.capsLock)
        if notchView.standbyView.isCapsLockOn != caps {
            notchView.standbyView.isCapsLockOn = caps
            if !isExpanded {
                notchView.standbyView.invalidateCapsLock()
            }
        }
    }

    private func startEqAnimationTimer() {
        guard eqAnimationTimer == nil else { return }
        // 25 FPS smooth equalizer animation ONLY while media plays (bypasses CPU draw)
        eqAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, self.isNotchVisible, !self.isExpanded, self.notchView.standbyView.isMediaPlaying else { return }

            // Sub-40ms instant freeze: check audio active state every frame directly via cached device ID
            if !SystemStats.shared.isSystemAudioPlaying() {
                self.handleAudioStateChanged(isPlaying: false)
                return
            }

            self.notchView.standbyView.eqPhase += 0.28
            self.notchView.standbyView.updateEqualizerBars()
        }
    }

    private func stopEqAnimationTimer() {
        eqAnimationTimer?.invalidate()
        eqAnimationTimer = nil
    }

    private func handleAudioStateChanged(isPlaying: Bool) {
        if isPlaying {
            // Buffer drain debounce: ignore false positive play state right after user clicked pause
            if isUserPausing {
                if ProcessInfo.processInfo.systemUptime < pauseCooldownUptime {
                    return
                } else {
                    isUserPausing = false
                }
            }
        } else {
            isUserPausing = false
        }

        guard notchView.standbyView.isMediaPlaying != isPlaying else { return }
        notchView.standbyView.setMediaPlayingState(isPlaying)
        if isPlaying {
            if !isExpanded {
                startEqAnimationTimer()
            }
        } else {
            stopEqAnimationTimer()
        }
        if isExpanded {
            updateNowPlayingInfo(isPlaying: isPlaying)
        }
    }

    private func handleBatteryChanged(batInfo: DetailedBatteryInfo) {
        var needsRedraw = false
        if notchView.standbyView.batteryPercent != batInfo.percent || notchView.standbyView.isBatteryCharging != batInfo.isCharging {
            notchView.standbyView.batteryPercent = batInfo.percent
            notchView.standbyView.isBatteryCharging = batInfo.isCharging
            needsRedraw = true
        }

        if !isExpanded {
            if needsRedraw {
                notchView.standbyView.needsDisplay = true
            }
        } else {
            updateExpandedBatteryStats()
        }
    }

    private func checkCurrentMediaPlaying() {
        let playing = SystemStats.shared.isSystemAudioPlaying()
        handleAudioStateChanged(isPlaying: playing)
    }

    private func refreshStandbyStats() {
        let avgCpu = SystemStats.shared.updateCpuAverage()

        // Heartbeat filter: only redraw if CPU load tier changes (<40%, 40-75%, >75%)
        let oldTier = notchView.standbyView.cpuTier
        notchView.standbyView.cpuUsage = avgCpu

        if !isExpanded {
            if oldTier != notchView.standbyView.cpuTier {
                notchView.standbyView.needsDisplay = true
            }

            // Self-healing check: guarantee notch reappears on desktop if a transition was interrupted
            if !isSpaceTransitioning && !isMissionControlActive() {
                if let scr = NSScreen.main ?? NSScreen.screens.first {
                    let isFS = isFullScreenActive(for: scr)
                    if !isFS && !isNotchVisible && !isTransitioning {
                        showNotch(screen: scr)
                    } else if isFS && isNotchVisible {
                        hideNotch(screen: scr, animated: false)
                    }
                }
            }
        } else {
            updateExpandedHardwareStats()
        }
    }

    // MARK: - Cached Static Formatted Text (Zero Heap Churn)
    private enum FormattedTextCache {
        static let centerStyle: NSMutableParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            return style
        }()

        static let fontRegular11 = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let fontBold11 = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        static let fontRegular10_5 = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        static let fontBold10_5 = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)

        static let dimColor = NSColor.white.withAlphaComponent(0.45)
        static let greenColor = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)

        static let bulletSeparator: NSAttributedString = {
            NSAttributedString(string: "  •  ", attributes: [
                .foregroundColor: dimColor,
                .font: fontRegular11,
                .paragraphStyle: centerStyle
            ])
        }()

        static let bulletSeparatorSmall: NSAttributedString = {
            NSAttributedString(string: "  •  ", attributes: [
                .foregroundColor: dimColor,
                .font: fontRegular10_5,
                .paragraphStyle: centerStyle
            ])
        }()

        static let avgCpuLabel: NSAttributedString = {
            NSAttributedString(string: "Avg. CPU ", attributes: [
                .foregroundColor: dimColor,
                .font: fontRegular11,
                .paragraphStyle: centerStyle
            ])
        }()

        static let ramLabel: NSAttributedString = {
            NSAttributedString(string: "RAM ", attributes: [
                .foregroundColor: dimColor,
                .font: fontRegular11,
                .paragraphStyle: centerStyle
            ])
        }()

        static let tempLabel: NSAttributedString = {
            NSAttributedString(string: "Temp ", attributes: [
                .foregroundColor: dimColor,
                .font: fontRegular11,
                .paragraphStyle: centerStyle
            ])
        }()

        static let throttleLabel: NSAttributedString = {
            NSAttributedString(string: "Throttle ", attributes: [
                .foregroundColor: dimColor,
                .font: fontRegular11,
                .paragraphStyle: centerStyle
            ])
        }()
    }

    private func updateExpandedHardwareStats() {
        guard isExpanded else { return }

        let cpuInt = Int(SystemStats.shared.currentAverageCpu)
        let ram = SystemStats.shared.queryRamUsage()
        let temp = SystemStats.shared.queryCpuTemperature(cpu: SystemStats.shared.currentAverageCpu)
        let (throttleText, throttleColor) = SystemStats.shared.throttleStatusShort()

        let text = NSMutableAttributedString()

        func append(_ str: String, color: NSColor, bold: Bool = true) {
            let font = bold ? FormattedTextCache.fontBold11 : FormattedTextCache.fontRegular11
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: FormattedTextCache.centerStyle
            ]
            text.append(NSAttributedString(string: str, attributes: attrs))
        }

        text.append(FormattedTextCache.avgCpuLabel)
        let cpuColor: NSColor = cpuInt > 75 ? .systemRed : (cpuInt > 40 ? .systemOrange : FormattedTextCache.greenColor)
        append("\(cpuInt)%", color: cpuColor)

        text.append(FormattedTextCache.bulletSeparator)
        text.append(FormattedTextCache.ramLabel)
        let ramColor: NSColor = ram.percent > 85 ? .systemRed : (ram.percent > 65 ? .systemOrange : FormattedTextCache.greenColor)
        append("\(ram.percent)%", color: ramColor)

        text.append(FormattedTextCache.bulletSeparator)
        text.append(FormattedTextCache.tempLabel)
        let tempColor: NSColor = temp > 85 ? .systemRed : (temp > 70 ? .systemOrange : FormattedTextCache.greenColor)
        append("\(temp)°C", color: tempColor)

        text.append(FormattedTextCache.bulletSeparator)
        text.append(FormattedTextCache.throttleLabel)
        append(throttleText, color: throttleColor)

        hwSummaryLabel.attributedStringValue = text
        updateNowPlayingInfo(isPlaying: notchView.standbyView.isMediaPlaying)
    }

    private func updateExpandedBatteryStats() {
        guard isExpanded else { return }

        let batInfo = SystemStats.shared.queryDetailedBatteryInfo()
        let text = NSMutableAttributedString()

        func append(_ str: String, color: NSColor, bold: Bool = true) {
            let font = bold ? FormattedTextCache.fontBold10_5 : FormattedTextCache.fontRegular10_5
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font,
                .paragraphStyle: FormattedTextCache.centerStyle
            ]
            text.append(NSAttributedString(string: str, attributes: attrs))
        }

        let green = FormattedTextCache.greenColor
        let dim = FormattedTextCache.dimColor
        let batColor: NSColor = batInfo.percent > 50 ? green : (batInfo.percent > 20 ? .systemYellow : .systemRed)

        if batInfo.isAC {
            if batInfo.percent >= 100 {
                append("⚡ 100% Fully Charged", color: green)
                if let w = batInfo.watts {
                    text.append(FormattedTextCache.bulletSeparatorSmall)
                    append("\(w)W Adapter", color: NSColor.white.withAlphaComponent(0.75), bold: false)
                }
            } else if batInfo.isCharging {
                append("⚡ Charging ", color: green)
                append("\(batInfo.percent)%", color: batColor)
                if let w = batInfo.watts {
                    append(" (\(w)W)", color: NSColor.white.withAlphaComponent(0.85))
                }
                text.append(FormattedTextCache.bulletSeparatorSmall)
                if let ttf = batInfo.timeToFull {
                    let h = ttf / 60
                    let m = ttf % 60
                    let estStr = h > 0 ? "\(h)h \(m)m to full" : "\(m)m to full"
                    append(estStr, color: NSColor.white.withAlphaComponent(0.85), bold: false)
                } else {
                    append("Calculating time...", color: dim, bold: false)
                }
            } else {
                append("⚡ On AC Power ", color: green)
                append("\(batInfo.percent)%", color: batColor)
                if let w = batInfo.watts {
                    append(" (\(w)W)", color: NSColor.white.withAlphaComponent(0.85))
                }
                text.append(FormattedTextCache.bulletSeparatorSmall)
                append("Hold (Optimized)", color: NSColor.systemYellow, bold: false)
            }
        } else {
            append("🔋 Battery ", color: dim, bold: false)
            append("\(batInfo.percent)%", color: batColor)
            text.append(FormattedTextCache.bulletSeparatorSmall)
            if let tte = batInfo.timeToEmpty {
                let h = tte / 60
                let m = tte % 60
                let estStr = h > 0 ? "\(h)h \(m)m remaining" : "\(m)m remaining"
                append(estStr, color: NSColor.white.withAlphaComponent(0.85), bold: false)
            } else {
                append("Calculating time...", color: dim, bold: false)
            }
        }

        batterySummaryLabel.attributedStringValue = text
    }

    private func updateNowPlayingInfo(isPlaying: Bool) {
        let effectivePlaying = (isUserPausing && ProcessInfo.processInfo.systemUptime < pauseCooldownUptime) ? false : isPlaying
        NowPlayingManager.shared.queryNowPlaying { [weak self] title, artist in
            self?.mediaCard.updateTrack(isPlaying: effectivePlaying, title: title, artist: artist)
        }
    }

    @objc private func handleSpaceChange() {
        if isExpanded {
            collapseNotchInstantly()
        }
        isSpaceTransitioning = true
        cancelSpaceTransitionWorkItems()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Immediately hide notch on space change (0ms, vanishes cleanly)
        hideNotch(screen: screen, animated: false)

        // Multi-stage verification checks:
        // Covers 3-finger swipe (0.18s) and full macOS zoom exit animations (0.32s - 0.68s)
        let delays: [TimeInterval] = [0.18, 0.32, 0.48, 0.68]
        for (index, delay) in delays.enumerated() {
            let isLast = (index == delays.count - 1)
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                guard let scr = NSScreen.main ?? NSScreen.screens.first else { return }

                let isMC = self.isMissionControlActive()
                let isFS = self.isFullScreenActive(for: scr)

                if isMC || isFS {
                    if self.isNotchVisible {
                        self.hideNotch(screen: scr, animated: false)
                    }
                } else {
                    // Settled on desktop!
                    self.isSpaceTransitioning = false
                    if !self.isNotchVisible {
                        self.showNotch(screen: scr)
                    }
                    self.cancelSpaceTransitionWorkItems()
                    return
                }

                if isLast {
                    self.isSpaceTransitioning = false
                }
            }
            spaceTransitionWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    @objc private func triggerCheck() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if isFullScreenActive(for: screen) || isMissionControlActive() {
            hideNotch(screen: screen, animated: false)
        } else if !isSpaceTransitioning {
            updateVisibility(animatedHide: false)
        }
    }

    private func isMissionControlActive() -> Bool {
        if isMissionControlOpen { return true }
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

            guard bounds.width >= 200 else { continue }

            // Native macOS fullscreen window starts at top (y <= 1) and spans full screen height
            if bounds.origin.y <= 1 && bounds.height >= (screenFrame.height - 25) {
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
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(shownFrame, display: true)
            window.animator().alphaValue = 1.0
        }

        // Resume equalizer animation if audio is playing upon returning to space
        let isAudioPlaying = SystemStats.shared.isSystemAudioPlaying()
        notchView.standbyView.setMediaPlayingState(isAudioPlaying)
        if isAudioPlaying {
            startEqAnimationTimer()
        } else {
            stopEqAnimationTimer()
        }
    }

    private func hideNotch(screen: NSScreen, animated: Bool = true) {
        if isExpanded {
            collapseNotchInstantly()
        }
        guard isNotchVisible || window.isVisible else { return }
        isNotchVisible = false
        isTransitioning = false
        stopEqAnimationTimer()

        let (_, hiddenFrame, _) = calculateFrames(for: screen)

        if animated {
            isTransitioning = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.0, 0.7, 0.15)
                window.animator().setFrame(hiddenFrame, display: true)
                window.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                self.isTransitioning = false
                if !self.isNotchVisible {
                    self.window.orderOut(nil)
                }
            })
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            window.setFrame(hiddenFrame, display: false)
            window.alphaValue = 0.0
            CATransaction.commit()
            window.orderOut(nil)
        }
    }

    private func updateVisibility(animatedHide: Bool = true) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let shouldHide = isMissionControlActive() || isFullScreenActive(for: screen)

        if shouldHide {
            hideNotch(screen: screen, animated: animatedHide)
        } else {
            showNotch(screen: screen)
            if isNotchVisible && !isExpanded && notchView.standbyView.isMediaPlaying && eqAnimationTimer == nil {
                startEqAnimationTimer()
            }
        }
    }

    @objc private func quitApp() {
        disableOutsideClickMonitor()
        cancelSpaceTransitionWorkItems()
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        statsTimer?.invalidate()
        audioCheckTimer?.invalidate()
        stopEqAnimationTimer()
        NSApplication.shared.terminate(nil)
    }
}
