import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - C++ Audio Bridge Wrapper

private final class PulsoRender {
    let handle: UnsafeMutableRawPointer
    private let block = 512
    private let scratch: UnsafeMutablePointer<Float>

    init?(rate: UInt32) {
        guard let engine = pulso_create_engine(rate, 512) else { return nil }
        handle = engine
        scratch = .allocate(capacity: 512 * 4)
    }

    func add(_ pcm: AVAudioPCMBuffer, index: Int, cue: Bool) -> Bool {
        guard let channels = pcm.floatChannelData else { return false }
        let right = pcm.format.channelCount == 2 ? channels[1] : channels[0]
        return pulso_load_stem(handle, channels[0], right, pcm.frameLength, UInt32(index), cue)
    }

    deinit {
        pulso_destroy_engine(handle)
        scratch.deallocate()
    }

    func render(frames: Int, output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        guard buffers.count == 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
            return kAudio_ParamError
        }
        let musicL = scratch
        let musicR = scratch + block
        let cueL = scratch + block * 2
        let cueR = scratch + block * 3
        for offset in stride(from: 0, to: frames, by: block) {
            let count = min(block, frames - offset)
            pulso_render_audio(handle, musicL, musicR, cueL, cueR, UInt32(count))
            for i in 0..<count {
                left[offset + i] = min(1, max(-1, musicL[i] + cueL[i]))
                right[offset + i] = min(1, max(-1, musicR[i] + cueR[i]))
            }
        }
        return noErr
    }
}

// MARK: - Models

struct ChannelItem: Identifiable {
    let id: Int
    var name: String
    var db: Float = 0.0
    var muted: Bool = false
    var solo: Bool = false
    var bus: PulsoBusType = PULSO_BUS_MASTER
    var rms: Float = 0.0
    var isCueDefault: Bool = false
}

struct SectionItem: Identifiable {
    let id: Int
    var name: String
    var startBar: Int
    var lengthBars: Int
    var color: Color
}

// MARK: - Audio Controller (MainActor Observable)

