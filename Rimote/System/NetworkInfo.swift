import Foundation

/// Reads the Mac's primary LAN IPv4 address, shown in the menubar popover so
/// the user can pair by IP on networks where Bonjour discovery is blocked
/// (campus / office Wi-Fi).
enum NetworkInfo {

    /// The first non-loopback IPv4 address, preferring the primary interfaces
    /// (`en0` = built-in Wi-Fi/Ethernet, then `en…` in order). `nil` when the
    /// Mac has no LAN address at all.
    static func primaryIPv4() -> String? {
        var addresses: [(interface: String, address: String)] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                  (Int32(ifa.ifa_flags) & IFF_LOOPBACK) == 0,
                  (Int32(ifa.ifa_flags) & IFF_UP) != 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            addresses.append((String(cString: ifa.ifa_name), String(cString: host)))
        }

        // en0 first, then the rest of en* sorted, then anything else.
        return (addresses.first { $0.interface == "en0" }
                ?? addresses.filter { $0.interface.hasPrefix("en") }
                    .sorted { $0.interface < $1.interface }.first
                ?? addresses.first)?.address
    }
}
