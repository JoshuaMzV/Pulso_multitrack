# PULSO: Master Architecture & Technical Specification
## The Next-Generation Multitrack & Stage Playback System for iOS (IPA) & Android (APK)

---

## 1. Executive Vision & Competitive Strategy

### Why Playback (MultiTracks.com) & Prime (Loop Community) Fall Short
1. **Platform Exclusivity & Fragmentation**:
   - **Playback** is heavily constrained to Apple devices (iPadOS/iOS/macOS). Android musicians and worship teams are completely excluded from professional multitrack playback.
   - **Prime** offers an Android client, but it suffers from severe Android audio fragmentation: high audio latency (80–180ms), buffer underruns, click jitter, and frequent crashes on non-Samsung/Pixel devices due to reliance on standard Java/ExoPlayer audio stacks.
2. **Cloud Gatekeeping & Cost**:
   - Both platforms restrict stem upload behind expensive monthly tiers (e.g. MultiTracks Cloud Pro). Teams cannot easily drop their own studio stems from USB, AirDrop, Google Drive, or local storage without paying subscription fees.
3. **Seat Management & Role Friction**:
   - Teams must pay per-seat licenses with rigid permissions. In typical church or touring band scenarios, members need to practice with personal transpositions (e.g., guitar capo, brass Bb/Eb transpositions, vocal warmups) without messing up the master stage setlist.
4. **Dependency on Web Portals**:
   - Preparing, uploading, and organizing custom multitracks often forces users to open a desktop web browser. 

### PULSO Strategic Moat
- **Universal Low-Latency Performance**: Identical < 5ms audio latency on both iOS (CoreAudio) and Android (Google Oboe / AAudio in exclusive low-latency burst mode) powered by a shared **C++20 / ARM NEON SIMD audio core**.
- **Dual Dynamic View Modes**:
  - **Vista Edición (Studio Mode)**: Full multitrack mixer (64 channels), stem routing, section marker setup, in-app ZIP/stem importer, and organization seats management.
  - **Vista Show (Live Stage Mode)**: High-contrast stage console with a centered top **Hero Stage Card**. The song cover art starts masked in opaque black and progressively reveals the full-color vivid artwork as the song advances, acting as a natural duration/progress indicator. Includes massive tactile section launch pads, drummer beat flasher, and quick in-ear monitoring sliders.
- **Mobile-First In-App Multitrack Importer**: Full local ingestion of ZIP archives, WAV/M4A/MP3 multitracks directly from the phone/tablet storage. Automatic track categorization (Click, Guide, Drums, Bass, Keys, Guitars, Vocals) and peak waveform caching.
- **Seat & Role Ecosystem**:
  - **Band Leader**: Full administrative rights (upload multitracks, build setlists, assign song keys/BPM, manage organization seats, control master stage playback).
  - **Band Member (Seat)**: Read-only access to master setlists, with local personal control: personal instrument key transpose (independent of master audio), personal in-ear monitor mix (solo/mute own track for rehearsal), and live stage chord/section synchronization.
- **Continuous Ambient Pads & Seamless Transitions**: Built-in 12-key atmospheric pad drone synthesizer running continuously underneath song transitions to eliminate stage silence.
- **Stage Sync (P2P + Cloud)**: Ableton Link + local stage UDP broadcast for zero-latency local Wi-Fi synchronization with zero internet required at the venue.

---

## 2. System Architecture Diagram

