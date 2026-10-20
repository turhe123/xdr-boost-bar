import SwiftUI
import AppKit

/// The menu bar popover: on/off switch, boost slider, display picker, battery saver and login options.
struct ContentView: View {
    @EnvironmentObject private var controller: BoostController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if controller.isSupported {
                controls
            } else {
                Label("No display with extended dynamic range (EDR) headroom was found. XdrBoostBar works with MacBook Pro Liquid Retina XDR and Pro Display XDR screens.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = controller.notice {
                Label(notice.prefix(1).capitalized + notice.dropFirst(), systemImage: "thermometer.sun")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Divider()
            Text("Boosting raises battery use and heat. Screenshots and screen recordings may look brightened while it is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: controller.menuBarSymbol)
                .font(.title2)
                .foregroundStyle(controller.isActive ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("XdrBoostBar").font(.headline)
                Text(controller.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $controller.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!controller.isSupported)
                .help("Toggle boost (⌃⌥B)")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Boost")
                Slider(value: $controller.boost, in: 0...100)
                Text("\(Int(controller.boost))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            .disabled(!controller.enabled)

            Text("Displays").font(.subheadline.bold())
            ForEach(controller.displays) { display in
                Toggle(isOn: displayBinding(display.id)) {
                    Text(display.name)
                    Text(String(format: "Headroom %.1f×", display.headroom)).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Toggle("Battery saver below", isOn: $controller.batterySaver)
                TextField("", value: $controller.batteryThreshold, format: .number)
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                    .disabled(!controller.batterySaver)
                    .onChange(of: controller.batteryThreshold) { _, value in
                        let clamped = min(max(value, 0), 100)
                        if clamped != value { controller.batteryThreshold = clamped }
                    }
                Text("%")
            }
            .help("Pauses the boost on battery below this level, or in Low Power Mode")

            Toggle("Compatibility mode (gamma table)", isOn: $controller.useGammaFallback)
                .help("Use if the overlay method does not brighten your screen")
            Toggle("Launch at login", isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }))
            if let error = controller.loginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Support / Donate ❤️") {
                NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func displayBinding(_ id: CGDirectDisplayID) -> Binding<Bool> {
        Binding(
            get: { !controller.disabledDisplays.contains(id) },
            set: { on in
                if on { controller.disabledDisplays.remove(id) } else { controller.disabledDisplays.insert(id) }
            })
    }
}
