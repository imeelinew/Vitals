import Foundation
import Darwin

final class CPUMetrics {
    private var current: [Int32] = []
    private var previous: [Int32] = []
    private let host: host_t = mach_host_self()

    func sample() -> Double {
        var numCPU: natural_t = 0
        var cpuInfo: UnsafeMutablePointer<integer_t>? = nil
        var cpuInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPU,
            &cpuInfo,
            &cpuInfoCount
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return .nan }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(host, vm_address_t(UInt(bitPattern: info)), size)
        }

        let states = Int(CPU_STATE_MAX)
        let n = Int(numCPU)
        let needed = n * states
        if current.count != needed {
            current = [Int32](repeating: 0, count: needed)
        }
        for i in 0..<needed {
            current[i] = info[i]
        }

        guard !previous.isEmpty, previous.count == current.count else {
            swap(&previous, &current)
            return .nan
        }

        var userDelta: Int64 = 0
        var systemDelta: Int64 = 0
        var niceDelta: Int64 = 0
        var idleDelta: Int64 = 0
        var idx = 0
        while idx < current.count {
            userDelta   += Int64(current[idx + Int(CPU_STATE_USER)])   - Int64(previous[idx + Int(CPU_STATE_USER)])
            systemDelta += Int64(current[idx + Int(CPU_STATE_SYSTEM)]) - Int64(previous[idx + Int(CPU_STATE_SYSTEM)])
            niceDelta   += Int64(current[idx + Int(CPU_STATE_NICE)])   - Int64(previous[idx + Int(CPU_STATE_NICE)])
            idleDelta   += Int64(current[idx + Int(CPU_STATE_IDLE)])   - Int64(previous[idx + Int(CPU_STATE_IDLE)])
            idx += states
        }

        swap(&previous, &current)

        let total = userDelta + systemDelta + niceDelta + idleDelta
        guard total > 0 else { return 0 }
        let used = userDelta + systemDelta + niceDelta
        return Double(used) / Double(total) * 100.0
    }
}
