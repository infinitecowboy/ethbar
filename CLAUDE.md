# EthBar

macOS menubar app that shows ethernet connection status and optionally upload/download throughput.

## Build & Run

```
swift build
swift run
```

## Bundle as .app

```
./scripts/bundle.sh
```

Builds release binary, creates .app bundle, installs to /Applications.

## Architecture

```
AppDelegate
├── EthernetMonitor       (NWPathMonitor + sysctl throughput polling)
├── PillRenderer          (menubar icon drawing — dot/pill/pill+speeds)
├── StatusBarController   (NSStatusItem + NSMenu)
└── PreferencesWindowController (SwiftUI settings)
```

## Stack

- Swift 5.9, SPM, AppKit, macOS 13+
- Network framework (NWPathMonitor for wired ethernet)
- SystemConfiguration (SCNetworkInterface for interface discovery)
- SwiftUI (Preferences window only)
- Berkeley Mono font (falls back to monospacedSystemFont)

## Display Modes

| Mode | Content | When (auto) |
|------|---------|-------------|
| compact | Colored dot only | <16" display |
| medium | Dot + "ETH" in pill | 16–25" display |
| large | Dot + "ETH" + throughput in pill | >25" display |

## UserDefaults Keys

| Key | Type | Default |
|-----|------|---------|
| `HideFromDock` | Bool | `true` |
| `DisplayMode` | String | `"auto"` |
| `DisplayStyle` | String | `"medium"` |
| `FontSize` | Float | `14` |
| `ShowSpeeds` | Bool | `true` |
| `PollInterval` | Double | `2.0` |
| `DisplaySizeClassOverride` | String? | `nil` |

## Key Implementation Details

- `SIOCGIFXMEDIA` (0xc02c6948) is hardcoded because Swift can't import the `_IOWR` macro with struct args
- Throughput uses `sysctl` with `CTL_NET/PF_LINK/NETLINK_GENERIC/IFMIB_IFDATA` for 64-bit byte counters
- Pill is stroked outline (no fill) with white text to match dark menubar aesthetic
- Fixed-width speed formatting prevents pill from jumping as values change
