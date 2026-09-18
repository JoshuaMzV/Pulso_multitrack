#include "pulso_engine.h"
#include "pulso_mixer_simd.h"
#include "lock_free_queue.h"

#include <vector>
#include <string>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <atomic>

namespace PulsoAudio {

enum class CommandType {
    Play,
    Pause,
    Stop,
    SetBpm,
    JumpToBar,
    JumpToSection,
    SetPitch,
    SetChannelGain,
    SetChannelMute,
    SetChannelSolo,
    SetChannelBus,
    SetMasterGain,
    SetClickEnabled,
    SetClickVolume,
    StartAmbientPad,
    StopAmbientPad
};

struct EngineCommand {
    CommandType type;
    int32_t intArg1;
    int32_t intArg2;
    float floatArg1;
    float floatArg2;
    bool boolArg1;
};

// Internal Stem Data Buffer
struct ChannelTrack {
    std::string name;
    std::vector<float> audioData;
    float currentGain = 0.8f;
    float targetGain = 0.8f;
    float pan = 0.0f;
    bool muted = false;
    bool solo = false;
    PulsoBusType bus = PULSO_BUS_MASTER;
    float currentRms = 0.0f;
};

class EngineImpl {
public:
    EngineImpl(uint32_t sampleRate, uint32_t bufferSize)
        : sampleRate_(sampleRate), bufferSize_(bufferSize) {
        channels_.resize(PULSO_MAX_CHANNELS);
        tempMixBuffer_.resize(bufferSize);
        padBuffer_.resize(bufferSize);
        clickBuffer_.resize(bufferSize);

        // Precompute frequencies for 12 chromatic pad keys (C3 to B3)
        // C3 = ~130.81 Hz
        for (int i = 0; i < 12; ++i) {
            padFrequencies_[i] = 130.8128f * std::pow(2.0f, static_cast<float>(i) / 12.0f);
        }
    }

    void pushCommand(const EngineCommand& cmd) {
        commandQueue_.push(cmd);
    }

    void render(float* masterL, float* masterR, float* cueL, float* cueR, uint32_t numFrames) {
        processCommands();

        // Clear output buffers
        std::memset(masterL, 0, numFrames * sizeof(float));
        std::memset(masterR, 0, numFrames * sizeof(float));
        std::memset(cueL, 0, numFrames * sizeof(float));
        std::memset(cueR, 0, numFrames * sizeof(float));

        if (!isPlaying_.load(std::memory_order_relaxed)) {
            // Render ambient pad even when transport is stopped (stage atmosphere)
            renderAmbientPad(masterL, masterR, numFrames);
            updateTelemetry(masterL, masterR, numFrames);
            return;
        }

        const bool hasSolo = std::any_of(channels_.begin(), channels_.end(), [](const ChannelTrack& ch) {
            return ch.solo;
        });

        // 1. Process and mix multitrack stems
        for (size_t ch = 0; ch < channels_.size(); ++ch) {
            auto& track = channels_[ch];
            if (track.audioData.empty()) continue;

            float effectiveGain = track.targetGain;
            if (track.muted || (hasSolo && !track.solo)) {
                effectiveGain = 0.0f;
            }

            if (effectiveGain > 0.0001f) {
                // Clear temp buffer
                std::memset(tempMixBuffer_.data(), 0, numFrames * sizeof(float));

                // Fetch samples from channel audio data
                for (uint32_t i = 0; i < numFrames; ++i) {
                    size_t sampleIdx = currentFrameIndex_ + i;
                    if (sampleIdx < track.audioData.size()) {
                        tempMixBuffer_[i] = track.audioData[sampleIdx];
                    }
                }

                // Vectorized mix into Master or Cue bus
                if (track.bus == PULSO_BUS_MASTER) {
                    SimdMixer::mixChannel(masterL, tempMixBuffer_.data(), effectiveGain, numFrames);
                    SimdMixer::mixChannel(masterR, tempMixBuffer_.data(), effectiveGain, numFrames);
                } else {
                    SimdMixer::mixChannel(cueL, tempMixBuffer_.data(), effectiveGain, numFrames);
                    SimdMixer::mixChannel(cueR, tempMixBuffer_.data(), effectiveGain, numFrames);
                }

                track.currentRms = SimdMixer::calculateRms(tempMixBuffer_.data(), numFrames) * effectiveGain;
            } else {
                track.currentRms = 0.0f;
            }
        }

        // 2. Synthesize Click and route directly to Cue Bus (In-Ear Monitors)
        if (clickEnabled_.load(std::memory_order_relaxed)) {
            renderClick(cueL, cueR, numFrames);
        }

        // 3. Render Ambient Pad
        renderAmbientPad(masterL, masterR, numFrames);

        // 4. Advance Transport Playhead
        currentFrameIndex_ += numFrames;
        updateTimeSignature(numFrames);

        // 5. Apply Soft Limiter to avoid digital clipping
        SimdMixer::applySoftLimiter(masterL, numFrames);
        SimdMixer::applySoftLimiter(masterR, numFrames);
        SimdMixer::applySoftLimiter(cueL, numFrames);
        SimdMixer::applySoftLimiter(cueR, numFrames);

        updateTelemetry(masterL, masterR, numFrames);
    }

