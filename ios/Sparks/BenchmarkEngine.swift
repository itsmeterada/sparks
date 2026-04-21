import Foundation
import UIKit

// Default durations (seconds). Must be kept in sync with the Android
// implementation in android/app/src/main/cpp/benchmark_engine.* so that
// results are comparable across platforms.
enum BenchmarkTiming {
    static let warmupSec: Double = 3.0
    static let measureSec: Double = 10.0
    static let cooldownSec: Double = 2.0
}

struct ShaderBenchResult: Codable {
    let index: Int
    let name: String
    let avgFps: Double
    let onePctLowFps: Double
    let medianFrameMs: Double
    let p99FrameMs: Double
    let frames: Int
    let droppedFrames: Int
    let skipped: Bool
}

struct BenchmarkReport: Codable {
    struct DeviceInfo: Codable {
        let os: String
        let model: String
        let gpu: String
    }
    struct BenchConfig: Codable {
        let resolution: [Int]
        let halfRes: Bool
        let vsync: Bool
        let warmupSec: Double
        let measureSec: Double
        let cooldownSec: Double
    }
    let version: Int
    let timestamp: String
    let device: DeviceInfo
    let config: BenchConfig
    let thermalStateStart: String
    let thermalStateEnd: String
    let shaders: [ShaderBenchResult]
    let overallScore: Double
}

enum BenchmarkMode {
    case singleShader(Int)
    case allShaders
}

enum BenchmarkPhase {
    case idle, warmup, measure, cooldown, done
}

final class BenchmarkEngine {

    private(set) var phase: BenchmarkPhase = .idle
    private(set) var results: [ShaderBenchResult] = []

    private var shaderNames: [String] = []
    private var shaderQueue: [Int] = []
    private var queuePosition: Int = 0
    private var phaseStartTime: CFAbsoluteTime = 0
    private var lastFrameTime: CFAbsoluteTime = 0
    private var frameTimes: [Double] = []
    private var thermalStart: ProcessInfo.ThermalState = .nominal
    private var startedAt: Date = Date()

    var isRunning: Bool { phase != .idle && phase != .done }
    var isDone: Bool { phase == .done }

    var totalShadersInRun: Int { shaderQueue.count }
    var currentPositionOneBased: Int { min(queuePosition + 1, shaderQueue.count) }

    var activeShaderIndex: Int? {
        guard isRunning, queuePosition < shaderQueue.count else { return nil }
        return shaderQueue[queuePosition]
    }

    func start(mode: BenchmarkMode,
               shaderNames: [String],
               pipelineAvailable: (Int) -> Bool) {
        self.shaderNames = shaderNames
        self.results = []
        self.thermalStart = ProcessInfo.processInfo.thermalState
        self.startedAt = Date()

        var queue: [Int] = []
        switch mode {
        case .singleShader(let idx):
            if idx >= 0 && idx < shaderNames.count && pipelineAvailable(idx) {
                queue = [idx]
            }
        case .allShaders:
            queue = (0..<shaderNames.count).filter { pipelineAvailable($0) }
        }
        shaderQueue = queue
        queuePosition = 0
        frameTimes = []

        if queue.isEmpty {
            phase = .done
            return
        }
        phase = .warmup
        phaseStartTime = CFAbsoluteTimeGetCurrent()
    }

    func abort() {
        phase = .idle
        results = []
        shaderQueue = []
        queuePosition = 0
        frameTimes = []
    }

    /// Records frame time (present-to-present) during measure phase.
    /// Call at the start of each draw, before advancePhase.
    func recordPresentTime(now: CFAbsoluteTime) {
        guard phase == .measure else { return }
        let dt = now - lastFrameTime
        lastFrameTime = now
        // Sanity filter: drop absurd gaps (paused / backgrounded).
        if dt > 0 && dt < 1.0 {
            frameTimes.append(dt)
        }
    }

    /// Advances the state machine based on wall-clock elapsed time.
    /// Call each frame after recordPresentTime.
    func advancePhase(now: CFAbsoluteTime) {
        guard isRunning else { return }
        let elapsed = now - phaseStartTime
        switch phase {
        case .warmup:
            if elapsed >= BenchmarkTiming.warmupSec {
                phase = .measure
                phaseStartTime = now
                lastFrameTime = now
                frameTimes = []
            }
        case .measure:
            if elapsed >= BenchmarkTiming.measureSec {
                let idx = shaderQueue[queuePosition]
                results.append(makeResult(index: idx, frameTimes: frameTimes, skipped: false))
                phase = .cooldown
                phaseStartTime = now
            }
        case .cooldown:
            if elapsed >= BenchmarkTiming.cooldownSec {
                queuePosition += 1
                if queuePosition >= shaderQueue.count {
                    phase = .done
                } else {
                    phase = .warmup
                    phaseStartTime = now
                    frameTimes = []
                }
            }
        default:
            break
        }
    }

