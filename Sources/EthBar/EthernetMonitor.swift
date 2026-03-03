import Foundation
import Network
import SystemConfiguration

enum ConnectionType {
    case ethernet
    case wifi

    var label: String {
        switch self {
        case .ethernet: return "ENET"
        case .wifi: return "WIFI"
        }
    }

    var menuLabel: String {
        switch self {
        case .ethernet: return "Ethernet Connected"
        case .wifi: return "Wi-Fi Connected"
        }
    }

    var nettopFilter: String {
        switch self {
        case .ethernet: return "wired"
        case .wifi: return "wifi"
        }
    }
}

struct EthernetStatus {
    var isConnected: Bool
    var connectionType: ConnectionType?
    var interfaceName: String?
    var displayName: String?
    var linkSpeed: String?
    var ipv4Address: String?
    var macAddress: String?
    var uploadBytesPerSec: UInt64
    var downloadBytesPerSec: UInt64
    var topApps: [AppTrafficEntry]

    static let disconnected = EthernetStatus(
        isConnected: false,
        connectionType: nil,
        interfaceName: nil,
        displayName: nil,
        linkSpeed: nil,
        ipv4Address: nil,
        macAddress: nil,
        uploadBytesPerSec: 0,
        downloadBytesPerSec: 0,
        topApps: []
    )
}

protocol EthernetMonitorDelegate: AnyObject {
    func didUpdateEthernetStatus(_ status: EthernetStatus)
}

final class EthernetMonitor {
    weak var delegate: EthernetMonitorDelegate?

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ethernet.monitor")
    private var throughputTimer: DispatchSourceTimer?
    private var lastBytes: (inBytes: UInt64, outBytes: UInt64)?
    private var lastSampleTime: Date?
    private var currentBSDName: String?
    private var currentConnectionType: ConnectionType?
    private var isConnected = false
    private let trafficMonitor = TrafficMonitor()

