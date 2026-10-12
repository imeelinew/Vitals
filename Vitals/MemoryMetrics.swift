import Foundation
import Darwin

final class MemoryMetrics {
    private let totalBytes = ProcessInfo.processInfo.physicalMemory
    private let pageSize = UInt64(vm_kernel_page_size)
    private let host = mach_host_self()

    func sample() -> Double {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS, totalBytes > 0 else { return 0 }

        let internalPages = UInt64(info.internal_page_count)
        let purgeablePages = UInt64(info.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let used = (appPages + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * pageSize

        return Double(used) / Double(totalBytes) * 100
    }
}
