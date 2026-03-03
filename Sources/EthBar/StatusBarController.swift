import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private var currentStatus: EthernetStatus = .disconnected
    var onPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        buildMenu()
    }

    func updateIcon(_ image: NSImage) {
        statusItem.button?.image = image
    }

    func updateStatus(_ status: EthernetStatus) {
        self.currentStatus = status
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if currentStatus.isConnected {
            let headerTitle = currentStatus.connectionType?.menuLabel ?? "Connected"
            let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
            menu.addItem(header)

            menu.addItem(NSMenuItem.separator())

            if let name = currentStatus.displayName ?? currentStatus.interfaceName {
                let item = NSMenuItem(title: "Interface: \(name)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }

            if let speed = currentStatus.linkSpeed {
                let item = NSMenuItem(title: "Link Speed: \(speed)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }

            let showDetails = UserDefaults.standard.object(forKey: "ShowInterfaceDetails") as? Bool ?? false
            if showDetails {
                if let ip = currentStatus.ipv4Address {
                    let item = NSMenuItem(title: "IP: \(ip)", action: nil, keyEquivalent: "")
                    menu.addItem(item)
                }

                if let mac = currentStatus.macAddress {
                    let item = NSMenuItem(title: "MAC: \(mac)", action: nil, keyEquivalent: "")
                    menu.addItem(item)
                }
            }

            let showSpeeds = UserDefaults.standard.object(forKey: "ShowSpeeds") as? Bool ?? true
            if showSpeeds {
                menu.addItem(NSMenuItem.separator())
                let up = formatSpeed(currentStatus.uploadBytesPerSec)
                let down = formatSpeed(currentStatus.downloadBytesPerSec)
                let throughput = NSMenuItem(title: "\u{2191} \(up)  \u{2193} \(down)", action: nil, keyEquivalent: "")
                menu.addItem(throughput)
            }

            if !currentStatus.topApps.isEmpty {
                menu.addItem(NSMenuItem.separator())
                let useAvg = UserDefaults.standard.object(forKey: "UseTrafficAverage") as? Bool ?? false
                let header = NSMenuItem(title: useAvg ? "Top Traffic (10m avg)" : "Top Traffic", action: nil, keyEquivalent: "")
                menu.addItem(header)
                for entry in currentStatus.topApps {
                    let up = formatSpeed(entry.uploadBytesPerSec)
                    let down = formatSpeed(entry.downloadBytesPerSec)
                    let item = NSMenuItem(
                        title: "  \(entry.appName)  \u{2191}\(up)  \u{2193}\(down)",
                        action: nil,
                        keyEquivalent: ""
                    )
                    menu.addItem(item)
                }
            }
        } else {
            let header = NSMenuItem(title: "Disconnected", action: nil, keyEquivalent: "")
            menu.addItem(header)
        }

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences\u{2026}", action: #selector(preferencesClicked), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit EthBar", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func preferencesClicked() {
        onPreferences?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }

    // MARK: - Speed Formatting

    private func formatSpeed(_ bytesPerSec: UInt64) -> String {
        let b = Double(bytesPerSec)
        if b < 1024 {
            return "\(bytesPerSec) B/s"
        } else if b < 1024 * 1024 {
            return String(format: "%.0f KB/s", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", b / (1024 * 1024))
        } else {
            return String(format: "%.2f GB/s", b / (1024 * 1024 * 1024))
        }
    }
}