    var pollInterval: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: "PollInterval")
            return val > 0 ? val : 2.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "PollInterval")
            if isConnected { restartThroughputTimer() }
        }
    }

    var showSpeeds: Bool {
        get { UserDefaults.standard.object(forKey: "ShowSpeeds") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowSpeeds")
            if isConnected {
                if newValue {
                    startThroughputTimer()
                } else {
                    stopThroughputTimer()
                    // Push an update without speeds
                    let status = buildStatus(uploadPerSec: 0, downloadPerSec: 0, topApps: [])
                    DispatchQueue.main.async { self.delegate?.didUpdateEthernetStatus(status) }
                }
            }
        }
    }

    var showTopApps: Bool {
        get { UserDefaults.standard.object(forKey: "ShowTopApps") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "ShowTopApps") }
    }

    var showInterfaceDetails: Bool {
        get { UserDefaults.standard.object(forKey: "ShowInterfaceDetails") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "ShowInterfaceDetails") }
    }

    var useTrafficAverage: Bool {
        get { UserDefaults.standard.object(forKey: "UseTrafficAverage") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "UseTrafficAverage") }
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            // Prioritize ethernet over WiFi
            let connectionType: ConnectionType?
            if path.usesInterfaceType(.wiredEthernet) {
                connectionType = .ethernet
            } else if path.usesInterfaceType(.wifi) {
                connectionType = .wifi
            } else {
                connectionType = nil
            }
            self.monitorQueue.async {
                self.handlePathUpdate(connectionType: connectionType)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func stop() {
        pathMonitor.cancel()
        stopThroughputTimer()
    }

    func refresh() {
        monitorQueue.async { [weak self] in
            guard let self = self else { return }
            let status = self.isConnected
                ? self.buildStatus(uploadPerSec: 0, downloadPerSec: 0)
                : .disconnected
            DispatchQueue.main.async { self.delegate?.didUpdateEthernetStatus(status) }
        }
    }

    // MARK: - Path Handling

    private func handlePathUpdate(connectionType: ConnectionType?) {
        let connected = connectionType != nil
        isConnected = connected
        currentConnectionType = connectionType

        if let connectionType = connectionType {
            currentBSDName = findInterface(for: connectionType)
            lastBytes = nil
            lastSampleTime = nil
            trafficMonitor.connectionType = connectionType

            let status = buildStatus(uploadPerSec: 0, downloadPerSec: 0)
            DispatchQueue.main.async { self.delegate?.didUpdateEthernetStatus(status) }

            if showSpeeds {
                startThroughputTimer()
            }
        } else {
            currentBSDName = nil
            currentConnectionType = nil
            stopThroughputTimer()
            trafficMonitor.reset()
            DispatchQueue.main.async { self.delegate?.didUpdateEthernetStatus(.disconnected) }
        }
    }

    // MARK: - Interface Discovery

    private func findInterface(for connectionType: ConnectionType) -> String? {
        let scType: String
        switch connectionType {
        case .ethernet:
            scType = kSCNetworkInterfaceTypeEthernet as String
        case .wifi:
            scType = kSCNetworkInterfaceTypeIEEE80211 as String
        }

        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for iface in interfaces {
            if let type = SCNetworkInterfaceGetInterfaceType(iface) as String?,
               type == scType {
                return SCNetworkInterfaceGetBSDName(iface) as String?
            }
        }
        return nil
    }

    // MARK: - Build Status

    private func buildStatus(uploadPerSec: UInt64, downloadPerSec: UInt64, topApps: [AppTrafficEntry] = []) -> EthernetStatus {
        let bsdName = currentBSDName
        var ipv4: String?
        var mac: String?
        var displayName: String?
        var linkSpeed: String?

        if let bsdName = bsdName {
            ipv4 = getIPv4Address(for: bsdName)
            mac = getMACAddress(for: bsdName)
            linkSpeed = getLinkSpeed(for: bsdName)

            // Get display name from SCNetworkInterface
            if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
                for iface in interfaces {
                    if let name = SCNetworkInterfaceGetBSDName(iface) as String?, name == bsdName {
                        displayName = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?
                        break
                    }
                }
            }
        }

        return EthernetStatus(
            isConnected: true,
            connectionType: currentConnectionType,
            interfaceName: bsdName,
            displayName: displayName,
            linkSpeed: linkSpeed,
            ipv4Address: ipv4,
            macAddress: mac,
            uploadBytesPerSec: uploadPerSec,
            downloadBytesPerSec: downloadPerSec,
            topApps: topApps
        )
    }

    // MARK: - IPv4 Address

    private func getIPv4Address(for interfaceName: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == interfaceName else { continue }

            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                var addr = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buffer)
            }
        }
        return nil
    }

    // MARK: - MAC Address

    private func getMACAddress(for interfaceName: String) -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for iface in interfaces {
            if let name = SCNetworkInterfaceGetBSDName(iface) as String?, name == interfaceName {
                return SCNetworkInterfaceGetHardwareAddressString(iface) as String?
            }
        }
        return nil
    }

    // MARK: - Link Speed

    private func getLinkSpeed(for interfaceName: String) -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var ifmr = ifmediareq()
        _ = interfaceName.withCString { cstr in
            strlcpy(&ifmr.ifm_name.0, cstr, MemoryLayout.size(ofValue: ifmr.ifm_name))
        }

        // SIOCGIFXMEDIA = _IOWR('i', 72, struct ifmediareq) — Swift can't import
        // the macro because it references a struct, so we use the precomputed value.
        let SIOCGIFXMEDIA: UInt = 0xc02c6948
        let result = withUnsafeMutablePointer(to: &ifmr) { ptr in
            ioctl(sock, SIOCGIFXMEDIA, ptr)
        }
        guard result >= 0 else { return nil }

        let options = ifmr.ifm_active
        // Extract subtype from media word
        let subtype = Int32(options) & Int32(bitPattern: 0x000000FF)

        // Map common ethernet subtypes to speeds
        // IFM_10_T=6, IFM_100_TX=16, IFM_1000_T=32, IFM_10G_T=48, IFM_2500_T=55, IFM_5000_T=56
        switch subtype {
        case 6: return "10 Mbps"
        case 16: return "100 Mbps"
        case 32: return "1 Gbps"
        case 48: return "10 Gbps"
        case 55: return "2.5 Gbps"
        case 56: return "5 Gbps"
        default: return nil
        }
    }

    // MARK: - Throughput via sysctl

    private func startThroughputTimer() {
        stopThroughputTimer()

        // Take initial sample
        if let bsdName = currentBSDName, let idx = interfaceIndex(for: bsdName) {
            let counters = getInterfaceCounters(index: idx)
            lastBytes = counters
            lastSampleTime = Date()
        }

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.sampleThroughput()
        }
        timer.resume()
        throughputTimer = timer
    }

    private func stopThroughputTimer() {
        throughputTimer?.cancel()
        throughputTimer = nil
        lastBytes = nil
        lastSampleTime = nil
    }

    private func restartThroughputTimer() {
        if isConnected && showSpeeds {
            startThroughputTimer()
        }
    }

    private func sampleThroughput() {
        guard let bsdName = currentBSDName,
              let idx = interfaceIndex(for: bsdName) else { return }

        let now = Date()
        let counters = getInterfaceCounters(index: idx)

        var uploadPerSec: UInt64 = 0
        var downloadPerSec: UInt64 = 0

        if let prev = lastBytes, let prevTime = lastSampleTime {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let inDelta = counters.inBytes >= prev.inBytes
                    ? counters.inBytes - prev.inBytes
                    : counters.inBytes // counter wrapped
                let outDelta = counters.outBytes >= prev.outBytes
                    ? counters.outBytes - prev.outBytes
                    : counters.outBytes // counter wrapped

                downloadPerSec = UInt64(Double(inDelta) / elapsed)
                uploadPerSec = UInt64(Double(outDelta) / elapsed)
            }
        }

        lastBytes = counters
        lastSampleTime = now

        let topApps = showTopApps
            ? (useTrafficAverage ? trafficMonitor.sampleAverage() : trafficMonitor.sample())
            : []
        let status = buildStatus(uploadPerSec: uploadPerSec, downloadPerSec: downloadPerSec, topApps: topApps)
        DispatchQueue.main.async { self.delegate?.didUpdateEthernetStatus(status) }
    }

    private func interfaceIndex(for name: String) -> Int32? {
        let idx = if_nametoindex(name)
        return idx > 0 ? Int32(idx) : nil
    }

    private func getInterfaceCounters(index: Int32) -> (inBytes: UInt64, outBytes: UInt64) {
        var mib = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL]
        var ifmd = ifmibdata()
        var len = MemoryLayout<ifmibdata>.size

        let result = mib.withUnsafeMutableBufferPointer { buf in
            sysctl(buf.baseAddress, UInt32(buf.count), &ifmd, &len, nil, 0)
        }

        if result == 0 {
            return (
                inBytes: UInt64(ifmd.ifmd_data.ifi_ibytes),
                outBytes: UInt64(ifmd.ifmd_data.ifi_obytes)
            )
        }
        return (0, 0)
    }
}
