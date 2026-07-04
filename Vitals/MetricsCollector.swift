import Foundation
import Observation

@Observable
final class MetricsCollector {
    var cpuUsage: Double = -1
    var memoryUsage: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var totalMemoryBytes: UInt64 = 0
    var pressure: MemoryPressureState = .normal
    var pressurePercent: Double = 0

    var onUpdate: (() -> Void)?

    private let cpu = CPUMetrics()
    private let memory = MemoryMetrics()
    private let pressureMonitor = MemoryPressureMonitor()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.eli.Vitals.collector", qos: .utility)

    var hasCPUSample: Bool { cpuUsage >= 0 }

    func start() {
        totalMemoryBytes = memory.totalBytes
        pressureMonitor.start { [weak self] state in
            guard let self else { return }
            self.pressure = state
            DispatchQueue.main.async {
                self.onUpdate?()
            }
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
        let reconciledPressure = pressureMonitor.currentLevel()
        let pressureLevel = Self.readPressureLevel()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !cpuVal.isNaN {
                self.cpuUsage = cpuVal
            }
            self.memoryUsage = mem.usagePercent
            self.memoryUsedBytes = mem.usedBytes
            if reconciledPressure != self.pressure {
                self.pressure = reconciledPressure
            }
            self.pressurePercent = pressureLevel
            self.onUpdate?()
        }
    }

    private static func readPressureLevel() -> Double {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_level", &value, &size, nil, 0)
        return max(0, min(100, Double(value)))
    }

    deinit {
        timer?.cancel()
    }
}
