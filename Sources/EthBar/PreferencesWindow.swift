import AppKit
import ServiceManagement
import SwiftUI

final class PreferencesWindowController {
    private var window: NSWindow?
    private let ethernetMonitor: EthernetMonitor
    private let renderer: PillRenderer
    var onSettingsChanged: (() -> Void)?

    init(ethernetMonitor: EthernetMonitor, renderer: PillRenderer) {
        self.ethernetMonitor = ethernetMonitor
        self.renderer = renderer
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PreferencesView(
            ethernetMonitor: ethernetMonitor,
            renderer: renderer,
            onSettingsChanged: { [weak self] in self?.onSettingsChanged?() }
        )
        let hostingView = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "EthBar Preferences"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }
}

// MARK: - SwiftUI

struct PreferencesView: View {
    let ethernetMonitor: EthernetMonitor
    let renderer: PillRenderer
    let onSettingsChanged: () -> Void

    @State private var displayMode: DisplayMode = .auto
    @State private var displayStyle: DisplayStyle = .medium
    @State private var fontSize: CGFloat = 11
    @State private var sizeClassOverride: DisplaySizeClass?
    @State private var hideFromDock: Bool = UserDefaults.standard.object(forKey: "HideFromDock") as? Bool ?? true
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var showSpeeds: Bool = UserDefaults.standard.object(forKey: "ShowSpeeds") as? Bool ?? true
    @State private var showTopApps: Bool = UserDefaults.standard.object(forKey: "ShowTopApps") as? Bool ?? false
    @State private var showInterfaceDetails: Bool = UserDefaults.standard.object(forKey: "ShowInterfaceDetails") as? Bool ?? false
    @State private var useTrafficAverage: Bool = UserDefaults.standard.object(forKey: "UseTrafficAverage") as? Bool ?? false
    @State private var pollInterval: Double = {
        let val = UserDefaults.standard.double(forKey: "PollInterval")
        return val > 0 ? val : 2.0
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Hide from Dock", isOn: $hideFromDock)
                        .onChange(of: hideFromDock) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "HideFromDock")
                            NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                        }
                    Toggle("Start at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = !newValue
                            }
                        }
                }
                .padding(4)
            }

            // Display
            GroupBox("Display") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: $displayMode) {
                        Text("Auto").tag(DisplayMode.auto)
                        Text("Manual").tag(DisplayMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: displayMode) { newValue in
                        renderer.displayMode = newValue
                        onSettingsChanged()
                    }

                    if displayMode == .auto {
                        Text("Automatically switches based on display size")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Simulate")
                                .font(.caption)
                            Picker("", selection: Binding(
                                get: { sizeClassOverride ?? .compact },
                                set: { sizeClassOverride = $0 }
                            )) {
                                ForEach(DisplaySizeClass.allCases) { sc in
                                    Text(sc.label).tag(sc)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 200)

                            Toggle("", isOn: Binding(
                                get: { sizeClassOverride != nil },
                                set: { enabled in
                                    if enabled {
                                        sizeClassOverride = .compact
                                        DisplayDetector.override = .compact
                                    } else {
                                        sizeClassOverride = nil
                                        DisplayDetector.override = nil
                                    }
                                    onSettingsChanged()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        .onChange(of: sizeClassOverride) { newValue in
                            DisplayDetector.override = newValue
                            onSettingsChanged()
                        }
                    }

                    Picker("Style", selection: $displayStyle) {
                        ForEach(DisplayStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(displayMode == .auto)
                    .opacity(displayMode == .auto ? 0.5 : 1)
                    .onChange(of: displayStyle) { newValue in
                        renderer.displayStyle = newValue
                        onSettingsChanged()
                    }

                    HStack {
                        Text("Font Size")
                        Slider(value: $fontSize, in: 8...24, step: 1)
                        Text("\(Int(fontSize))pt")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    .onChange(of: fontSize) { newValue in
                        renderer.fontSize = newValue
                        onSettingsChanged()
                    }
                }
                .padding(4)
            }

            // Monitoring
            GroupBox("Monitoring") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show upload/download speeds", isOn: $showSpeeds)
                        .onChange(of: showSpeeds) { newValue in
                            ethernetMonitor.showSpeeds = newValue
                            onSettingsChanged()
                        }

                    Toggle("Show IP & MAC address", isOn: $showInterfaceDetails)
                        .onChange(of: showInterfaceDetails) { newValue in
                            ethernetMonitor.showInterfaceDetails = newValue
                            onSettingsChanged()
                        }

                    Toggle("Show top traffic by app", isOn: $showTopApps)
                        .onChange(of: showTopApps) { newValue in
                            ethernetMonitor.showTopApps = newValue
                            onSettingsChanged()
                        }

                    Toggle("Use 10-minute average", isOn: $useTrafficAverage)
                        .disabled(!showTopApps)
                        .opacity(showTopApps ? 1 : 0.5)
                        .onChange(of: useTrafficAverage) { newValue in
                            ethernetMonitor.useTrafficAverage = newValue
                            onSettingsChanged()
                        }

                    HStack {
                        Text("Poll interval")
                        Slider(value: $pollInterval, in: 1...10, step: 0.5)
                        Text("\(String(format: "%.1f", pollInterval))s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    .disabled(!showSpeeds)
                    .opacity(showSpeeds ? 1 : 0.5)
                    .onChange(of: pollInterval) { newValue in
                        ethernetMonitor.pollInterval = newValue
                    }
                }
                .padding(4)
            }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 520)
        .onAppear {
            displayMode = renderer.displayMode
            displayStyle = renderer.displayStyle
            fontSize = renderer.fontSize
            sizeClassOverride = DisplayDetector.override
        }
    }
}