```
+-----------------------------------------------------------------------------------+
|                                 USER INTERFACE                                    |
|              (Flutter 3.x with Impeller GPU Acceleration / 120 FPS)               |
|                                                                                   |
|  [Hardware Console Mixer]    [Multi-Track Waveforms]    [Transport & Section Pads] |
|  [In-App ZIP/Stem Importer]  [Roles & Seats Manager]   [Ambient Pads & Crossfades] |
+------------------------------------------+----------------------------------------+
                                           |
                                [Dart FFI Pointer Bridge]
                                           |
+------------------------------------------v----------------------------------------+
|                      PULSO CORE AUDIO ENGINE (C++20 / SIMD)                        |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  | Lock-Free SPSC Command Queue (Zero-Allocation UI <-> Audio Thread)          |  |
|  +-----------------------------------------------------------------------------+  |
|  | 64-Channel Summing Bus with ARM NEON SIMD (Vectorized Fused Multiply-Add)   |  |
|  +-----------------------------------------------------------------------------+  |
|  | Signalsmith Stretch (MIT) - Independent Elastic Tempo (BPM) & Pitch (±6 ST)  |  |
|  +-----------------------------------------------------------------------------+  |
|  | Dynamic Section Quantizer & Micro-Crossfade Engine (< 5ms Seamless Jumps)   |  |
|  +-----------------------------------------------------------------------------+  |
|  | Independent Bus Routing: Master Stereo L/R | CUE Click & Voice Guide (Aux)  |  |
|  +-----------------------------------------------------------------------------+  |
|  | Ambient Drone / Pad Wavetable Synthesizer (12 Keys, Infinite Loop)          |  |
|  +-----------------------------------------------------------------------------+  |
|                                                                                   |
|  +-------------------------------------+   +------------------------------------+ |
|  |     iOS HAL: CoreAudio RemoteIO     |   |   Android HAL: Google Oboe/AAudio  | |
|  | (AudioUnit, Real-Time Priority 63)  |   | (Exclusive Burst Buffer, Low Lat)  | |
|  +-------------------------------------+   +------------------------------------+ |
+-----------------------------------------------------------------------------------+
```

---

## 3. Technology Stack Selection & Rationale

| Layer | Recommended Technology | Technical Rationale |
|---|---|---|
| **Audio Core** | **C++20 with ARM NEON Intrinsics** | Hard real-time audio thread execution. Absolute guarantee of zero garbage-collection pauses. Compiles to native ARM64 for both iOS and Android. |
| **Android Audio Driver** | **Google Oboe (C++)** | Automatically selects AAudio on Android 8.0+ (API 26+) and falls back to OpenSL ES on older devices. Configured with `AAUDIO_PERFORMANCE_MODE_LOW_LATENCY` and `AAUDIO_SHARING_MODE_EXCLUSIVE`. |
| **iOS Audio Driver** | **CoreAudio (AudioUnit RemoteIO)** | Standard pro-audio interface in iOS with direct buffer callback delivery, yielding < 3ms hardware latency. |
| **Pitch & Time Stretch** | **Signalsmith Stretch (C++20)** | High-performance, header-only MIT licensed pitch-shifting and time-stretching library. Exceptional transient clarity on drum tracks compared to SoundTouch. |
| **UI Framework** | **Flutter (Dart 3.x) + Dart FFI** | Unmatched cross-platform 120 FPS rendering of complex canvas waveforms, custom sliders, and LED meters. Dart FFI passes raw pointers to C++ structs with zero overhead. Single codebase produces both `.ipa` (iOS) and `.apk`/`.aab` (Android). |
| **Stage Sync (Local)** | **Ableton Link + Local UDP Broadcast** | Ableton Link synchronizes BPM and beat phase over local Wi-Fi without a central server. UDP broadcast distributes section jump commands in < 2ms without internet access. |
| **Backend & Auth** | **Supabase (PostgreSQL + RLS + S3 Storage)** | Native Row Level Security (RLS) handles member seats, band permissions, and cloud multitrack backups. Realtime channels sync setlist changes between devices. |
| **Local Cache & Storage**| **SQLite (via FFI) + Raw Audio Blobs** | Instant offline loading during live concerts. Audio stems are decrypted and streamed directly into RAM/memory-mapped files. |

---

## 4. In-App Multitrack Importer (No Web Portal Needed)

The application eliminates web dashboard dependencies with an intelligent mobile file ingestion engine:
1. **Document / Cloud File Picker**:
   - User taps `+ Import Song` inside the app.
   - Supports selecting `.zip`, `.m4a`, `.wav`, or choosing an entire folder from iOS Files / Android Document Provider / Google Drive / iCloud.
