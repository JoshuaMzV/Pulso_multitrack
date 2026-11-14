import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

private final class PulsoRender {
    let handle: UnsafeMutableRawPointer
    private let block = 512
    private let scratch: UnsafeMutablePointer<Float>

    init?(rate: UInt32, buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData,
              let engine = pulso_create_engine(rate, 512) else { return nil }
        let right = buffer.format.channelCount == 2 ? channels[1] : channels[0]
        guard pulso_load_stereo(engine, channels[0], right, buffer.frameLength) else {
            pulso_destroy_engine(engine)
            return nil
        }
        handle = engine
        scratch = .allocate(capacity: 512 * 4)
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

@MainActor
private final class NativeShowModel: ObservableObject {
    @Published var title = "Abre una pista FLAC"
    @Published var message: String?
    @Published var loading = false
    @Published var ready = false
    @Published var master = 0.0
    private var output: AVAudioEngine?
    private var render: PulsoRender?

    var position: Int { render.map { Int(pulso_position($0.handle)) } ?? 0 }

    func load(_ url: URL) async {
        loading = true
        message = nil
        defer { loading = false }
        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
                guard url.pathExtension.lowercased() == "flac", file.length > 0,
                      file.length <= 24_000_000, (1...2).contains(file.processingFormat.channelCount),
                      let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                try file.read(into: pcm)
                guard let render = PulsoRender(rate: UInt32(pcm.format.sampleRate), buffer: pcm),
                      let format = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: 2) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return (render, format)
            }.value
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            let next = AVAudioEngine()
            let renderer = decoded.0
            let source = AVAudioSourceNode(format: decoded.1) { _, _, frames, output in
                renderer.render(frames: Int(frames), output: output)
            }
            next.attach(source)
            next.connect(source, to: next.mainMixerNode, format: decoded.1)
            output?.stop()
            ready = false
            try next.start()
            output = next
            render = renderer
            title = url.lastPathComponent
            ready = true
            updateMaster()
        } catch {
            message = "No se pudo abrir el FLAC o iniciar la salida de audio."
        }
    }

    func play() { if ready, let render { pulso_play(render.handle) } }
    func pause() { if let render { pulso_pause(render.handle) } }
    func stop() { if let render { pulso_stop(render.handle) } }
    func updateMaster() {
        if let render { pulso_set_master_gain(render.handle, Float(pow(10.0, master / 20))) }
    }
}

@MainActor
struct NativeShowView: View {
    @StateObject private var player = NativeShowModel()
    @State private var picking = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PULSO · Show").font(.largeTitle.bold())
            Text(player.title)
            Button(player.loading ? "Cargando…" : "Abrir FLAC") { picking = true }
                .disabled(player.loading)
            if let message = player.message { Text(message).foregroundColor(.red) }
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(String(format: "%d:%02d", player.position / 60, player.position % 60))
                    .monospacedDigit()
            }
            HStack {
                Button("Reproducir", action: player.play)
                Button("Pausa", action: player.pause)
                Button("Detener", action: player.stop)
            }.buttonStyle(.bordered).disabled(!player.ready || player.loading)
            Text(String(format: "Master %.1f dB", player.master))
            Slider(value: $player.master, in: -60...10)
                .accessibilityLabel("Master")
                .disabled(!player.ready)
                .onChange(of: player.master) { _ in player.updateMaster() }
        }
        .padding()
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: phase) { if $0 != .active { player.pause() } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "flac") ?? .audio]) {
            if case .success(let url) = $0 { Task { await player.load(url) } }
        }
    }
}
