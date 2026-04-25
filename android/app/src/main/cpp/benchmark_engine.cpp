#include "benchmark_engine.h"

#include <algorithm>
#include <cstdio>
#include <sstream>

namespace bench {

static std::string escapeJson(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 2);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
    return out;
}

void BenchmarkEngine::start(Mode mode,
                            const std::vector<std::string>& shaderNames,
                            const PipelineAvailable& pipelineAvailable) {
    std::lock_guard<std::mutex> lock(mMutex);
    mNames = shaderNames;
    mResults.clear();
    mFrameTimes.clear();
    mQueue.clear();
    mQueuePos = 0;

    if (mode.kind == Mode::Single) {
        int idx = mode.singleIndex;
        if (idx >= 0 && idx < (int)shaderNames.size() && pipelineAvailable(idx)) {
            mQueue.push_back(idx);
        }
    } else {
        for (int i = 0; i < (int)shaderNames.size(); ++i) {
            if (pipelineAvailable(i)) mQueue.push_back(i);
        }
    }

    if (mQueue.empty()) {
        mPhase = Phase::Done;
        return;
    }
    mPhase = Phase::Warmup;
    mPhaseStart = Clock::now();
}

void BenchmarkEngine::abort() {
    std::lock_guard<std::mutex> lock(mMutex);
    mPhase = Phase::Idle;
    mResults.clear();
    mQueue.clear();
    mQueuePos = 0;
    mFrameTimes.clear();
}

bool BenchmarkEngine::isRunning() const {
    std::lock_guard<std::mutex> lock(mMutex);
    return mPhase != Phase::Idle && mPhase != Phase::Done;
}

bool BenchmarkEngine::isDone() const {
    std::lock_guard<std::mutex> lock(mMutex);
    return mPhase == Phase::Done;
}

void BenchmarkEngine::recordPresent(TimePoint now) {
    std::lock_guard<std::mutex> lock(mMutex);
    if (mPhase != Phase::Measure) return;
    double dt = std::chrono::duration<double>(now - mLastFrame).count();
    mLastFrame = now;
    if (dt > 0.0 && dt < 1.0) {
        mFrameTimes.push_back(dt);
    }
}

void BenchmarkEngine::advancePhase(TimePoint now) {
    std::lock_guard<std::mutex> lock(mMutex);
    if (mPhase == Phase::Idle || mPhase == Phase::Done) return;
    double elapsed = std::chrono::duration<double>(now - mPhaseStart).count();
    switch (mPhase) {
        case Phase::Warmup:
            if (elapsed >= kWarmupSec) {
                mPhase = Phase::Measure;
                mPhaseStart = now;
                mLastFrame = now;
                mFrameTimes.clear();
            }
            break;
        case Phase::Measure:
            if (elapsed >= kMeasureSec) {
                int idx = mQueue[mQueuePos];
                mResults.push_back(makeResultLocked(idx, mFrameTimes, false));
                mPhase = Phase::Cooldown;
                mPhaseStart = now;
            }
            break;
        case Phase::Cooldown:
            if (elapsed >= kCooldownSec) {
                mQueuePos++;
                if (mQueuePos >= (int)mQueue.size()) {
                    mPhase = Phase::Done;
                } else {
                    mPhase = Phase::Warmup;
                    mPhaseStart = now;
                    mFrameTimes.clear();
                }
            }
            break;
        default: break;
    }
}

int BenchmarkEngine::activeShaderIndex() const {
    std::lock_guard<std::mutex> lock(mMutex);
    if (mPhase == Phase::Idle || mPhase == Phase::Done) return -1;
    if (mQueuePos >= (int)mQueue.size()) return -1;
    return mQueue[mQueuePos];
}

std::string BenchmarkEngine::statusText() const {
    std::lock_guard<std::mutex> lock(mMutex);
    if (mPhase == Phase::Idle || mPhase == Phase::Done) return "";
    int total = (int)mQueue.size();
    int pos = std::min(mQueuePos + 1, total);
    const std::string& name = (mQueuePos < (int)mQueue.size() && mQueue[mQueuePos] < (int)mNames.size())
                              ? mNames[mQueue[mQueuePos]] : std::string("?");
    const char* phaseName = "";
    double dur = 0;
    switch (mPhase) {
        case Phase::Warmup: phaseName = "warmup"; dur = kWarmupSec; break;
        case Phase::Measure: phaseName = "measure"; dur = kMeasureSec; break;
        case Phase::Cooldown: phaseName = "cooldown"; dur = kCooldownSec; break;
        default: break;
    }
    double elapsed = std::chrono::duration<double>(Clock::now() - mPhaseStart).count();
    double remaining = std::max(0.0, dur - elapsed);
    char buf[160];
    std::snprintf(buf, sizeof(buf), "Bench %d/%d  %s  %s %.1fs",
                  pos, total, name.c_str(), phaseName, remaining);
    return std::string(buf);
}