2. **Automated Stem Classification Engine**:
   - When a ZIP is extracted in an isolated staging sandbox, filenames are normalized and matched against an intelligent audio regex dictionary:
     - `CLICK`: `/(click|metronome|tempo|klick)/i` -> Assigned to Cue Bus (Aux 1).
     - `GUIDE`: `/(guide|cue|vox_cue|direcc)/i` -> Assigned to Cue Bus (Aux 2).
     - `DRUMS`: `/(drum|bateria|kick|snare|hihat|tom|overhead)/i` -> Drums Stem.
     - `BASS`: `/(bass|bajo|synth_bass)/i` -> Bass Stem.
     - `KEYS`: `/(keys|piano|rhodes|organ|teclados)/i` -> Keys Stem.
     - `PAD`: `/(pad|ambient|drone|atmos)/i` -> Pad Stem.
     - `GUITARS`: `/(eg|ag|electric|acoustic|guitar|guitarras)/i` -> Guitars Stem.
     - `VOCALS`: `/(vox|lead|bgv|choir|coros)/i` -> Vocals Stem.
3. **Fast Peak Waveform Generation**:
   - Audio files are decoded in background worker threads to extract RMS and min/max peak decibels (1 sample per 256 audio frames).
   - Peak arrays are serialized into compact `.peak` binary files. Waveform rendering on the UI reads precomputed peaks instead of decoding multi-gigabyte audio in real time.
4. **Song Metadata Tagging**:
   - User specifies or confirms: Song Name, Artist, BPM, Original Key, Time Signature, and Section Markers (Intro, Verse, Chorus, Bridge, etc.).

---

## 5. Organization, Seats, and Role-Based Permissions

```
                           +------------------------+
                           |   ORGANIZATION / BAND  |
                           |  (Subscription Plan)   |
                           +-----------+------------+
                                       |
                   +-------------------+-------------------+
                   |                                       |
        +----------v-----------+               +-----------v-----------+
        |     BAND LEADER      |               |  MEMBER (SEAT USER)   |
        +----------------------+               +-----------------------+
        | • Create/Edit Songs  |               | • View Setlists       |
        | • Upload Multitracks |               | • Personal Key Trans. |
        | • Edit Master Setlist|               | • Personal Monitor Mix|
        | • Master Stage Play  |               | • Rehearsal Mode      |
        | • Manage Seat Access |               | ✕ No Song Deletions   |
        +----------------------+               | ✕ No Multitrack Upload|
                                               +-----------------------+
```

### Permission Matrix
| Feature / Action | Band Leader | Member (Seat) | Guest / Roadie |
|---|---|---|---|
| Upload Multitrack ZIP / Stems | **YES** | NO | NO |
| Delete or Edit Song Metadata | **YES** | NO | NO |
| Create & Reorder Master Setlist | **YES** | NO | NO |
| Launch Stage Playback (Master) | **YES** | NO (unless delegated) | NO |
| View Setlists & Chord Charts | **YES** | **YES** | **YES** |
| Personal Transposition (Rehearsal/In-Ear) | **YES** | **YES** | NO |
| Personal In-Ear Mix Faders | **YES** | **YES** | NO |
| Offline Cache Download | **YES** | **YES** | NO |

---

## 6. Assembly & SIMD Optimization Strategy

### The Multitrack Audio Mixing Challenge
At 48,000 Hz, 64 audio tracks running simultaneously produce **3,072,000 floating-point samples per second**.
In a naive scalar C++ loop:
```cpp
// SLOW SCALAR LOOP (High CPU & Battery Drain)
for (int ch = 0; ch < 64; ++ch) {
    float gain = channelGains[ch];
    for (int i = 0; i < bufferSize; ++i) {
        output[i] += channelBuffers[ch][i] * gain;
    }
}
```
### The ARM NEON Vectorized Solution
Every modern iOS device (A12 through A18 / M-series) and Android smartphone (Snapdragon, Dimensity, Tensor) uses ARMv8-A or ARMv9 64-bit architecture with **ARM NEON SIMD**.
With NEON, 128-bit vector registers (`q0` to `q31`) process **four 32-bit floats simultaneously** in a single instruction cycle:
- `vld1q_f32`: Vector Load 4 floats from memory.
- `vfmaq_f32`: Vector Fused Multiply-Accumulate (`out += stem * gain` with zero rounding loss).
- `vmaxnmq_f32` / `vminnmq_f32`: Vectorized soft-clipping protection.

By utilizing NEON intrinsics, the CPU load for 64 tracks drops from ~18% down to **under 2.1%**, preserving mobile battery life and preventing thermal throttling on stage.

---

