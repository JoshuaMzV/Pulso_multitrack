#include <jni.h>
#include <oboe/Oboe.h>
#include "pulso_engine.h"
#include <algorithm>
#include <array>
#include <memory>

namespace {
constexpr int blockSize = 512;
struct Player : oboe::AudioStreamDataCallback {
    void* engine = nullptr;
    std::shared_ptr<oboe::AudioStream> stream;
    std::array<float, blockSize> left{}, right{}, cueL{}, cueR{};

    ~Player() {
        if (stream) stream->close();
        pulso_destroy_engine(engine);
    }
    oboe::DataCallbackResult onAudioReady(oboe::AudioStream*, void* data, int32_t frames) override {
        auto output = static_cast<float*>(data);
        for (int offset = 0; offset < frames; offset += blockSize) {
            int count = std::min(blockSize, frames - offset);
            pulso_render_audio(engine, left.data(), right.data(), cueL.data(), cueR.data(), count);
            for (int i = 0; i < count; ++i) {
                output[2 * (offset + i)] = std::clamp(left[i] + cueL[i], -1.f, 1.f);
                output[2 * (offset + i) + 1] = std::clamp(right[i] + cueR[i], -1.f, 1.f);
            }
        }
        return oboe::DataCallbackResult::Continue;
    }
};
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_pulso_multitrack_NativeAudio_open(JNIEnv* env, jobject, jint rate, jfloatArray left, jfloatArray right) {
    if (rate <= 0 || !left || !right) return 0;
    const auto count = env->GetArrayLength(left);
    if (!count || count != env->GetArrayLength(right)) return 0;
    try {
        auto player = std::make_unique<Player>();
        player->engine = pulso_create_engine(rate, blockSize);
        auto l = env->GetFloatArrayElements(left, nullptr);
        auto r = env->GetFloatArrayElements(right, nullptr);
        const bool loaded = pulso_load_stereo(player->engine, l, r, count);
        if (l) env->ReleaseFloatArrayElements(left, l, JNI_ABORT);
        if (r) env->ReleaseFloatArrayElements(right, r, JNI_ABORT);
        if (!loaded) return 0;
        oboe::AudioStreamBuilder builder;
        builder.setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setFormat(oboe::AudioFormat::Float)
            ->setSampleRate(rate)
            ->setChannelCount(2)
            ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
            ->setDataCallback(player.get());
        if (builder.openStream(player->stream) != oboe::Result::OK ||
            player->stream->getSampleRate() != rate ||
            player->stream->requestStart() != oboe::Result::OK) return 0;
        return reinterpret_cast<jlong>(player.release());
    } catch (...) { return 0; }
}

extern "C" JNIEXPORT void JNICALL
Java_com_pulso_multitrack_NativeAudio_close(JNIEnv*, jobject, jlong handle) {
    delete reinterpret_cast<Player*>(handle);
}
extern "C" JNIEXPORT void JNICALL
Java_com_pulso_multitrack_NativeAudio_command(JNIEnv*, jobject, jlong handle, jint action, jfloat value) {
    auto player = reinterpret_cast<Player*>(handle);
    if (!player) return;
    switch (action) {
        case 0: pulso_play(player->engine); break;
        case 1: pulso_pause(player->engine); break;
        case 2: pulso_stop(player->engine); break;
        case 3: pulso_set_master_gain(player->engine, value); break;
    }
}
extern "C" JNIEXPORT jfloat JNICALL
Java_com_pulso_multitrack_NativeAudio_position(JNIEnv*, jobject, jlong handle) {
    auto player = reinterpret_cast<Player*>(handle);
    return player ? pulso_position(player->engine) : 0;
}
