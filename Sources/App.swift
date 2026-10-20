import SwiftUI
import AppKit

/// Entry point: a menu-bar-only app whose sun icon opens the boost popover.
@main
struct XdrBoostBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = BoostController.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(controller)
        } label: {
            Image(systemName: controller.menuBarSymbol)
                .accessibilityLabel("XdrBoostBar: \(controller.statusText)")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Wires app lifecycle events: starts the controller, registers the hotkey and restores displays on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BoostController.shared.start()
        // Control + Option + B toggles the boost globally (Carbon hotkeys need no Accessibility access).
        hotKey = HotKey(keyCode: HotKey.keyB, modifiers: HotKey.controlOption) {
            BoostController.shared.toggleEnabled()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BoostController.shared.shutdown()
    }
}
