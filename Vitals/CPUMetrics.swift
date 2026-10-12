import Darwin

final class CPUMetrics {
    private var previous: [UInt32] = []
    private let host = mach_host_self()

    func sample() -> Double {
        var cpuCount: natural_t = 0
        var cpuInfo: UnsafeMutablePointer<integer_t>?
        var count: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &count)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return .nan }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let states = Int(CPU_STATE_MAX)
        var current = [UInt32](repeating: 0, count: states)
        for cpu in 0..<Int(cpuCount) {
            for state in 0..<states {
                current[state] &+= UInt32(bitPattern: info[cpu * states + state])
            }
        }
        defer { previous = current }
        guard !previous.isEmpty else { return .nan }

        let deltas = zip(current, previous).map { UInt64($0 &- $1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return 0 }
        return Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) * 100
    }
}