## 7. Stage UX Design System & Real-Time Visualization

### 1. Dual Mode Workflow
- **Edición (Studio / Rehearsal)**: 64-channel multitrack mixer, stem gain faders, in-app multitrack zip uploader, song transposition, and seat management.
- **Show (Live Stage Mode)**: High-contrast, glanceable UI designed for stage lighting and rapid touch gestures during live performance.

### 2. Hero Stage Card & Stencil Knockout Mask (Version Identification)
- **Full-Bleed Artwork Layer**: The active album cover (e.g. `214.jpg`) rendered cleanly at the base.
- **Deep Dark Stencil Overlay (`hero-black-stencil`)**: An 80% deep dark overlay (`fill="#060709" fill-opacity="0.80"`, reduced by 15% from 0.95) with hollow vector cut-out typography forming the song title across two rows (`TU PRESENCIA` / `ES EL CIELO`). This allows the underlying cover art to breathe through softly at 20% visibility while giving 100% crystal-clear visibility inside the letters.
- **Cover Art Cutout Window**: Through the letter cutouts, the actual album artwork shines through in 100% full color, allowing musicians on stage to immediately recognize the specific album/song version.
- **Hero Song Typography (`Lato 900 Black`)**: Exclusively for the song title overlaid on the hero background/cover art (`--font-hero-song: 'Lato'`), heavy humanist 900-weight typography is used. Its harmonious rounded curves eliminate edge spikiness along vector stroke boundaries, providing high-contrast readability from across the stage while general UI elements preserve `Archivo` and `IBM Plex Mono`.
- **Delicate Hairline Shaded Border (`#whiteShadedFilter`)**: An ultra-thin 0.8px soft white border (`rgba(255, 255, 255, 0.50)`) equipped with rounded caps/joins (`stroke-linejoin="round" stroke-linecap="round"`) and a tight contact shadow (`feDropShadow dy="0.8" stdDeviation="1.0"`), producing a clean, natural contour without harsh or muddy edge artifacts.
- **Unidirectional Upward Audacity Waveform Strip (`hero-waveform-strip`)**: A delicate 22px high audio dynamic peak bar strip along the bottom edge of the card. Unlike standard mirrored waveforms, it projects **strictly upward** from the bottom edge like a dynamic energy meter. Played segments are illuminated in warm stage amber (`#f59e0b`), while upcoming segments remain in subtle translucent white (`rgba(255, 255, 255, 0.22)`), with live micro-flutter during active playback.
- **Centered Chord Badge (`hero-tone-badge`)**: Centered horizontally at the bottom of the card, displaying strictly the chord letter (e.g., `E` or `D`) in large, bold 16px high-contrast amber styling without unnecessary prefixes, floating above the waveform strip with a frosted backdrop blur.
- **Dynamic Laser Wipe (`hero-laser-wipe`)**: As the audio timeline progresses, the dark stencil sheet and shaded white border are progressively peeled away from left to right via `clip-path: polygon(...)`, cleanly revealing the full, borderless cover art underneath.

### 3. Transition Control (Flecha Blanca)
- A circular white transition arrow placed between current song and upcoming song ("Rey de Reyes").
- Opens a video-editor-style transition inspector offering:
  - `De una vez` (Instant switch on bar 1)
  - `Crossfade` (Smooth 3-second curve)
  - `Pad continuo` (Underlying ambient drone prevents stage silence)
  - `Pausa` (Wait for live cue / manual play)

### 4. Compact Header Transport & Stacked Live Timing Display
- **Ultra-Compact Header (Reduced by 18%)**: Height trimmed to 48px with scaled-down transport controls to maximize stage area.
- **Timing Display (Top Header Only)**:
  - **Top Row (Elapsed)**: `00:39` (Tabular monospace font).
  - **Bottom Row (Total Range)**: `0:00 / 2:27` (Amber accent font).
  - Exclusively housed in the top header to keep the stage card clean and uncluttered.

