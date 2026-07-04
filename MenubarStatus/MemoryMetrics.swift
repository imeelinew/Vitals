import Foundation
import Darwin

struct MemoryInfo {
    let usedBytes: UInt64
    let totalBytes: UInt64
    var usagePercent: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0
    }
}

final class MemoryMetrics {
    let totalBytes: UInt64
    private let pageSize: vm_size_t

    init() {
        self.pageSize = vm_kernel_page_size
        var size: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)
        self.totalBytes = size
    }

    func sample() -> MemoryInfo {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()

        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return MemoryInfo(usedBytes: 0, totalBytes: totalBytes)
        }

        let ps = UInt64(pageSize)
        let internalPages = UInt64(info.internal_page_count)
        let purgeablePages = UInt64(info.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let appMemory = appPages * ps
        let wired = UInt64(info.wire_count) * ps
        let compressed = UInt64(info.compressor_page_count) * ps
        let used = appMemory + wired + compressed

        return MemoryInfo(usedBytes: used, totalBytes: totalBytes)
    }
}
