#ifndef PULSO_ENGINE_H
#define PULSO_ENGINE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define PULSO_API __declspec(dllexport)
#else
  #define PULSO_API __attribute__((visibility("default")))
#endif

#define PULSO_MAX_CHANNELS 64
#define PULSO_MAX_SECTIONS 32

typedef enum {
    PULSO_BUS_MASTER = 0,    // Stereo out (FOH / audience)
    PULSO_BUS_CUE    = 1     // Headphones / In-Ear Aux (Click + Guide + Monitors)
} PulsoBusType;

typedef struct {
    char name[32];
    int32_t startBar;
    int32_t lengthBars;
    uint32_t colorHex;
} PulsoSection;

typedef struct {
    char label[32];
    float gain;          // 0.0 to 1.0 (or >1.0 with headroom)
    float pan;           // -1.0 (Left) to +1.0 (Right)
    bool muted;
    bool solo;
    PulsoBusType bus;    // Route to Master or Cue
} PulsoChannelConfig;

typedef struct {
    int32_t currentBar;
    int32_t currentBeat;
    int32_t currentSixteenth;
    float positionSeconds;
    float bpm;
    bool isPlaying;
    int32_t activeSectionIndex;
    float masterRmsL;
    float masterRmsR;
    float channelRms[PULSO_MAX_CHANNELS];
} PulsoPlaybackState;

// Engine Lifecycle
PULSO_API void* pulso_create_engine(uint32_t sampleRate, uint32_t bufferSize);
PULSO_API void pulso_destroy_engine(void* engine);

// Audio Transport
PULSO_API void pulso_play(void* engine);
PULSO_API void pulso_pause(void* engine);
PULSO_API void pulso_stop(void* engine);
PULSO_API void pulso_set_bpm(void* engine, float bpm);
PULSO_API void pulso_jump_to_bar(void* engine, int32_t targetBar, bool quantizeToNextBar);
PULSO_API void pulso_jump_to_section(void* engine, int32_t sectionIndex, bool quantizeToNextBar);

// Pitch & Key Transposition
PULSO_API void pulso_set_pitch_semitones(void* engine, float semitones); // -6.0 to +6.0

// Stem Mixer Control
PULSO_API void pulso_set_channel_gain(void* engine, int32_t channelIndex, float gain);
PULSO_API void pulso_set_channel_mute(void* engine, int32_t channelIndex, bool muted);
PULSO_API void pulso_set_channel_solo(void* engine, int32_t channelIndex, bool solo);
PULSO_API void pulso_set_channel_bus(void* engine, int32_t channelIndex, PulsoBusType bus);
PULSO_API void pulso_set_master_gain(void* engine, float gain);

// Click & CUE Controls
PULSO_API void pulso_set_click_enabled(void* engine, bool enabled);
PULSO_API void pulso_set_click_volume(void* engine, float volume);
PULSO_API void pulso_set_count_in(void* engine, bool enabled, int32_t bars);

// Ambient Continuous Pad Synth
PULSO_API void pulso_start_ambient_pad(void* engine, int32_t keyIndex, float volume); // 0=C, 1=C#, ..., 11=B
PULSO_API void pulso_stop_ambient_pad(void* engine, float fadeOutSeconds);

// Telemetry & Real-Time Monitoring
PULSO_API void pulso_get_state(void* engine, PulsoPlaybackState* outState);

// Audio Callback (Called directly by CoreAudio or Google Oboe)
PULSO_API void pulso_render_audio(void* engine, float* masterOutL, float* masterOutR, float* cueOutL, float* cueOutR, uint32_t numFrames);

#ifdef __cplusplus
}
#endif

#endif // PULSO_ENGINE_H