ShaderResult BenchmarkEngine::makeResultLocked(int idx, const std::vector<double>& times, bool skipped) const {
    ShaderResult r{};
    r.index = idx;
    r.name = idx < (int)mNames.size() ? mNames[idx] : "?";
    int count = (int)times.size();
    if (skipped || count == 0) {
        r.skipped = skipped;
        return r;
    }
    double total = 0;
    for (double t : times) total += t;
    r.avgFps = (double)count / total;
    std::vector<double> sorted = times;
    std::sort(sorted.begin(), sorted.end());
    r.medianFrameMs = sorted[count / 2] * 1000.0;
    int p99idx = std::min(count - 1, (int)(count * 0.99));
    r.p99FrameMs = sorted[p99idx] * 1000.0;
    int lowCount = std::max(1, count / 100);
    double lowSum = 0;
    for (int i = count - lowCount; i < count; ++i) lowSum += sorted[i];
    double lowAvg = lowSum / lowCount;
    r.onePctLowFps = lowAvg > 0 ? 1.0 / lowAvg : 0;
    double dropT = sorted[count / 2] * 2.0;
    int dropped = 0;
    for (double t : times) if (t > dropT) dropped++;
    r.droppedFrames = dropped;
    r.frames = count;
    r.skipped = false;
    return r;
}

double BenchmarkEngine::overallScore(int resW, int resH, bool halfRes) const {
    std::lock_guard<std::mutex> lock(mMutex);
    double sumR = 0;
    int n = 0;
    for (const auto& s : mResults) {
        if (!s.skipped && s.avgFps > 0) {
            sumR += 1.0 / s.avgFps;
            n++;
        }
    }
    if (n == 0) return 0;
    double harmonicMean = (double)n / sumR;
    double pixels = (double)resW * (double)resH * (halfRes ? 0.25 : 1.0);
    constexpr double kReferencePixels = 1920.0 * 1080.0;
    return harmonicMean * 100.0 * pixels / kReferencePixels;
}

std::string BenchmarkEngine::reportJson(int resW, int resH, bool halfRes, bool vsync,
                                        const std::string& gpuName,
                                        const std::string& osVersion,
                                        const std::string& model,
                                        const std::string& thermalStart,
                                        const std::string& thermalEnd,
                                        const std::string& timestamp) const {
    std::lock_guard<std::mutex> lock(mMutex);
    std::ostringstream ss;
    ss.precision(6);
    ss << "{\n";
    ss << "  \"version\": 1,\n";
    ss << "  \"timestamp\": \"" << escapeJson(timestamp) << "\",\n";
    ss << "  \"device\": {\n";
    ss << "    \"os\": \"" << escapeJson(osVersion) << "\",\n";
    ss << "    \"model\": \"" << escapeJson(model) << "\",\n";
    ss << "    \"gpu\": \"" << escapeJson(gpuName) << "\"\n";
    ss << "  },\n";
    ss << "  \"config\": {\n";
    ss << "    \"resolution\": [" << resW << ", " << resH << "],\n";
    ss << "    \"halfRes\": " << (halfRes ? "true" : "false") << ",\n";
    ss << "    \"vsync\": " << (vsync ? "true" : "false") << ",\n";
    ss << "    \"warmupSec\": " << kWarmupSec << ",\n";
    ss << "    \"measureSec\": " << kMeasureSec << ",\n";
    ss << "    \"cooldownSec\": " << kCooldownSec << "\n";
    ss << "  },\n";
    ss << "  \"thermalStateStart\": \"" << escapeJson(thermalStart) << "\",\n";
    ss << "  \"thermalStateEnd\": \"" << escapeJson(thermalEnd) << "\",\n";
    ss << "  \"shaders\": [\n";
    for (size_t i = 0; i < mResults.size(); ++i) {
        const auto& s = mResults[i];
        ss << "    {\n";
        ss << "      \"index\": " << s.index << ",\n";
        ss << "      \"name\": \"" << escapeJson(s.name) << "\",\n";
        ss << "      \"avgFps\": " << s.avgFps << ",\n";
        ss << "      \"onePctLowFps\": " << s.onePctLowFps << ",\n";
        ss << "      \"medianFrameMs\": " << s.medianFrameMs << ",\n";
        ss << "      \"p99FrameMs\": " << s.p99FrameMs << ",\n";
        ss << "      \"frames\": " << s.frames << ",\n";
        ss << "      \"droppedFrames\": " << s.droppedFrames << ",\n";
        ss << "      \"skipped\": " << (s.skipped ? "true" : "false") << "\n";
        ss << "    }";
        if (i + 1 < mResults.size()) ss << ",";
        ss << "\n";
    }
    ss << "  ],\n";
    // overallScore: compute inline to avoid recursive lock.
    // effectivePx = resW × resH × (halfRes ? 0.25 : 1.0)
    // score = harmonicMean(avgFps) × 100 × effectivePx / (1920 × 1080)
    double sumR = 0;
    int n = 0;
    for (const auto& s : mResults) {
        if (!s.skipped && s.avgFps > 0) { sumR += 1.0 / s.avgFps; n++; }
    }
    double score = 0;
    if (n > 0) {
        double harmonicMean = (double)n / sumR;
        double pixels = (double)resW * (double)resH * (halfRes ? 0.25 : 1.0);
        constexpr double kReferencePixels = 1920.0 * 1080.0;
        score = harmonicMean * 100.0 * pixels / kReferencePixels;
    }
    ss << "  \"overallScore\": " << score << "\n";
    ss << "}\n";
    return ss.str();
}

} // namespace bench
