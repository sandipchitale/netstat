import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app shows up in the Dock and menu bar, and can take focus
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct NetstatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Single shared monitor so every window (main table + Launch Command
    // windows) operates on the same connection state and can refresh it.
    @State private var monitor = ConnectionMonitor()

    var body: some Scene {
        Window("TCP Port Monitor", id: "main") {
            ContentView(monitor: monitor)
                .frame(minWidth: 1200, idealWidth: 1800, minHeight: 700, idealHeight: 900)
        }
        .windowStyle(.titleBar)

        // Auxiliary, freely-resizable window showing the full launch command
        // for a process. A real window (not a sheet) so it has native resize.
        WindowGroup("Launch Command", id: "command-info", for: Connection.self) { $connection in
            if let connection {
                CommandWindow(connection: connection, monitor: monitor)
            }
        }
        .defaultSize(width: 1300, height: 760)
    }
}
