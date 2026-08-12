import Darwin
import Foundation
import Mobile

// Keeps olcRTC carrier sockets on a physical interface instead of allowing a
// subsequently enabled Packet Tunnel (Happ) to feed them back into olcRTC's
// own local SOCKS listener. The Go core invokes this before connect/listen.
final class IOSSocketProtector: NSObject, MobileSocketProtectorProtocol {
    static let shared = IOSSocketProtector()

    func protect(_ fileDescriptor: Int) -> Bool {
        guard fileDescriptor >= 0, let interfaceIndex = preferredPhysicalInterfaceIndex() else {
            return true
        }

        let fd = Int32(fileDescriptor)
        var address = sockaddr_storage()
        var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &addressLength)
            }
        }
        guard result == 0 else { return true }

        var index = interfaceIndex
        switch Int32(address.ss_family) {
        case AF_INET:
            _ = setsockopt(
                fd,
                IPPROTO_IP,
                IP_BOUND_IF,
                &index,
                socklen_t(MemoryLayout.size(ofValue: index))
            )
            return true
        case AF_INET6:
            _ = setsockopt(
                fd,
                IPPROTO_IPV6,
                IPV6_BOUND_IF,
                &index,
                socklen_t(MemoryLayout.size(ofValue: index))
            )
            return true
        default:
            return true
        }
    }

    private func preferredPhysicalInterfaceIndex() -> UInt32? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var cellular: UInt32?
        var wifi: UInt32?
        var fallback: UInt32?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            let item = current.pointee
            cursor = item.ifa_next
            guard let address = item.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            let flags = Int32(item.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: item.ifa_name)
            guard !name.hasPrefix("utun"),
                  !name.hasPrefix("ipsec"),
                  !name.hasPrefix("llw") else { continue }
            let index = if_nametoindex(item.ifa_name)
            guard index != 0 else { continue }

            if name.hasPrefix("pdp_ip") {
                cellular = cellular ?? index
            } else if name.hasPrefix("en") {
                wifi = wifi ?? index
            } else {
                fallback = fallback ?? index
            }
        }
        return cellular ?? wifi ?? fallback
    }
}
