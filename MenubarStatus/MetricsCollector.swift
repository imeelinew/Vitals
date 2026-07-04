import Foundation
import Observation

@Observable
final class MetricsCollector {
    var cpuUsage: Double = -1
    var memoryUsage: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var totalMemoryBytes: UInt64 = 0
    var pressure: MemoryPressureState = .normal

    var onTitleUpdate: ((Double, Double) -> Void)?

    private let cpu = CPUMetrics()
    private let memory = MemoryMetrics()
    private let pressureMonitor = MemoryPressureMonitor()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.eli.MenubarStatus.collector", qos: .utility)

    var hasCPUSample: Bool { cpuUsage >= 0 }

    func start() {
        totalMemoryBytes = memory.totalBytes
        pressureMonitor.start { [weak self] state in
            self?.pressure = state
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2.0)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()
        timer = t
    }

    func sampleOnce() {
        queue.async { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        let cpuVal = cpu.sample()
        let mem = memory.sample()
        #if DEBUG
        let usedGB = Double(mem.usedBytes) / 1_073_741_824
        let totalGB = Double(mem.totalBytes) / 1_073_741_824
        if cpuVal.isNaN {
            print("[metrics] CPU=--  MEM=\(String(format: "%.1f", mem.usagePercent))% (\(String(format: "%.2f", usedGB))/\(String(format: "%.1f", totalGB)) GB) pressure=\(pressure.label)")
        } else {
            print("[metrics] CPU=\(String(format: "%.1f", cpuVal))%  MEM=\(String(format: "%.1f", mem.usagePercent))% (\(String(format: "%.2f", usedGB))/\(String(format: "%.1f", totalGB)) GB) pressure=\(pressure.label)")
        }
        fflush(stdout)
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !cpuVal.isNaN {
                self.cpuUsage = cpuVal
            }
            self.memoryUsage = mem.usagePercent
            self.memoryUsedBytes = mem.usedBytes
            self.onTitleUpdate?(self.cpuUsage, self.memoryUsage)
        }
    }

    deinit {
        timer?.cancel()
    }
}