### 5. Stage Master Console & Separated Stereo Output (Sonido Separado L / R)
- **Minimalist Stage Controls**: To prepare for upcoming stage reimaginings, all legacy section pads (`INTRO`, `VERSO`, `CORO`, `PUENTE`), stage dock transport (`PLAY`/`STOP`), visual compass (`COMPÁS 1.1`), and ambient pad keys strip were eliminated from the Show tab.
- **Dual-Channel Separated Stereo Metering (`stageStereoCanvas`)**:
  - Independent **Left (Canal L)** and **Right (Canal R)** 24-segment LED ladder peak meters calibrated from `+6 dB` down to `-inf dB`.
  - Driven directly by Web Audio `ChannelSplitter(2)` and dedicated analyzer nodes (`anaL` and `anaR`).
  - Real-time numerical peak readouts per channel (`L: -2.1 dB` / `R: -2.3 dB`).
- **Tactile Stage Master Fader (`stageMasterFader`)**:
  - Machined long-throw fader with glowing amber center line.
  - Instant tactile feedback, synchronized bidirectionally with the Edition Mode mixer master channel.
  - Quick action macros: Master Mute toggle (`M`), Unity Gain (`0 dB`), and Quick Attenuation (`-6 dB`).

---

## 8. Multitrack Edition Console & Real-Time Studio Engine (Mode Edición)

### 1. Architectural Fidelity & Reference Design
The Edition Mode console (`#editionConsole`) replicates the hardware-inspired digital audio workstation (DAW) layout inspired by `"Captura de pantalla 2026-09-17 155815.png"` and `"Nuevo Documento de texto.html"`. It provides professional touring sound engineers and worship leaders with precise mixing, routing, and section arrangement capabilities.

```
+---------------------------------------------------------------------------------------------------------+
| [●] RUNNING  TU PRESENCIA ES EL CIELO · 128 BPM · 4/4 · D   [ READY > PLAYING ]     00:39.12  BAR 3.2   |
+-------------------------------------------------------------+-------------------------------------------+
| MIXER CHANNELS (5 Stems)                                    | MULTITRACK TIMELINE                       |
| +---------+ +---------+ +---------+ +---------+ +---------+ | [ INTRO ] [   VERSO   ] [ CORO ] [PUENTE] |
| | BATERIA | |  BAJO   | | TECLAS  | |  GUIA   | |  CLICK  | | 1    .    2    .    3    .    4    .    |
| | [24-LED]| | [24-LED]| | [24-LED]| | [24-LED]| | [24-LED]| | [BATERÍA]  |||||||||||||||||||||||||||||| |
| |  FADER  | |  FADER  | |  FADER  | |  FADER  | |  FADER  | | [BAJO]     ████████  ████████  ████████   |
| | [S] [M] | | [S] [M] | | [S] [M] | | [S] [M] | | [S] [M] | | [TECLAS]   ~~~~~~~~~~~~~~~~~~~~~~~~~~ |
| | -3.2 dB | | -5.0 dB | | -2.1 dB | |  0.0 dB | | -1.5 dB | | [GUÍA]     ___/\/\____/\/\____________|
| +---------+ +---------+ +---------+ +---------+ +---------+ | [CLICK]    |   |   |   |   |   |   |   |  |
+-------------------------------------------------------------+-------------------------------------------+
| [◀◀] [▶ PLAY] [■] | 128 BPM [TAP] | [✓] CLICK [✓] CONTEO | [INTRO] [VERSO] [CORO] | [GUÍA -] [SOLO CLICK]|
+---------------------------------------------------------------------------------------------------------+
```

### 2. Console Header (`.c-head`)
- **Status LED (`.runled`)**: Pulsing green/amber/red LED reflecting the active transport state (blinking red when live playback is active, solid amber on pause, dim when stopped).
- **Metadata Title (`.c-title`)**: Displays current song name, master tempo, time signature, and root musical key.
- **Terminal Status Console (`.c-status`)**: Monospace retro-green terminal logging real-time engine events (`READY > PLAYING`, `BAR 3.2`, `CH_MUTE [GUIA]`, `TAP TEMPO 128`), complete with a blinking cursor.
- **Precision Timecode Clock (`.c-clock`)**: Monospace tabular readout showing elapsed time down to tenths of a second (`00:39.1`), compass measure and beat (`BAR 3.2`), and 4-phase 16th sub-beat activity dots (`.c-dots`).