    void getState(PulsoPlaybackState* state) const {
        state->currentBar = currentBar_;
        state->currentBeat = currentBeat_;
        state->currentSixteenth = currentSixteenth_;
        state->positionSeconds = static_cast<float>(currentFrameIndex_) / static_cast<float>(sampleRate_);
        state->bpm = bpm_;
        state->isPlaying = isPlaying_.load(std::memory_order_relaxed);
        state->activeSectionIndex = activeSectionIndex_;
        state->masterRmsL = masterRmsL_;
        state->masterRmsR = masterRmsR_;

        for (size_t i = 0; i < PULSO_MAX_CHANNELS && i < channels_.size(); ++i) {
            state->channelRms[i] = channels_[i].currentRms;
        }
    }

private:
    void processCommands() {
        EngineCommand cmd;
        while (commandQueue_.pop(cmd)) {
            switch (cmd.type) {
                case CommandType::Play:
                    isPlaying_.store(true, std::memory_order_relaxed);
                    break;
                case CommandType::Pause:
                    isPlaying_.store(false, std::memory_order_relaxed);
                    break;
                case CommandType::Stop:
                    isPlaying_.store(false, std::memory_order_relaxed);
                    currentFrameIndex_ = 0;
                    currentBar_ = 0;
                    currentBeat_ = 0;
                    currentSixteenth_ = 0;
                    break;
                case CommandType::SetBpm:
                    bpm_ = std::clamp(cmd.floatArg1, 40.0f, 240.0f);
                    break;
                case CommandType::JumpToBar: {
                    int32_t bar = cmd.intArg1;
                    float secondsPerBar = (60.0f / bpm_) * 4.0f;
                    currentFrameIndex_ = static_cast<size_t>(bar * secondsPerBar * sampleRate_);
                    currentBar_ = bar;
                    break;
                }
                case CommandType::SetChannelGain:
                    if (cmd.intArg1 >= 0 && cmd.intArg1 < static_cast<int32_t>(channels_.size())) {
                        channels_[cmd.intArg1].targetGain = cmd.floatArg1;
                    }
                    break;
                case CommandType::SetChannelMute:
                    if (cmd.intArg1 >= 0 && cmd.intArg1 < static_cast<int32_t>(channels_.size())) {
                        channels_[cmd.intArg1].muted = cmd.boolArg1;
                    }
                    break;
                case CommandType::SetChannelSolo:
                    if (cmd.intArg1 >= 0 && cmd.intArg1 < static_cast<int32_t>(channels_.size())) {
                        channels_[cmd.intArg1].solo = cmd.boolArg1;
                    }
                    break;
                case CommandType::SetChannelBus:
                    if (cmd.intArg1 >= 0 && cmd.intArg1 < static_cast<int32_t>(channels_.size())) {
                        channels_[cmd.intArg1].bus = static_cast<PulsoBusType>(cmd.intArg2);
                    }
                    break;
                case CommandType::SetClickEnabled:
                    clickEnabled_.store(cmd.boolArg1, std::memory_order_relaxed);
                    break;
                case CommandType::SetClickVolume:
                    clickVolume_ = cmd.floatArg1;
                    break;
                case CommandType::StartAmbientPad:
                    activePadKey_ = cmd.intArg1;
                    padTargetVolume_ = cmd.floatArg1;
                    padActive_ = true;
                    break;
                case CommandType::StopAmbientPad:
                    padTargetVolume_ = 0.0f;
                    break;
                default:
                    break;
            }
        }
    }

