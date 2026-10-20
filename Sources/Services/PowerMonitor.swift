import Foundation
import IOKit.ps

/// Reads battery state from the IOKit power-source API (returns nil on desktops without a battery).
enum PowerMonitor {
    struct Battery {
        let onBattery: Bool
        let percent: Int
    }

    static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = max(desc[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            return Battery(onBattery: state == kIOPSBatteryPowerValue, percent: current * 100 / max)
        }
        return nil
    }
}