### 3. Multitrack Timeline & Waveform Engine (`.timeline`)
- **Top Section Navigation Band (`.tl-band`)**:
  - Arranged by musical song structure (`INTRO`, `VERSO`, `CORO`, `PUENTE`).
  - Active section is dynamically highlighted with warm amber background tinting, glowing border, and section text.
  - Clicking any section triggers a sample-accurate, beat-quantized playback jump.
- **Measure Ruler (`.tl-ruler`)**:
  - Clearly calibrated measure numbers (`1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`).
  - Downbeat tick lines and quarter-beat division marks (`.tl-rb`).
- **Stem Waveform Lanes (`.tl-tracks`)**:
  - High-performance HTML5 `<canvas>` rendering (`drawWave`) tailored to each stem's acoustic signature:
    - **BATERÍA**: Transient spikes centered vertically at `H/2`, with high-amplitude kicks on downbeats and snares on beats 2 and 4.
    - **BAJO**: Sustained block waveforms with rhythmic rests and melodic fundamental contours.
    - **TECLAS**: Smooth, continuous envelope resembling sustained polyphonic synth pads and electric piano resonance.
    - **GUÍA (Voice Cues)**: Silent across intro/verse, showing distinct triangular hit envelopes during chorus/bridge cues ("1, 2, 3, CORO!").
    - **CLICK**: Periodic, needle-sharp metronome impulses on quarter beats with accent on beat 1.
- **Interactive Playhead (`.playhead`)**:
  - Vertical 2px amber needle with a downward-pointing triangle cursor (`border: 5px solid transparent; border-top-color: var(--amber)`).
  - Draggable across the timeline for instant scrubbing.

### 4. Hardware Channel Strip & Metering (`.mixer`)
- **24-Segment LED Peak Ladders (`.ch-meter`)**:
  - Dual-column, 24-step hardware-calibrated LED peak meters per channel.
  - Color gradient mapping: Green (-inf to -12 dB), Amber (-12 dB to -3 dB), Red (-3 dB to 0 dB / Clip).
  - Fast attack (< 1ms) and smooth ballistic decay with peak-hold behavior.
- **Tactile Long-Throw Faders (`.fader`, `.fader-cap`)**:
  - Machined aluminum-style cap with high-contrast amber center line.
  - Full pointer/touch dragging support with logarithmic dB attenuation mapping (`-inf` to `+6 dB`).
- **Channel Buttons & Readouts**:
  - Dedicated **Solo** (`S`, glowing amber) and **Mute** (`M`, illuminated red) buttons.
  - Real-time numerical decibel indicator badge (`.ch-db`).

### 5. Transport Foot & Global Macros (`.c-foot`)
- **Playback Controls**: Rewind to beginning, Play/Pause toggle with spacebar keybinding, and Stop.
- **Tempo Module**: Draggable/scrubbable BPM control, plus responsive multi-tap averaging button (`TAP`).
- **Cue Toggles**: Independent enable/disable for metronome `CLICK` and vocal guide `CONTEO`.
- **Live Section Launch Pads**: Dedicated tactile pads for instant section triggering on stage.
- **Quick Automation Macros**:
  - `GUÍA −`: Drops vocal cue level by 6 dB during quiet prayer/worship moments.
  - `SOLO CLICK`: Instantly isolates metronome click for the drummer's in-ear monitor.
  - `RESET`: Restores default gain staging and clears mutes/solos across all stems.

### 6. Integrated Polyphonic Web Audio Engine
- Built-in zero-dependency Web Audio API synthesizer generating realistic multitrack stems:
  - `vKick` & `vSnare`: Synthesized dual-oscillator pitch-drop kick and filtered white-noise snare.
  - `vHat`: High-pass filtered square-wave cluster hi-hats with open/closed decay dynamics.
  - `vBass`: Resonant low-pass sawtooth bass synth following the harmonic chord progression in D major.
  - `vPad`: Warm detuned saw/triangle pad with gentle low-pass filtering.
  - `vLead`: Expressive bell/keys pluck with exponential gain envelope.
  - `vClick`: Wooden clave/rimshot impulse generator on 1/4 notes.
- **Bi-Directional State Synchronization**:
  - The shared 16th-note clock `getBeat16()` synchronizes Show Mode (laser wipe, Audacity upward strip, cover stencil reveal, header timer) and Edition Mode (timeline playhead, LED meters, clock readout, terminal logs) simultaneously.


