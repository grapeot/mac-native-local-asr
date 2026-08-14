import AppKit
import SwiftUI

@main
struct MacLocalASRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: appState)
        } label: {
            Label(LocalizableStrings.appName, systemImage: appState.menuBarSymbol)
                .foregroundStyle(appState.stateColor)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Settings", id: "settings") {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 240)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Open settings on first launch if bridge is not configured
        do {
            _ = try SettingsStore.current()
        } catch {
            // Settings not configured — open the settings window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}