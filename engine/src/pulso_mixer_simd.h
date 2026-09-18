#ifndef PULSO_MIXER_SIMD_H
#define PULSO_MIXER_SIMD_H

#include <cstdint>
#include <cstddef>

namespace PulsoAudio {

class SimdMixer {
public:
    // Vectorized channel accumulation with constant gain:
    // destination[i] += source[i] * gain
    // Optimized with ARM NEON vld1q_f32 / vfmaq_f32 (or AVX/SSE on x86)
    static void mixChannel(float* __restrict dest, const float* __restrict src, float gain, size_t numFrames);

    // Vectorized channel accumulation with de-zippering gain ramp:
    // Interpolates smoothly from startGain to endGain over numFrames to prevent clicks/pops
    static void mixChannelRamped(float* __restrict dest, const float* __restrict src, float startGain, float endGain, size_t numFrames);

    // Vectorized soft-saturator / limiter:
    // Applies smooth polynomial tanh curve: y = x - (x^3)/3 when |x| < 1.0, clamped at [-1.0, 1.0]
    // Eliminates harsh digital overs when 30+ multitrack stems sum simultaneously
    static void applySoftLimiter(float* __restrict buffer, size_t numFrames);

    // Vectorized RMS (Root Mean Square) decibel meter calculation
    static float calculateRms(const float* __restrict buffer, size_t numFrames);
};

} // namespace PulsoAudio

#endif // PULSO_MIXER_SIMD_H
