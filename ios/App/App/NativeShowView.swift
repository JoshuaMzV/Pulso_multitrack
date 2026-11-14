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
    @Published private(set) var duration = 0.0
    private var output: AVAudioEngine?
    private var render: PulsoRender?

    var position: Int { render.map { Int(pulso_position($0.handle)) } ?? 0 }
    var playing: Bool { render.map { pulso_is_playing($0.handle) } ?? false }

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
                return (render, format, Double(pcm.frameLength) / pcm.format.sampleRate)
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
            title = url.deletingPathExtension().lastPathComponent
            duration = decoded.2
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
    @Environment(\.colorScheme) private var scheme

    private var light: Bool { scheme == .light }
    private var accent: Color { light ? Color(red: 0.31, green: 0.42, blue: 0.14) : Color(red: 1, green: 0.68, blue: 0.26) }
    private var surface: Color { light ? Color(red: 0.98, green: 0.97, blue: 0.93) : Color(white: 0.12) }
    private var canvas: Color { light ? Color(red: 0.94, green: 0.93, blue: 0.89) : Color(white: 0.07) }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let elapsed = player.position
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button {
                        if player.playing { player.pause() } else { player.play() }
                    } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .frame(minWidth: 22, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .foregroundColor(light ? .white : .black)
                    .accessibilityLabel(player.playing ? "Pausa" : "Reproducir")
                    .disabled(!player.ready || player.loading)
                    Button(action: player.stop) {
                        Image(systemName: "stop").frame(minWidth: 22, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Detener")
                    .disabled(!player.ready || player.loading)
                    Text(clock(elapsed)).font(.system(.body, design: .monospaced))
                    Spacer()
                    Label("SHOW", systemImage: "bolt.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(accent.opacity(0.18), in: Capsule())
                }
                .padding(10)
                .background(surface, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 12) {
                    Text(player.ready ? player.title.uppercased() : "PULSO")
                        .font(.system(.largeTitle, design: .default).weight(.black))
                        .lineLimit(2)
                    Text(player.ready ? "PISTA LOCAL" : "Selecciona un FLAC para reproducir")
                        .font(.subheadline).foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    HStack(alignment: .bottom) {
                        Button { picking = true } label: {
                            Label(player.loading ? "Cargando…" : "Abrir FLAC", systemImage: "folder")
                        }
                        .buttonStyle(.bordered).disabled(player.loading)
                        Spacer()
                        if player.ready {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(clock(max(0, Int(ceil(player.duration)) - elapsed)))
                                    .font(.system(.largeTitle, design: .monospaced).bold())
                                    .foregroundColor(accent)
                                Text("RESTANTE").font(.caption.bold()).foregroundColor(.secondary)
                            }
                        }
                    }
                    if let message = player.message { Text(message).foregroundColor(.red) }
                    if player.duration > 0 {
                        ProgressView(value: min(Double(elapsed), player.duration), total: player.duration)
                            .tint(accent)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [accent.opacity(0.16), surface, surface],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.25)) }

                HStack(spacing: 14) {
                    Text("MASTER").font(.caption.bold()).tracking(1)
                    Slider(value: $player.master, in: -60...10)
                        .accessibilityLabel("Master")
                        .disabled(!player.ready)
                        .onChange(of: player.master) { _ in player.updateMaster() }
                    Text(String(format: "%.1f dB", player.master))
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(12)
                .background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(16)
            .frame(maxWidth: 1100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas.ignoresSafeArea())
        .onChange(of: phase) { if $0 != .active { player.pause() } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "flac") ?? .audio]) {
            if case .success(let url) = $0 { Task { await player.load(url) } }
        }
    }
}
