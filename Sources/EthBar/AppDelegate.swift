import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, EthernetMonitorDelegate {
    private let ethernetMonitor = EthernetMonitor()
    private let statusBar = StatusBarController()
    private let renderer = PillRenderer()
    private lazy var prefsController = PreferencesWindowController(
        ethernetMonitor: ethernetMonitor,
        renderer: renderer
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hideFromDock = UserDefaults.standard.object(forKey: "HideFromDock") as? Bool ?? true
        NSApp.setActivationPolicy(hideFromDock ? .accessory : .regular)

        ethernetMonitor.delegate = self

        statusBar.onPreferences = { [weak self] in
            self?.prefsController.show()
        }
        statusBar.onQuit = {
            NSApp.terminate(nil)
        }

        prefsController.onSettingsChanged = { [weak self] in
            self?.ethernetMonitor.refresh()
        }

        // Defer initial start to the next run loop pass so the status bar
        // has fully materialised.
        DispatchQueue.main.async { [weak self] in
            self?.ethernetMonitor.start()
        }
    }

    // MARK: - EthernetMonitorDelegate

    func didUpdateEthernetStatus(_ status: EthernetStatus) {
        let image = renderer.render(status: status)
        statusBar.updateIcon(image)
        statusBar.updateStatus(status)
    }
}
