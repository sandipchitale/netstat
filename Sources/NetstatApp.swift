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
    
    var body: some Scene {
        Window("TCP Port Monitor", id: "main") {
            ContentView()
                .frame(minWidth: 1200, idealWidth: 1800, minHeight: 700, idealHeight: 900)
        }
        .windowStyle(.titleBar)
    }
}
