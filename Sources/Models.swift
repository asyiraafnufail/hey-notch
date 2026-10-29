import Cocoa

struct DetailedBatteryInfo {
    let percent: Int
    let isCharging: Bool
    let isAC: Bool
    let watts: Int?
    let timeToFull: Int?
    let timeToEmpty: Int?
}

struct RamInfo {
    let usedGB: Double
    let totalGB: Double
    let percent: Int
}
