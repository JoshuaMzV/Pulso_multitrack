#include "pulso_mixer_simd.h"
#include <cmath>
#include <algorithm>

#if defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(_M_ARM64)
    #include <arm_neon.h>
    #define PULSO_HAS_NEON 1
#elif defined(__SSE2__) || defined(_M_X64) || defined(_M_IX86)
    #include <immintrin.h>
    #define PULSO_HAS_SSE 1
#endif

namespace PulsoAudio {

void SimdMixer::mixChannel(float* __restrict dest, const float* __restrict src, float gain, size_t numFrames) {
    if (std::abs(gain) < 0.00001f) {
        return; // Gain is -inf dB / muted, skip processing
    }

    size_t i = 0;

#if defined(PULSO_HAS_NEON)
    // ARM NEON Vectorized Loop (Processes 4 32-bit float samples per cycle)
    // Assembly generated:
    //   dup   v2.4s, w0          // duplicate gain across all 4 lanes
    // .Lloop:
    //   ld1   {v0.4s}, [x1], #16 // load 4 source frames
    //   ld1   {v1.4s}, [x0]      // load 4 dest frames
    //   fmla  v1.4s, v0.4s, v2.4s// fused multiply-accumulate: dest += src * gain
    //   st1   {v1.4s}, [x0], #16 // store back to dest
    const float32x4_t vGain = vdupq_n_f32(gain);
    const size_t simdLimit = numFrames & ~3UL; // Multiples of 4

    for (; i < simdLimit; i += 4) {
        float32x4_t vSrc = vld1q_f32(src + i);
        float32x4_t vDest = vld1q_f32(dest + i);
        vDest = vfmaq_f32(vDest, vSrc, vGain);
        vst1q_f32(dest + i, vDest);
    }
#elif defined(PULSO_HAS_SSE)
    // x86/x64 SSE2 Fallback for Desktop Simulation
    const __m128 vGain = _mm_set1_ps(gain);
    const size_t simdLimit = numFrames & ~3UL;

    for (; i < simdLimit; i += 4) {
        __m128 vSrc = _mm_loadu_ps(src + i);
        __m128 vDest = _mm_loadu_ps(dest + i);
        vDest = _mm_add_ps(vDest, _mm_mul_ps(vSrc, vGain));
        _mm_storeu_ps(dest + i, vDest);
    }
#endif

    // Scalar remainder loop for leftover frames (< 4)
    for (; i < numFrames; ++i) {
        dest[i] += src[i] * gain;
    }
}

void SimdMixer::mixChannelRamped(float* __restrict dest, const float* __restrict src, float startGain, float endGain, size_t numFrames) {
    if (numFrames == 0) return;
    const float gainStep = (endGain - startGain) / static_cast<float>(numFrames);
    float currentGain = startGain;

    size_t i = 0;

#if defined(PULSO_HAS_NEON)
    // De-zippering gain ramping in NEON:
    // Precomputes the 4-lane increment vector: [0, step, 2*step, 3*step]
    const float32x4_t vStep4 = vdupq_n_f32(gainStep * 4.0f);
    float rampOffsets[4] = {0.0f, gainStep, gainStep * 2.0f, gainStep * 3.0f};
    const float32x4_t vRampOffsets = vld1q_f32(rampOffsets);

    const size_t simdLimit = numFrames & ~3UL;
    for (; i < simdLimit; i += 4) {
        float32x4_t vBaseGain = vdupq_n_f32(currentGain);
        float32x4_t vGain = vaddq_f32(vBaseGain, vRampOffsets);

        float32x4_t vSrc = vld1q_f32(src + i);
        float32x4_t vDest = vld1q_f32(dest + i);
        vDest = vfmaq_f32(vDest, vSrc, vGain);
        vst1q_f32(dest + i, vDest);

        currentGain += gainStep * 4.0f;
    }
#endif

    // Scalar loop
    for (; i < numFrames; ++i) {
        dest[i] += src[i] * currentGain;
        currentGain += gainStep;
    }
}

void SimdMixer::applySoftLimiter(float* __restrict buffer, size_t numFrames) {
    size_t i = 0;

#if defined(PULSO_HAS_NEON)
    const float32x4_t vOne = vdupq_n_f32(1.0f);
    const float32x4_t vNegOne = vdupq_n_f32(-1.0f);
    const float32x4_t vOneThird = vdupq_n_f32(1.0f / 3.0f);
    const size_t simdLimit = numFrames & ~3UL;

    for (; i < simdLimit; i += 4) {
        float32x4_t x = vld1q_f32(buffer + i);
        // Clamp to [-1.5, 1.5] before saturation
        x = vminnmq_f32(vmaxnmq_f32(x, vdupq_n_f32(-1.5f)), vdupq_n_f32(1.5f));

        // Cubic soft saturation: y = x - (x^3)/3
        float32x4_t x2 = vmulq_f32(x, x);
        float32x4_t x3 = vmulq_f32(x2, x);
        float32x4_t sat = vsubq_f32(x, vmulq_f32(x3, vOneThird));

        // Safety clamp strictly to [-1.0, 1.0]
        sat = vminnmq_f32(vmaxnmq_f32(sat, vNegOne), vOne);
        vst1q_f32(buffer + i, sat);
    }
#endif

    for (; i < numFrames; ++i) {
        float x = buffer[i];
        if (x > 1.0f) {
            buffer[i] = 1.0f - (1.0f / (3.0f * x));
        } else if (x < -1.0f) {
            buffer[i] = -1.0f - (1.0f / (3.0f * x));
        } else {
            buffer[i] = x - (x * x * x) * (1.0f / 3.0f);
        }
    }
}

float SimdMixer::calculateRms(const float* __restrict buffer, size_t numFrames) {
    if (numFrames == 0) return 0.0f;

    float sum = 0.0f;
    size_t i = 0;

#if defined(PULSO_HAS_NEON)
    float32x4_t vSum = vdupq_n_f32(0.0f);
    const size_t simdLimit = numFrames & ~3UL;

    for (; i < simdLimit; i += 4) {
        float32x4_t v = vld1q_f32(buffer + i);
        vSum = vfmaq_f32(vSum, v, v); // vSum += v * v
    }

    // Horizontal sum of the 4 vector lanes
    float temp[4];
    vst1q_f32(temp, vSum);
    sum = temp[0] + temp[1] + temp[2] + temp[3];
#endif

    for (; i < numFrames; ++i) {
        sum += buffer[i] * buffer[i];
    }

    return std::sqrt(sum / static_cast<float>(numFrames));
}

} // namespace PulsoAudio
