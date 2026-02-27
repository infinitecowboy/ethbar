# EthBar

A lightweight macOS menu bar app that shows your ethernet connection status and throughput at a glance.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Status indicator** — green dot when connected, gray outline when disconnected
- **Live throughput** — upload/download speeds updated every 2 seconds
- **Three display modes** — compact (dot only), medium (dot + ETH), large (dot + ETH + speeds)
- **Auto display mode** — automatically picks the right density based on your display size
- **Interface details** — link speed, IP address, MAC address in the dropdown menu
- **Preferences panel** — configure display mode, font size, poll interval, and more
- **Hide from Dock** — runs as a pure menu bar app (hidden by default)
- **Start at Login** — optional auto-launch via SMAppService

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel

## Build & Run

```
swift build
swift run
```

## Install as .app

```
./scripts/bundle.sh
open /Applications/EthBar.app
```

## How It Works

EthBar uses `NWPathMonitor(.wiredEthernet)` for event-driven connect/disconnect detection and `SCNetworkInterfaceCopyAll()` to discover the active ethernet interface. Throughput is measured via `sysctl` reading the kernel's 64-bit byte counters (`ifi_ibytes`/`ifi_obytes`) and computing deltas over the poll interval.

## Project Structure

```
Sources/EthBar/
  main.swift               App entry point
  AppDelegate.swift        Wires monitor, renderer, and status bar
  EthernetMonitor.swift    Connection detection + throughput polling
  PillRenderer.swift       Renders dot/pill/pill+speeds indicator
  DisplayDetector.swift    Classifies primary display size for auto mode
  StatusBarController.swift  Menu bar item and dropdown
  PreferencesWindow.swift  SwiftUI preferences panel
```

## License

MIT
