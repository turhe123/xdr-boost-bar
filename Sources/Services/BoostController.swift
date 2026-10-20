import AppKit
import Combine
import ServiceManagement

/// A display that can be boosted, as shown in the popover's display picker.
struct BoostDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let headroom: Double
}

/// Owns the boost state: detects EDR-capable screens, manages overlay windows / gamma tables,
/// applies battery and thermal limits, ramps the boost smoothly, and persists settings.
final class BoostController: ObservableObject {
    static let shared = BoostController()

    /// Largest multiplier ever applied; roughly the gap between SDR and sustained full-screen HDR.
    private static let maxFactorCap = 2.0
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); updateTarget() } }
    @Published var boost: Double { didSet { defaults.set(boost, forKey: "boost"); applyLevel() } }
    @Published var batterySaver: Bool { didSet { defaults.set(batterySaver, forKey: "batterySaver"); updateTarget() } }
    @Published var batteryThreshold: Int { didSet { defaults.set(batteryThreshold, forKey: "batteryThreshold"); updateTarget() } }
    @Published var useGammaFallback: Bool { didSet { defaults.set(useGammaFallback, forKey: "useGammaFallback"); rebuild() } }
    @Published var disabledDisplays: Set<CGDirectDisplayID> {
        didSet { defaults.set(disabledDisplays.map { Int($0) }, forKey: "disabledDisplays"); rebuild() }
    }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @Published private(set) var displays: [BoostDisplay] = []
    @Published private(set) var notice: String?
    @Published private(set) var loginError: String?

    /// Current ramped strength (0…1) multiplied onto the user's boost.
    private var level = 0.0
    private var target = 0.0
    private var rampTimer: Timer?
    private var pollTimer: Timer?
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        defaults.register(defaults: ["enabled": false, "boost": 50.0, "batterySaver": true,
                                     "batteryThreshold": 30, "useGammaFallback": false])
        enabled = defaults.bool(forKey: "enabled")
        boost = defaults.double(forKey: "boost")
        batterySaver = defaults.bool(forKey: "batterySaver")
        batteryThreshold = defaults.integer(forKey: "batteryThreshold")
        useGammaFallback = defaults.bool(forKey: "useGammaFallback")
        let stored = defaults.array(forKey: "disabledDisplays") as? [Int] ?? []
        disabledDisplays = Set(stored.map { CGDirectDisplayID(truncatingIfNeeded: $0) })
    }

    // MARK: Derived state

    var isSupported: Bool { !displays.isEmpty }
    var isActive: Bool { enabled && isSupported && target > 0 }

    var statusText: String {
        if !isSupported { return "Unsupported" }
        if !enabled { return "Off" }
        if let notice { return "Limited – \(notice)" }
        return "On · \(Int(boost))%"
    }

    var menuBarSymbol: String {
        if !isSupported { return "sun.min" }
        return isActive ? "sun.max.fill" : "sun.max"
    }

    // MARK: Lifecycle

    func start() {
        let center = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() },
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() },
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateTarget() },
            center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.updateTarget() },
        ]
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.updateTarget() }
        rebuild()
    }

    func shutdown() {
        tearDown()
        CGDisplayRestoreColorSyncSettings()
    }

    func toggleEnabled() {
        guard isSupported else { NSSound.beep(); return }
        enabled.toggle()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Displays & windows

    /// Re-detects EDR displays and rebuilds every overlay window from scratch.
    func rebuild() {
        displays = NSScreen.screens.compactMap { screen in
            let headroom = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            guard headroom > 1.0, let id = Self.displayID(of: screen) else { return nil }
            return BoostDisplay(id: id, name: screen.localizedName, headroom: headroom)
        }
        tearDown()
        CGDisplayRestoreColorSyncSettings()
        updateTarget()
        if level > 0 { buildWindows() }
        applyLevel()
    }

    private func buildWindows() {
        guard windows.isEmpty else { return }
        let mode: OverlayWindow.Mode = useGammaFallback ? .gamma : .overlay
        for screen in NSScreen.screens {
            guard let id = Self.displayID(of: screen),
                  displays.contains(where: { $0.id == id }),
                  !disabledDisplays.contains(id),
                  let window = OverlayWindow(screen: screen, displayID: id, mode: mode) else { continue }
            window.orderFrontRegardless()
            windows[id] = window
        }
    }

    private func tearDown() {
        windows.values.forEach { $0.close() }
        windows.removeAll()
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: Limits & ramping

    /// Recomputes the target strength from user choice, thermal state and battery saver.
    private func updateTarget() {
        let thermal = ProcessInfo.processInfo.thermalState
        var newNotice: String?
        var newTarget = enabled && isSupported ? 1.0 : 0.0
        if thermal == .serious || thermal == .critical {
            newTarget = 0
            newNotice = "Mac is running hot, boost paused"
        } else if batterySaver {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                newTarget = 0
                newNotice = "Low Power Mode is on"
            } else if let battery = PowerMonitor.battery(), battery.onBattery, battery.percent < batteryThreshold {
                newTarget = 0
                newNotice = "battery below \(batteryThreshold)%"
            }
        }
        notice = enabled ? newNotice : nil
        target = newTarget
        if abs(target - level) > 0.001, rampTimer == nil {
            // Ramp across the full range in one second at ~60 fps.
            rampTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.stepRamp() }
        }
    }

    private func stepRamp() {
        let step = 1.0 / 60
        level = target > level ? min(target, level + step) : max(target, level - step)
        if level > 0 { buildWindows() }
        applyLevel()
        if abs(level - target) < 0.001 {
            rampTimer?.invalidate()
            rampTimer = nil
            if level == 0 {
                tearDown()
                CGDisplayRestoreColorSyncSettings()
            }
        }
    }

    /// Pushes the current factor to every window (and gamma table in fallback mode).
    private func applyLevel() {
        for (id, window) in windows {
            let headroom = displays.first(where: { $0.id == id })?.headroom ?? 1
            let maxFactor = min(headroom, Self.maxFactorCap)
            let factor = 1 + (maxFactor - 1) * (boost / 100) * level
            if useGammaFallback {
                // Keep EDR alive with a bright pixel, then stretch the output curve past 1.0.
                window.apply(factor: maxFactor)
                let f = Float(factor)
                CGSetDisplayTransferByFormula(id, 0, f, 1, 0, f, 1, 0, f, 1)
            } else {
                window.apply(factor: factor)
            }
        }
    }
}