@MainActor
final class PulsoAudioController: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentSeconds: Double = 0.0
    @Published var totalDuration: Double = 0.0
    @Published var currentBar: Int = 1
    @Published var currentBeat: Int = 1
    @Published var bpm: Double = 120.0
    @Published var masterDb: Float = 0.0
    @Published var masterRms: Float = 0.0
    @Published var channels: [ChannelItem] = []
    @Published var sections: [SectionItem] = []
    @Published var activeSectionIndex: Int = 0
    @Published var loopSection: Bool = false

    @Published var songTitle: String = "PULSO SHOW"
    @Published var songArtist: String = "Stems Locales"
    @Published var songKey: String = "C"
    @Published var padActive: Bool = false
    @Published var padKeyIndex: Int = 0
    @Published var padVolume: Float = 0.7

    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Importa pistas FLAC o WAV para comenzar."
    @Published var errorMessage: String? = nil

    private var output: AVAudioEngine?
    private var renderer: PulsoRender?
    private var timer: Timer?
    private let ioQueue = DispatchQueue(label: "com.pulso.multitrack.io", qos: .userInitiated)

    var libraryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PulsoStems", isDirectory: true)
    }

    init() {
        setupDefaultSections()
        startTelemetryTimer()
        loadExistingLibraryIfAvailable()
    }

    deinit {
        timer?.invalidate()
        output?.stop()
    }

    private func setupDefaultSections() {
        let colors: [Color] = [
            Color(red: 0.15, green: 0.45, blue: 0.85),
            Color(red: 0.1, green: 0.65, blue: 0.55),
            Color(red: 0.95, green: 0.6, blue: 0.1),
            Color(red: 0.1, green: 0.65, blue: 0.55),
            Color(red: 0.95, green: 0.6, blue: 0.1),
            Color(red: 0.65, green: 0.3, blue: 0.85),
            Color(red: 0.95, green: 0.6, blue: 0.1),
            Color(red: 0.4, green: 0.45, blue: 0.55)
        ]
        let names = ["INTRO", "VERSO 1", "CORO", "VERSO 2", "CORO", "PUENTE", "CORO", "OUTRO"]
        var items: [SectionItem] = []
        var bar = 1
        for (i, name) in names.enumerated() {
            items.append(SectionItem(id: i, name: name, startBar: bar, lengthBars: 8, color: colors[i % colors.count]))
            bar += 8
        }
        self.sections = items
    }

    private func startTelemetryTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollTelemetry()
            }
        }
    }

    private func pollTelemetry() {
        guard let renderer = renderer else { return }
        var state = PulsoPlaybackState()
        pulso_get_state(renderer.handle, &state)

        self.isPlaying = state.isPlaying
        self.currentSeconds = Double(state.positionSeconds)
        self.currentBar = Int(state.currentBar)
        self.currentBeat = max(1, min(4, Int(state.currentBeat)))
        self.masterRms = max(state.masterRmsL, state.masterRmsR)

        // Read channel RMS levels safely from C struct fixed-size array
        withUnsafeBytes(of: &state.channelRms) { rawBuffer in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<min(channels.count, 64) {
                channels[i].rms = floatPtr[i]
            }
        }

        // Section update & auto loop
        updateCurrentSection()
    }

    private func updateCurrentSection() {
        guard !sections.isEmpty else { return }
        for (idx, sec) in sections.enumerated().reversed() {
            if currentBar >= sec.startBar {
                activeSectionIndex = idx
                if loopSection && currentBar >= (sec.startBar + sec.lengthBars) {
                    jumpToBar(sec.startBar)
                }
                break
            }
        }
    }

    // MARK: - Transport Actions

    func play() {
        guard let renderer = renderer else { return }
        pulso_play(renderer.handle)
        isPlaying = true
    }

    func pause() {
        guard let renderer = renderer else { return }
        pulso_pause(renderer.handle)
        isPlaying = false
    }

    func stop() {
        guard let renderer = renderer else { return }
        pulso_stop(renderer.handle)
        isPlaying = false
        currentSeconds = 0
        currentBar = 1
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func jumpToBar(_ bar: Int) {
        guard let renderer = renderer else { return }
        pulso_jump_to_bar(renderer.handle, Int32(bar), true)
        currentBar = bar
    }

    func jumpToSection(index: Int) {
        guard index >= 0 && index < sections.count else { return }
        activeSectionIndex = index
        jumpToBar(sections[index].startBar)
    }

    func toggleSectionLoop() {
        loopSection.toggle()
    }

    // MARK: - Mixer Controls

    func setChannelDb(index: Int, db: Float) {
        guard index >= 0 && index < channels.count, let renderer = renderer else { return }
        channels[index].db = db
        let linearGain: Float = db <= -59.5 ? 0.0 : pow(10.0, db / 20.0)
        pulso_set_channel_gain(renderer.handle, Int32(index), linearGain)
    }

    func toggleMute(index: Int) {
        guard index >= 0 && index < channels.count, let renderer = renderer else { return }
        channels[index].muted.toggle()
        pulso_set_channel_mute(renderer.handle, Int32(index), channels[index].muted)
    }

    func toggleSolo(index: Int) {
        guard index >= 0 && index < channels.count, let renderer = renderer else { return }
        channels[index].solo.toggle()
        pulso_set_channel_solo(renderer.handle, Int32(index), channels[index].solo)
    }

    func toggleBus(index: Int) {
        guard index >= 0 && index < channels.count, let renderer = renderer else { return }
        let newBus: PulsoBusType = channels[index].bus == PULSO_BUS_MASTER ? PULSO_BUS_CUE : PULSO_BUS_MASTER
        channels[index].bus = newBus
        pulso_set_channel_bus(renderer.handle, Int32(index), newBus)
    }

    func setMasterDb(_ db: Float) {
        masterDb = db
        guard let renderer = renderer else { return }
        let linearGain: Float = db <= -59.5 ? 0.0 : pow(10.0, db / 20.0)
        pulso_set_master_gain(renderer.handle, linearGain)
    }

    func setBpm(_ newBpm: Double) {
        bpm = max(40.0, min(240.0, newBpm))
        guard let renderer = renderer else { return }
        pulso_set_bpm(renderer.handle, Float(bpm))
    }

    // MARK: - Ambient Pad

    func togglePad() {
        padActive.toggle()
        guard let renderer = renderer else { return }
        if padActive {
            pulso_start_ambient_pad(renderer.handle, Int32(padKeyIndex), padVolume)
        } else {
            pulso_stop_ambient_pad(renderer.handle, 1.0)
        }
    }

    func setPadKey(index: Int) {
        padKeyIndex = index
        let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        songKey = keys[index % keys.count]
        if padActive, let renderer = renderer {
            pulso_start_ambient_pad(renderer.handle, Int32(padKeyIndex), padVolume)
        }
    }

    // MARK: - Stems Loading & Importing

    func loadExistingLibraryIfAvailable() {
        let saved = (try? FileManager.default.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil)) ?? []
        let audioFiles = saved.filter { ["flac", "wav"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if !audioFiles.isEmpty {
            loadFiles(audioFiles, importing: false)
        }
    }

    func importFiles(_ urls: [URL]) {
        loadFiles(urls, importing: true)
    }

    private func loadFiles(_ urls: [URL], importing: Bool) {
        guard !urls.isEmpty else { return }
        pause()
        isLoading = true
        statusMessage = "Cargando pistas de audio nativas…"
        errorMessage = nil

        let dest = libraryDirectory
        ioQueue.async { [weak self] in
            let result = Result { try Self.prepareStems(urls, destination: dest, importing: importing) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                do {
                    let prepared = try result.get()
                    try self.setupAudioGraph(prepared.renderer, sampleRate: prepared.rate, channels: prepared.channels, maxFrames: prepared.maxFrames)
                    self.statusMessage = "\(prepared.channels.count) pistas nativas listas"
                    self.songTitle = urls.first?.deletingPathExtension().lastPathComponent.components(separatedBy: "-").last ?? "CANCIÓN ACTIVA"
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "Error al cargar pistas"
                }
            }
        }
    }

    private struct PreparedSession {
        let renderer: PulsoRender
        let rate: Double
        let channels: [ChannelItem]
        let maxFrames: Int64
    }

    private nonisolated static func prepareStems(_ urls: [URL], destination: URL, importing: Bool) throws -> PreparedSession {
        func invalidErr(_ msg: String) -> NSError {
            NSError(domain: "PulsoLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard urls.count <= 64 else { throw invalidErr("Máximo 64 pistas por canción.") }

        let files = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        if importing { try files.createDirectory(at: staging, withIntermediateDirectories: true) }
        defer { if importing { try? files.removeItem(at: staging) } }

        var render: PulsoRender?
        var sampleRate = 0.0
        var totalFrames: Int64 = 0
        var longestTrackFrames: Int64 = 0
        var channelItems: [ChannelItem] = []

        for (index, url) in urls.enumerated() {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            guard ext == "flac" || ext == "wav" else { throw invalidErr("Formato no compatible: usa archivos FLAC o WAV.") }

            let audioFile = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = audioFile.processingFormat
            let length = audioFile.length
            guard length > 0, length <= 30_000_000, (1...2).contains(format.channelCount) else {
                throw invalidErr("Pista inválida o supera el tamaño permitido.")
            }
            totalFrames += length
            longestTrackFrames = max(longestTrackFrames, length)

            guard totalFrames <= 80_000_000 else {
                throw invalidErr("Memoria excedida para esta setlist en el dispositivo.")
            }

            if render == nil {
                sampleRate = format.sampleRate
                render = PulsoRender(rate: UInt32(sampleRate))
            }
            guard format.sampleRate == sampleRate else {
                throw invalidErr("Todas las pistas deben compartir la misma frecuencia de muestreo.")
            }

            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(length)) else {
                throw invalidErr("No se pudo asignar buffer PCM.")
            }
            try audioFile.read(into: pcm)

            let clean = cleanStemName(url.lastPathComponent)
            let isCue = ["click", "guide", "guia", "metronomo", "cue"].contains { clean.lowercased().contains($0) }
            guard render?.add(pcm, index: index, cue: isCue) == true else {
                throw invalidErr("Fallo al registrar la pista en el motor C++.")
            }

            channelItems.append(ChannelItem(
                id: index,
                name: clean,
                db: 0.0,
                muted: false,
                solo: false,
                bus: isCue ? PULSO_BUS_CUE : PULSO_BUS_MASTER,
                rms: 0.0,
                isCueDefault: isCue
            ))

            if importing {
                try files.copyItem(at: url, to: staging.appendingPathComponent("\(index)-\(url.lastPathComponent)"))
            }
        }

        guard let renderInstance = render else { throw invalidErr("No se pudieron inicializar las pistas.") }

        if importing {
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else {
                try files.moveItem(at: staging, to: destination)
            }
        }

        return PreparedSession(renderer: renderInstance, rate: sampleRate, channels: channelItems, maxFrames: longestTrackFrames)
    }

    private nonisolated static func cleanStemName(_ filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension
        if let idx = name.firstIndex(of: "-") {
            let prefix = name[..<idx]
            if Int(prefix) != nil { name = String(name[name.index(after: idx)...]) }
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Stem" : name
    }

    private func setupAudioGraph(_ render: PulsoRender, sampleRate: Double, channels: [ChannelItem], maxFrames: Int64) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(0.005) // 5 ms low latency target
        try session.setActive(true)

        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let source = AVAudioSourceNode(format: format) { _, _, frames, output in
            render.render(frames: Int(frames), output: output)
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        self.output?.stop()
        self.output = nil
        self.renderer = nil

        try engine.start()
        self.output = engine
        self.renderer = render
        self.channels = channels
        self.totalDuration = Double(maxFrames) / sampleRate
        self.setMasterDb(self.masterDb)
    }
}

// MARK: - SwiftUI Show View

struct PulsoShowView: View {
    @ObservedObject var audio: PulsoAudioController
    @State private var showingFilePicker = false
    @State private var showingPadSheet = false
    @State private var showingTransposeSheet = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    // 1. Top Transport Header
                    transportHeader

                    // 2. Main Middle Area (Hero Card & Arranger)
                    HStack(alignment: .top, spacing: 10) {
                        heroCard
                            .frame(width: geo.size.width * 0.44)

                        arrangerAndMixerContainer
                    }
                    .frame(maxHeight: .infinity)

                    // 3. Bottom Control Dock (Pad & Master)
                    bottomBar
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if audio.isLoading {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    ProgressView(audio.statusMessage)
                        .tint(Color(red: 0.96, green: 0.62, blue: 0.04))
                        .padding(24)
                        .background(Color(red: 0.12, green: 0.15, blue: 0.20))
                        .cornerRadius(12)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio, UTType(filenameExtension: "flac") ?? .audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                audio.importFiles(urls)
            }
        }
        .sheet(isPresented: $showingPadSheet) {
            padPickerSheet
        }
        .sheet(isPresented: $showingTransposeSheet) {
            transposeSheet
        }
    }

    // MARK: - Top Transport Header

    private var transportHeader: some View {
        HStack(spacing: 12) {
            // Setlist Pill
            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                Text("SETLIST DOMINGO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.11, green: 0.14, blue: 0.19))
            .cornerRadius(8)

            Spacer()

            // Big Transport Cluster
            HStack(spacing: 14) {
                Button(action: { audio.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(audio.isPlaying ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.18, green: 0.22, blue: 0.29))
                            .frame(width: 44, height: 44)
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(audio.isPlaying ? .black : .white)
                    }
                }

                Button(action: { audio.stop() }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.18, green: 0.22, blue: 0.29))
                            .frame(width: 44, height: 44)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Time Display
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTime(audio.currentSeconds))
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                    Text("/ " + formatTime(audio.totalDuration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.gray)
                }
                .frame(width: 90)

                // Bar & Beat Metronome LEDs
                VStack(spacing: 3) {
                    Text("COMPÁS \(audio.currentBar).\(audio.currentBeat)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))

                    HStack(spacing: 5) {
                        ForEach(1...4, id: \.self) { beat in
                            Circle()
                                .fill(audio.currentBeat == beat ?
                                      (beat == 1 ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color.green) :
                                      Color(red: 0.2, green: 0.25, blue: 0.32))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Import FLAC button
            Button(action: { showingFilePicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Importar FLAC")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(red: 0.14, green: 0.18, blue: 0.24))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.08, green: 0.10, blue: 0.14))
        .cornerRadius(10)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Key / BPM
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(audio.songTitle.uppercased())
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(audio.songArtist.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.6, green: 0.65, blue: 0.75))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: { showingTransposeSheet = true }) {
                        Text(audio.songKey)
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .cornerRadius(6)
                    }

                    Text("\(Int(audio.bpm)) BPM · 4/4")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Current Section Info
            let currentSec = audio.sections.indices.contains(audio.activeSectionIndex) ? audio.sections[audio.activeSectionIndex] : nil
            let nextSec = audio.sections.indices.contains(audio.activeSectionIndex + 1) ? audio.sections[audio.activeSectionIndex + 1] : nil

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SECCIÓN ACTUAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.gray)
                    Text(currentSec?.name ?? "INICIO")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(currentSec?.color ?? Color(red: 0.96, green: 0.62, blue: 0.04))

                    if let next = nextSec {
                        Text("SIGUIENTE: \(next.name)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.gray)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    let remaining = max(0, audio.totalDuration - audio.currentSeconds)
                    Text("-" + formatTime(remaining))
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)

                    Button(action: { audio.toggleSectionLoop() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                            Text("LOOP")
                        }
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(audio.loopSection ? .black : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(audio.loopSection ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.18, green: 0.22, blue: 0.29))
                        .cornerRadius(6)
                    }
                }
            }

            Spacer()

            // Progress Bar
            VStack(spacing: 4) {
                GeometryReader { pGeo in
                    let fraction = audio.totalDuration > 0 ? CGFloat(audio.currentSeconds / audio.totalDuration) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.18, green: 0.22, blue: 0.29))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .frame(width: max(0, min(pGeo.size.width, pGeo.size.width * fraction)))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.10, blue: 0.14))
        .cornerRadius(12)
    }

    // MARK: - Arranger Carousel & Multitrack Mixer

    private var arrangerAndMixerContainer: some View {
        VStack(spacing: 8) {
            // Arranger Sections Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(audio.sections) { sec in
                        let isActive = audio.activeSectionIndex == sec.id
                        Button(action: { audio.jumpToSection(index: sec.id) }) {
                            VStack(spacing: 2) {
                                Text(sec.name)
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundColor(isActive ? .black : .white)
                                Text("C.\(sec.startBar)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isActive ? .black.opacity(0.8) : Color.gray)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isActive ? sec.color : Color(red: 0.12, green: 0.15, blue: 0.20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(sec.color.opacity(0.7), lineWidth: isActive ? 0 : 1.5)
                            )
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)

            // Multitrack Mixer Strips
            if audio.channels.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 32))
                        .foregroundColor(Color.gray)
                    Text("Sin pistas cargadas.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.gray)
                    Button(action: { showingFilePicker = true }) {
                        Text("Cargar FLAC de la canción")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.08, green: 0.10, blue: 0.14))
                .cornerRadius(12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(audio.channels) { ch in
                            ChannelStripView(channel: ch, audio: audio)
                        }
                    }
                    .padding(8)
                }
                .background(Color(red: 0.08, green: 0.10, blue: 0.14))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Ambient Pad Quick Button
            Button(action: { audio.togglePad() }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(audio.padActive ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text("PAD · \(audio.songKey)")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(audio.padActive ? Color(red: 0.96, green: 0.62, blue: 0.04) : .white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(red: 0.14, green: 0.17, blue: 0.23))
                .cornerRadius(8)
            }

            Button(action: { showingPadSheet = true }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Color.gray)
            }

            Spacer()

            // Master Volume
            HStack(spacing: 10) {
                Text("MASTER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.gray)

                Slider(value: Binding(
                    get: { audio.masterDb },
                    set: { audio.setMasterDb($0) }
                ), in: -60...10)
                .tint(Color(red: 0.96, green: 0.62, blue: 0.04))
                .frame(width: 140)

                Text(String(format: "%.1f dB", audio.masterDb))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.08, green: 0.10, blue: 0.14))
        .cornerRadius(10)
    }

    // MARK: - Sheets

    private var padPickerSheet: some View {
        VStack(spacing: 16) {
            Text("AMBIENT CONTINUOUS PAD")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.white)

            let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<notes.count, id: \.self) { idx in
                    let isSelected = audio.padKeyIndex == idx
                    Button(action: { audio.setPadKey(index: idx) }) {
                        Text(notes[idx])
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.16, green: 0.20, blue: 0.28))
                            .cornerRadius(8)
                    }
                }
            }

            Button(action: { audio.togglePad() }) {
                Text(audio.padActive ? "APAGAR PAD" : "ENCENDER PAD")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(audio.padActive ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(audio.padActive ? Color.red : Color(red: 0.96, green: 0.62, blue: 0.04))
                    .cornerRadius(8)
            }
            .padding(.top, 10)
        }
        .padding(24)
        .background(Color(red: 0.09, green: 0.11, blue: 0.15).ignoresSafeArea())
    }

    private var transposeSheet: some View {
        VStack(spacing: 16) {
            Text("TRANSPONER TONALIDAD")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.white)

            let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<notes.count, id: \.self) { idx in
                    let isSelected = audio.songKey == notes[idx]
                    Button(action: {
                        audio.songKey = notes[idx]
                        showingTransposeSheet = false
                    }) {
                        Text(notes[idx])
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSelected ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.16, green: 0.20, blue: 0.28))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(24)
        .background(Color(red: 0.09, green: 0.11, blue: 0.15).ignoresSafeArea())
    }

    private func formatTime(_ sec: Double) -> String {
        let s = Int(max(0, sec))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Channel Strip Component

struct ChannelStripView: View {
    let channel: ChannelItem
    @ObservedObject var audio: PulsoAudioController

    var body: some View {
        VStack(spacing: 6) {
            // Stem Name
            Text(channel.name.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 58)

            // Bus Indicator
            Button(action: { audio.toggleBus(index: channel.id) }) {
                Text(channel.bus == PULSO_BUS_MASTER ? "FOH" : "CUE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(channel.bus == PULSO_BUS_MASTER ? .green : .cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.15, green: 0.18, blue: 0.25))
                    .cornerRadius(4)
            }

            // Fader & Peak Meter
            HStack(spacing: 4) {
                // Peak Meter
                VStack(spacing: 0) {
                    Spacer()
                    let meterHeight: CGFloat = max(0, min(140, CGFloat(channel.rms) * 280))
                    Rectangle()
                        .fill(channel.rms > 0.8 ? Color.red : (channel.rms > 0.5 ? Color.yellow : Color.green))
                        .frame(width: 4, height: meterHeight)
                }
                .frame(width: 4, height: 140)
                .background(Color.black.opacity(0.4))
                .cornerRadius(2)

                // Vertical Fader
                VerticalFader(value: Binding(
                    get: { channel.db },
                    set: { audio.setChannelDb(index: channel.id, db: $0) }
                ))
                .frame(width: 32, height: 140)
            }

            // Numeric dB Readout
            Text(channel.db <= -59.5 ? "-inf" : String(format: "%.1f", channel.db))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.gray)

            // Mute & Solo
            HStack(spacing: 4) {
                Button(action: { audio.toggleMute(index: channel.id) }) {
                    Text("M")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(channel.muted ? .white : Color.gray)
                        .frame(width: 24, height: 22)
                        .background(channel.muted ? Color.red : Color(red: 0.18, green: 0.22, blue: 0.29))
                        .cornerRadius(4)
                }

                Button(action: { audio.toggleSolo(index: channel.id) }) {
                    Text("S")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(channel.solo ? .black : Color.gray)
                        .frame(width: 24, height: 22)
                        .background(channel.solo ? Color.yellow : Color(red: 0.18, green: 0.22, blue: 0.29))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color(red: 0.11, green: 0.13, blue: 0.18))
        .cornerRadius(8)
    }
}

// MARK: - Custom High Performance Vertical Fader

struct VerticalFader: View {
    @Binding var value: Float // -60 to +10 dB

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            // Normalized: 0.0 at bottom (-60 dB), 0.857 at 0 dB, 1.0 at top (+10 dB)
            let normalized = max(0, min(1, (value + 60.0) / 70.0))
            let capY = totalHeight * (1.0 - CGFloat(normalized))

            ZStack(alignment: .top) {
                // Fader Slot Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 4, height: totalHeight)
                    .position(x: geo.size.width / 2, y: totalHeight / 2)

                // 0 dB tick line
                let zeroY = totalHeight * (1.0 - CGFloat(60.0 / 70.0))
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 14, height: 1)
                    .position(x: geo.size.width / 2, y: zeroY)

                // Fader Cap (Tactile thumb)
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.24, green: 0.28, blue: 0.36))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    Rectangle()
                        .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                        .frame(height: 2)
                }
                .frame(width: 28, height: 18)
                .position(x: geo.size.width / 2, y: max(9, min(totalHeight - 9, capY)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let locationY = drag.location.y
                        let fraction = 1.0 - (locationY / totalHeight)
                        let clamped = max(0.0, min(1.0, Float(fraction)))
                        value = (clamped * 70.0) - 60.0
                    }
            )
            .onTapGesture(count: 2) {
                value = 0.0 // Snap to 0 dB on double tap
            }
        }
    }
}

// MARK: - Root NativeShowView (Host for UIKit SceneDelegate)

final class NativeShowView: UIViewController {
    private let audioController = PulsoAudioController()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1.0)

        let hosting = UIHostingController(rootView: PulsoShowView(audio: audioController))
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    override var prefersStatusBarHidden: Bool { true }
}
