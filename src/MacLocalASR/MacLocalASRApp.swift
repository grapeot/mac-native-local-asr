import AppKit
import SwiftUI

@main
struct MacLocalASRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        appStateShared = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: appState)
        } label: {
            Label(LocalizableStrings.appName, systemImage: appState.menuBarSymbol)
                .foregroundStyle(appState.stateColor)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
var appStateShared: AppState!
@MainActor
var appDelegateShared: AppDelegate!

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let controlServer = ControlServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appDelegateShared = self

        controlServer.start(appState: appStateShared)

        if !SettingsStore.isConfigured() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showSettings()
            }
        } else {
            // Show main window on launch when already configured
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showMainWindow()
            }
        }
    }

    func showMainWindow() {
        if mainWindow == nil {
            let hostingController = NSHostingController(rootView: MainRecordView(appState: appStateShared))
            let window = NSWindow(contentViewController: hostingController)
            window.title = LocalizableStrings.appName
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 640))
            window.minSize = NSSize(width: 360, height: 480)
            window.center()
            window.isReleasedWhenClosed = false
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView(appState: appStateShared))
            let window = NSWindow(contentViewController: hostingController)
            window.title = LocalizableStrings.appName
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 280))
            window.minSize = NSSize(width: 400, height: 200)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}