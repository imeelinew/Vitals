import Foundation
import Dispatch
import Darwin

enum MemoryPressureState: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "警告"
        case .critical: return "严重"
        }
    }
}

final class MemoryPressureMonitor {
    private var source: DispatchSourceMemoryPressure?
    private var handler: ((MemoryPressureState) -> Void)?

    func start(onChange: @escaping (MemoryPressureState) -> Void) {
        self.handler = onChange

        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let initial = MemoryPressureState(rawValue: Int(level)) ?? .normal
        onChange(initial)

        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            let data = src.data
            let state: MemoryPressureState
            if data.contains(.critical) {
                state = .critical
            } else if data.contains(.warning) {
                state = .warning
            } else {
                state = .normal
            }
            self?.handler?(state)
        }
        src.resume()
        self.source = src
    }

    deinit {
        source?.cancel()
    }
}
