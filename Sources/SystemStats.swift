import Cocoa
import CoreAudio
import Darwin
import IOKit.ps

final class SystemStats {
    static let shared = SystemStats()

    private var previousCpuInfo = host_cpu_load_info()
    private var hasPreviousCpu = false

    // 10-second rolling CPU window (5 samples x 2.0s interval)
    private var cpuLoadHistory: [Double] = []
    private let maxHistorySamples = 5
    private(set) var currentAverageCpu: Double = 0.0

    // Caches to avoid redundant polling
    private var cachedRam = RamInfo(usedGB: 0.0, totalGB: 0.0, percent: 0)
    private var lastRamCheck: TimeInterval = 0

    private var cachedBattery = DetailedBatteryInfo(percent: 100, isCharging: false, isAC: false, watts: nil, timeToFull: nil, timeToEmpty: nil)
    private var lastBatteryCheck: TimeInterval = 0

    private init() {
        // Initial sample
        _ = sampleInstantCpu()
    }

    // MARK: - CPU 10-Second Rolling Average
    @discardableResult
    func updateCpuAverage() -> Double {
        let instant = sampleInstantCpu()
        cpuLoadHistory.append(instant)
        if cpuLoadHistory.count > maxHistorySamples {
            cpuLoadHistory.removeFirst()
        }
        let avg = cpuLoadHistory.reduce(0.0, +) / Double(cpuLoadHistory.count)
        currentAverageCpu = avg
        return avg
    }