    void renderClick(float* cueL, float* cueR, uint32_t numFrames) {
        float samplesPerBeat = (60.0f / bpm_) * static_cast<float>(sampleRate_);
        for (uint32_t i = 0; i < numFrames; ++i) {
            size_t totalFrame = currentFrameIndex_ + i;
            size_t frameInBeat = totalFrame % static_cast<size_t>(samplesPerBeat);
            int32_t beatNumber = (totalFrame / static_cast<size_t>(samplesPerBeat)) % 4;

            // Generate crisp synthesized click envelope
            if (frameInBeat < static_cast<size_t>(sampleRate_ * 0.025f)) { // 25ms pulse
                float clickFreq = (beatNumber == 0) ? 1760.0f : 1100.0f; // Accent on 1 (A6 vs C#6)
                float t = static_cast<float>(frameInBeat) / static_cast<float>(sampleRate_);
                float env = std::exp(-t * 220.0f); // Exponential decay
                float sample = std::sin(2.0f * 3.14159265f * clickFreq * t) * env * clickVolume_;

                cueL[i] += sample;
                cueR[i] += sample;
            }
        }
    }

    void renderAmbientPad(float* outL, float* outR, uint32_t numFrames) {
        if (!padActive_ && padCurrentVolume_ < 0.0001f) return;

        // Smooth volume slew rate
        padCurrentVolume_ += (padTargetVolume_ - padCurrentVolume_) * 0.005f;
        if (padCurrentVolume_ < 0.0001f && padTargetVolume_ <= 0.0001f) {
            padActive_ = false;
            return;
        }

        if (activePadKey_ < 0 || activePadKey_ >= 12) return;
        float baseFreq = padFrequencies_[activePadKey_];

        // Multi-oscillator detuned warm pad synthesis (Fundamental + 5th + Octave)
        for (uint32_t i = 0; i < numFrames; ++i) {
            padPhase1_ += 2.0f * 3.14159265f * baseFreq / static_cast<float>(sampleRate_);
            padPhase2_ += 2.0f * 3.14159265f * (baseFreq * 1.003f) / static_cast<float>(sampleRate_); // +3 cents
            padPhase3_ += 2.0f * 3.14159265f * (baseFreq * 1.498f) / static_cast<float>(sampleRate_); // Perfect 5th

            if (padPhase1_ > 2.0f * 3.14159265f) padPhase1_ -= 2.0f * 3.14159265f;
            if (padPhase2_ > 2.0f * 3.14159265f) padPhase2_ -= 2.0f * 3.14159265f;
            if (padPhase3_ > 2.0f * 3.14159265f) padPhase3_ -= 2.0f * 3.14159265f;

            float padSample = (std::sin(padPhase1_) * 0.45f +
                               std::sin(padPhase2_) * 0.35f +
                               std::sin(padPhase3_) * 0.20f) * padCurrentVolume_ * 0.25f;

            outL[i] += padSample;
            outR[i] += padSample;
        }
    }

    void updateTimeSignature(uint32_t numFrames) {
        float secondsPerBeat = 60.0f / bpm_;
        float secondsPerBar = secondsPerBeat * 4.0f; // Assuming 4/4
        float currentSeconds = static_cast<float>(currentFrameIndex_) / static_cast<float>(sampleRate_);

        currentBar_ = static_cast<int32_t>(currentSeconds / secondsPerBar);
        float secondInBar = currentSeconds - (currentBar_ * secondsPerBar);
        currentBeat_ = static_cast<int32_t>(secondInBar / secondsPerBeat);
        currentSixteenth_ = static_cast<int32_t>((secondInBar / secondsPerBeat) * 4.0f) % 16;
    }

    void updateTelemetry(const float* masterL, const float* masterR, uint32_t numFrames) {
        masterRmsL_ = SimdMixer::calculateRms(masterL, numFrames);
        masterRmsR_ = SimdMixer::calculateRms(masterR, numFrames);
    }

