import AppKit
import Dispatch
import Darwin

enum MemoryPressureState: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    var color: NSColor {
        switch self {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }
}

final class MemoryPressureMonitor {
    private var source: DispatchSourceMemoryPressure?

    func start(onChange: @escaping (MemoryPressureState) -> Void) {
        onChange(currentLevel())

        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .main
        )
        src.setEventHandler {
            let data = src.data
            let state: MemoryPressureState
            if data.contains(.critical) {
                state = .critical
            } else if data.contains(.warning) {
                state = .warning
            } else {
                state = .normal
            }
            onChange(state)
        }
        src.resume()
        self.source = src
    }

    func currentLevel() -> MemoryPressureState {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return MemoryPressureState(rawValue: Int(level)) ?? .normal
    }

    deinit {
        source?.cancel()
    }
}