    private func sampleInstantCpu() -> Double {
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

    // MARK: - RAM Usage (10s cached interval)
    func queryRamUsage(force: Bool = false) -> RamInfo {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && (now - lastRamCheck < 10.0) && cachedRam.totalGB > 0 {
            return cachedRam
        }
        lastRamCheck = now

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / 1_073_741_824.0

        guard result == KERN_SUCCESS else {
            cachedRam = RamInfo(usedGB: 0.0, totalGB: totalGB, percent: 0)
            return cachedRam
        }

        let pageSize = UInt64(getpagesize())
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = active + wired + compressed
        let usedGB = Double(usedBytes) / 1_073_741_824.0
        let percent = min(100, max(0, Int((Double(usedBytes) / Double(totalBytes)) * 100.0)))

        cachedRam = RamInfo(usedGB: usedGB, totalGB: totalGB, percent: percent)
        return cachedRam
    }

    // MARK: - Temperature & Thermal Throttle
    func queryCpuTemperature(cpu: Double) -> Int {
        // ponytail: Direct SMC read requires root/kext on macOS Ventura; computed from 10s avg Mach CPU load & thermalState
        var temp = 46.0 + (cpu * 0.42)
        switch ProcessInfo.processInfo.thermalState {
        case .fair:
            temp = max(temp, 70.0)
        case .serious:
            temp = max(temp, 86.0)
        case .critical:
            temp = max(temp, 96.0)
        default:
            break
        }
        return Int(min(100.0, max(42.0, temp)))
    }

    func throttleStatusShort() -> (text: String, color: NSColor) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return ("Normal", NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0))
        case .fair:
            return ("Fair", .systemYellow)
        case .serious:
            return ("Throttled", .systemOrange)
        case .critical:
            return ("Heavy", .systemRed)
        @unknown default:
            return ("Normal", NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1.0))
        }
    }

    // MARK: - Battery & Charging Power (10s cached interval)
    func queryDetailedBatteryInfo(force: Bool = false) -> DetailedBatteryInfo {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && (now - lastBatteryCheck < 10.0) {
            return cachedBattery
        }
        lastBatteryCheck = now

        var percent = 100
        var isCharging = false
        var isAC = false
        var watts: Int? = nil
        var timeToFull: Int? = nil
        var timeToEmpty: Int? = nil

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                    let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
                    let max = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
                    percent = max > 0 ? Int((Double(current) / Double(max)) * 100) : 100

                    let chargingFlag = (desc[kIOPSIsChargingKey as String] as? Bool) ?? ((desc[kIOPSIsChargingKey as String] as? Int) == 1)
                    let externalFlag = (desc["ExternalConnected"] as? Bool) ?? ((desc["ExternalConnected"] as? Int) == 1)
                    let powerState = desc[kIOPSPowerSourceStateKey as String] as? String
                    let acFlag = powerState?.contains("AC") ?? false

                    isCharging = chargingFlag
                    isAC = externalFlag || acFlag

                    if let adapter = desc["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? Int, w > 0 {
                        watts = w
                    } else if let w = desc["Watts"] as? Int, w > 0 {
                        watts = w
                    }

                    if let ttf = desc[kIOPSTimeToFullChargeKey as String] as? Int, ttf > 0 && ttf < 1440 {
                        timeToFull = ttf
                    }
                    if let tte = desc[kIOPSTimeToEmptyKey as String] as? Int, tte > 0 && tte < 1440 {
                        timeToEmpty = tte
                    }
                }
            }
        }

        // Secondary query via AppleSmartBattery in IORegistry if watts or time is nil
        if watts == nil || (isCharging && timeToFull == nil) || (!isAC && timeToEmpty == nil) {
            let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if entry != IO_OBJECT_NULL {
                defer { IOObjectRelease(entry) }
                var propsRef: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let props = propsRef?.takeRetainedValue() as? [String: Any] {
                    if watts == nil {
                        if let adapter = props["AdapterInfo"] as? [String: Any], let w = adapter["Watts"] as? Int, w > 0 {
                            watts = w
                        } else if let w = props["Watts"] as? Int, w > 0 {
                            watts = w
                        } else if let v = props["Voltage"] as? Int, let a = props["Amperage"] as? Int, a > 0 && v > 0 {
                            let calculatedWatts = Int(round((Double(v) * Double(a)) / 1_000_000.0))
                            if calculatedWatts > 0 { watts = calculatedWatts }
                        }
                    }
                    if timeToFull == nil, let ttf = props["AvgTimeToFull"] as? Int, ttf > 0 && ttf < 1440 {
                        timeToFull = ttf
                    }
                    if timeToEmpty == nil, let tte = props["AvgTimeToEmpty"] as? Int, tte > 0 && tte < 1440 {
                        timeToEmpty = tte
                    }
                }
            }
        }

        cachedBattery = DetailedBatteryInfo(
            percent: percent,
            isCharging: isCharging || isAC,
            isAC: isAC,
            watts: watts,
            timeToFull: timeToFull,
            timeToEmpty: timeToEmpty
        )
        return cachedBattery
    }

    // MARK: - CoreAudio HAL Detection & Event Listener
    private var currentOutputDeviceID: AudioObjectID = 0
    private var audioChangeListener: ((Bool) -> Void)?

    func setupAudioChangeListener(onChange: @escaping (Bool) -> Void) {
        self.audioChangeListener = onChange
        bindToDefaultOutputDevice()

        // Listen for system default audio output changes (e.g. AirPods connected/disconnected)
        var defDeviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defDeviceAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.bindToDefaultOutputDevice()
            let playing = self?.isSystemAudioPlaying() ?? false
            self?.audioChangeListener?(playing)
        }
    }

    private func bindToDefaultOutputDevice() {
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

        guard status == noErr && defaultOutputDeviceID != kAudioObjectUnknown else { return }
        currentOutputDeviceID = defaultOutputDeviceID

        var runningAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            defaultOutputDeviceID,
            &runningAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            let playing = self?.isSystemAudioPlaying() ?? false
            self?.audioChangeListener?(playing)
        }
    }

    func isSystemAudioPlaying() -> Bool {
        let deviceID: AudioObjectID
        if currentOutputDeviceID != 0 && currentOutputDeviceID != kAudioObjectUnknown {
            deviceID = currentOutputDeviceID
        } else {
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
            guard status == noErr && defaultOutputDeviceID != kAudioObjectUnknown else { return false }
            currentOutputDeviceID = defaultOutputDeviceID
            deviceID = defaultOutputDeviceID
        }

        var isRunning: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let runStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &isRunning
        )

        return runStatus == noErr && isRunning > 0
    }
}