    uint32_t sampleRate_ = 48000;
    uint32_t bufferSize_ = 512;
    std::atomic<bool> isPlaying_{false};
    float bpm_ = 120.0f;
    size_t currentFrameIndex_ = 0;

    int32_t currentBar_ = 0;
    int32_t currentBeat_ = 0;
    int32_t currentSixteenth_ = 0;
    int32_t activeSectionIndex_ = 0;

    std::atomic<bool> clickEnabled_{true};
    float clickVolume_ = 0.8f;

    bool padActive_ = false;
    int32_t activePadKey_ = 0; // 0 = C
    float padTargetVolume_ = 0.0f;
    float padCurrentVolume_ = 0.0f;
    float padPhase1_ = 0.0f;
    float padPhase2_ = 0.0f;
    float padPhase3_ = 0.0f;
    float padFrequencies_[12];

    float masterRmsL_ = 0.0f;
    float masterRmsR_ = 0.0f;

    std::vector<ChannelTrack> channels_;
    std::vector<float> tempMixBuffer_;
    std::vector<float> padBuffer_;
    std::vector<float> clickBuffer_;

    LockFreeQueue<EngineCommand, 256> commandQueue_;
};

} // namespace PulsoAudio

// C-ABI Implementations
extern "C" {

PULSO_API void* pulso_create_engine(uint32_t sampleRate, uint32_t bufferSize) {
    return new PulsoAudio::EngineImpl(sampleRate, bufferSize);
}

PULSO_API void pulso_destroy_engine(void* engine) {
    if (engine) {
        delete static_cast<PulsoAudio::EngineImpl*>(engine);
    }
}

PULSO_API void pulso_play(void* engine) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::Play;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_pause(void* engine) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::Pause;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_stop(void* engine) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::Stop;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_bpm(void* engine, float bpm) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetBpm;
    cmd.floatArg1 = bpm;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_jump_to_bar(void* engine, int32_t targetBar, bool quantizeToNextBar) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::JumpToBar;
    cmd.intArg1 = targetBar;
    cmd.boolArg1 = quantizeToNextBar;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_channel_gain(void* engine, int32_t channelIndex, float gain) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetChannelGain;
    cmd.intArg1 = channelIndex;
    cmd.floatArg1 = gain;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_channel_mute(void* engine, int32_t channelIndex, bool muted) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetChannelMute;
    cmd.intArg1 = channelIndex;
    cmd.boolArg1 = muted;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_channel_solo(void* engine, int32_t channelIndex, bool solo) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetChannelSolo;
    cmd.intArg1 = channelIndex;
    cmd.boolArg1 = solo;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_channel_bus(void* engine, int32_t channelIndex, PulsoBusType bus) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetChannelBus;
    cmd.intArg1 = channelIndex;
    cmd.intArg2 = static_cast<int32_t>(bus);
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_click_enabled(void* engine, bool enabled) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetClickEnabled;
    cmd.boolArg1 = enabled;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_set_click_volume(void* engine, float volume) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::SetClickVolume;
    cmd.floatArg1 = volume;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_start_ambient_pad(void* engine, int32_t keyIndex, float volume) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::StartAmbientPad;
    cmd.intArg1 = keyIndex;
    cmd.floatArg1 = volume;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_stop_ambient_pad(void* engine, float fadeOutSeconds) {
    if (!engine) return;
    PulsoAudio::EngineCommand cmd;
    cmd.type = PulsoAudio::CommandType::StopAmbientPad;
    cmd.floatArg1 = fadeOutSeconds;
    static_cast<PulsoAudio::EngineImpl*>(engine)->pushCommand(cmd);
}

PULSO_API void pulso_get_state(void* engine, PulsoPlaybackState* outState) {
    if (!engine || !outState) return;
    static_cast<PulsoAudio::EngineImpl*>(engine)->getState(outState);
}

PULSO_API void pulso_render_audio(void* engine, float* masterOutL, float* masterOutR, float* cueOutL, float* cueOutR, uint32_t numFrames) {
    if (!engine) return;
    static_cast<PulsoAudio::EngineImpl*>(engine)->render(masterOutL, masterOutR, cueOutL, cueOutR, numFrames);
}

} // extern "C"
