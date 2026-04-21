#pragma once

#include <chrono>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace bench {

// Default durations (seconds). Must match ios/sparks/BenchmarkEngine.swift
// (BenchmarkTiming) so results are comparable across platforms.
inline constexpr double kWarmupSec = 3.0;
inline constexpr double kMeasureSec = 10.0;
inline constexpr double kCooldownSec = 2.0;

enum class Phase { Idle, Warmup, Measure, Cooldown, Done };

struct Mode {
    enum Kind { Single, All };
    Kind kind;
    int singleIndex; // used when kind == Single
};

struct ShaderResult {
    int index;
    std::string name;
    double avgFps;
    double onePctLowFps;
    double medianFrameMs;
    double p99FrameMs;
    int frames;
    int droppedFrames;
    bool skipped;
};

class BenchmarkEngine {
public:
    using Clock = std::chrono::high_resolution_clock;
    using TimePoint = Clock::time_point;
    using PipelineAvailable = std::function<bool(int)>;

    void start(Mode mode,
               const std::vector<std::string>& shaderNames,
               const PipelineAvailable& pipelineAvailable);

    void abort();

    bool isRunning() const;
    bool isDone() const;

    /// Record present-to-present time for the measure phase. Call at start of each render tick.
    void recordPresent(TimePoint now);

    /// Advance the state machine based on elapsed wall-clock time. Call after recordPresent.
    void advancePhase(TimePoint now);

    /// Current shader index to render, or -1 when not running.
    int activeShaderIndex() const;

    /// Progress text for UI overlay.
    std::string statusText() const;

    /// Harmonic mean of avgFps × 100 across valid (non-skipped) results.
    double overallScore() const;

    /// JSON report body. The caller supplies metadata (timestamp, thermal state, device info).
    std::string reportJson(int resW, int resH, bool halfRes, bool vsync,
                           const std::string& gpuName,
                           const std::string& osVersion,
                           const std::string& model,
                           const std::string& thermalStart,
                           const std::string& thermalEnd,
                           const std::string& timestamp) const;

private:
    ShaderResult makeResultLocked(int idx, const std::vector<double>& times, bool skipped) const;

    mutable std::mutex mMutex;
    Phase mPhase = Phase::Idle;
    std::vector<std::string> mNames;
    std::vector<int> mQueue;
    int mQueuePos = 0;
    TimePoint mPhaseStart{};
    TimePoint mLastFrame{};
    std::vector<double> mFrameTimes;
    std::vector<ShaderResult> mResults;
};

} // namespace bench
