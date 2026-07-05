import Foundation

final class MetricsCollector {
    var cpuUsage: Double = -1
    var memoryUsage: Double = 0
    var pressure: MemoryPressureState = .normal

    var onUpdate: (() -> Void)?

    private let cpu = CPUMetrics()
    private let memory = MemoryMetrics()
    private let pressureMonitor = MemoryPressureMonitor()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.eli.Vitals.collector", qos: .utility)

    var hasCPUSample: Bool { cpuUsage >= 0 }

    func start() {
        pressureMonitor.start { [weak self] state in
            guard let self else { return }
            self.pressure = state
            DispatchQueue.main.async {
                self.onUpdate?()
            }
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 5.0)
        t.setEventHandler { [weak self] in
            autoreleasepool {
                self?.tick()
            }
        }
        t.resume()
        timer = t
    }

    func sampleOnce() {
        queue.async { [weak self] in
            autoreleasepool {
                self?.tick()
            }
        }
    }

    private func tick() {
        let cpuVal = cpu.sample()
        let memPercent = memory.sample()
        let reconciledPressure = pressureMonitor.currentLevel()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !cpuVal.isNaN {
                self.cpuUsage = cpuVal
            }
            self.memoryUsage = memPercent
            if reconciledPressure != self.pressure {
                self.pressure = reconciledPressure
            }
            self.onUpdate?()
        }
    }

    deinit {
        timer?.cancel()
    }
}