    var statusText: String {
        guard isRunning else { return "" }
        let total = shaderQueue.count
        let pos = currentPositionOneBased
        let name = currentShaderName()
        let phaseName: String
        let remaining: Double
        let elapsed = CFAbsoluteTimeGetCurrent() - phaseStartTime
        switch phase {
        case .warmup:
            phaseName = "warmup"
            remaining = max(0, BenchmarkTiming.warmupSec - elapsed)
        case .measure:
            phaseName = "measure"
            remaining = max(0, BenchmarkTiming.measureSec - elapsed)
        case .cooldown:
            phaseName = "cooldown"
            remaining = max(0, BenchmarkTiming.cooldownSec - elapsed)
        default:
            phaseName = ""
            remaining = 0
        }
        return String(format: "Bench %d/%d  %@  %@ %.1fs", pos, total, name, phaseName, remaining)
    }

    func currentShaderName() -> String {
        guard queuePosition < shaderQueue.count else { return "" }
        let idx = shaderQueue[queuePosition]
        return idx < shaderNames.count ? shaderNames[idx] : "?"
    }

    private func makeResult(index: Int, frameTimes: [Double], skipped: Bool) -> ShaderBenchResult {
        let name = index < shaderNames.count ? shaderNames[index] : "?"
        let count = frameTimes.count
        if skipped || count == 0 {
            return ShaderBenchResult(index: index, name: name,
                                     avgFps: 0, onePctLowFps: 0,
                                     medianFrameMs: 0, p99FrameMs: 0,
                                     frames: 0, droppedFrames: 0, skipped: skipped)
        }
        let totalTime = frameTimes.reduce(0, +)
        let avgFps = Double(count) / totalTime
        let sorted = frameTimes.sorted()
        let median = sorted[count / 2]
        let p99Idx = min(count - 1, Int((Double(count) * 0.99).rounded(.down)))
        let p99 = sorted[p99Idx]
        // 1% low FPS: mean of the slowest 1% of frames, inverted.
        let lowCount = max(1, count / 100)
        let lowSlice = sorted.suffix(lowCount)
        let lowAvg = lowSlice.reduce(0, +) / Double(lowCount)
        let onePctLowFps = lowAvg > 0 ? 1.0 / lowAvg : 0
        let droppedThreshold = median * 2.0
        let dropped = frameTimes.reduce(0) { $0 + ($1 > droppedThreshold ? 1 : 0) }
        return ShaderBenchResult(index: index, name: name,
                                 avgFps: avgFps,
                                 onePctLowFps: onePctLowFps,
                                 medianFrameMs: median * 1000.0,
                                 p99FrameMs: p99 * 1000.0,
                                 frames: count,
                                 droppedFrames: dropped,
                                 skipped: false)
    }

    /// Harmonic mean of avgFps × 100 across valid (non-skipped) results.
    func overallScore() -> Double {
        let valid = results.filter { !$0.skipped && $0.avgFps > 0 }
        if valid.isEmpty { return 0 }
        let sumReciprocal = valid.reduce(0.0) { $0 + 1.0 / $1.avgFps }
        return Double(valid.count) / sumReciprocal * 100.0
    }

    func makeReport(resolution: (Int, Int), halfRes: Bool, vsync: Bool, gpuName: String) -> BenchmarkReport {
        let fmt = ISO8601DateFormatter()
        let device = UIDevice.current
        return BenchmarkReport(
            version: 1,
            timestamp: fmt.string(from: startedAt),
            device: .init(os: "\(device.systemName) \(device.systemVersion)",
                          model: Self.modelIdentifier(),
                          gpu: gpuName),
            config: .init(resolution: [resolution.0, resolution.1],
                          halfRes: halfRes,
                          vsync: vsync,
                          warmupSec: BenchmarkTiming.warmupSec,
                          measureSec: BenchmarkTiming.measureSec,
                          cooldownSec: BenchmarkTiming.cooldownSec),
            thermalStateStart: Self.thermalString(thermalStart),
            thermalStateEnd: Self.thermalString(ProcessInfo.processInfo.thermalState),
            shaders: results,
            overallScore: overallScore()
        )
    }

    private static func thermalString(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func modelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        var id = ""
        for child in mirror.children {
            if let v = child.value as? Int8, v != 0 {
                id.append(Character(UnicodeScalar(UInt8(v))))
            }
        }
        return id
    }
}
