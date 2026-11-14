import AVFoundation
import UIKit
import UniformTypeIdentifiers

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


final class NativeShowView: UIViewController, UIDocumentPickerDelegate {
    private var output: AVAudioEngine?
    private var renderer: PulsoRender?
    private var timer: Timer?
    private let titleLabel = UILabel()
    private let status = UILabel()
    private let clock = UILabel()
    private let master = UISlider()
    private let open = UIButton(type: .system)
    private let transport = UIStackView()
    private let io = DispatchQueue(label: "com.pulso.library", qos: .userInitiated)

    private var library: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PulsoStems", isDirectory: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = "PULSO · SHOW"
        titleLabel.font = .systemFont(ofSize: 32, weight: .black)
        status.text = "Importa las pistas FLAC de una canción."
        status.numberOfLines = 0
        clock.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        clock.text = "0:00"
        open.setTitle("Importar pistas FLAC", for: .normal)
        open.addTarget(self, action: #selector(pick), for: .touchUpInside)
        transport.spacing = 14
        for (name, action) in [("Reproducir", #selector(play)), ("Pausa", #selector(pause)), ("Detener", #selector(stop))] {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.addTarget(self, action: action, for: .touchUpInside)
            transport.addArrangedSubview(button)
        }
        master.minimumValue = -60
        master.maximumValue = 10
        master.value = 0
        master.accessibilityLabel = "Master"
        master.addTarget(self, action: #selector(updateMaster), for: .valueChanged)
        let masterLabel = UILabel()
        masterLabel.text = "MASTER"
        let footer = UIStackView(arrangedSubviews: [masterLabel, master])
        footer.spacing = 12
        let stack = UIStackView(arrangedSubviews: [titleLabel, open, status, clock, transport, footer])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            stack.widthAnchor.constraint(equalTo: safe.widthAnchor, multiplier: 0.84),
        ])
        setReady(false)
        let saved = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
        if !saved.isEmpty { load(saved.sorted { $0.lastPathComponent < $1.lastPathComponent }, importing: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, let renderer = self.renderer else { return }
            let seconds = Int(pulso_position(renderer.handle))
            self.clock.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(pause),
            name: UIApplication.willResignActiveNotification, object: nil)
    }

    deinit { timer?.invalidate(); output?.stop() }

    private func setReady(_ ready: Bool) {
        transport.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { $0.isEnabled = ready }
        master.isEnabled = ready
    }

    @objc private func pick() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "flac") ?? .audio])
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        load(urls, importing: true)
    }

    @objc private func play() { if let renderer { pulso_play(renderer.handle) } }
    @objc private func pause() { if let renderer { pulso_pause(renderer.handle) } }
    @objc private func stop() { if let renderer { pulso_stop(renderer.handle) } }
    @objc private func updateMaster() {
        if let renderer { pulso_set_master_gain(renderer.handle, pow(10, master.value / 20)) }
    }

    private func load(_ urls: [URL], importing: Bool) {
        guard !urls.isEmpty else { return }
        pause()
        open.isEnabled = false
        setReady(false)
        status.text = "Cargando pistas…"
        let destination = library
        io.async { [weak self] in
            let result = Result { try Self.prepare(urls, destination: destination, importing: importing) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.open.isEnabled = true
                do {
                    let (render, rate) = try result.get()
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback)
                    try session.setActive(true)
                    let next = AVAudioEngine()
                    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let source = AVAudioSourceNode(format: format) { _, _, frames, output in
                        render.render(frames: Int(frames), output: output)
                    }
                    next.attach(source)
                    next.connect(source, to: next.mainMixerNode, format: format)
                    self.output?.stop()
                    self.output = nil
                    self.renderer = nil
                    try next.start()
                    self.output = next
                    self.renderer = render
                    self.updateMaster()
                    self.setReady(true)
                    self.status.text = "\(urls.count) pistas locales · listas para reproducir"
                } catch {
                    self.setReady(self.renderer != nil)
                    self.status.text = error.localizedDescription
                }
            }
        }
    }

    private static func prepare(_ urls: [URL], destination: URL, importing: Bool) throws -> (PulsoRender, Double) {
        func invalid(_ message: String) -> NSError {
            NSError(domain: "PulsoLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard urls.count <= 64 else { throw invalid("Puedes importar hasta 64 pistas por canción.") }
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        if importing { try files.createDirectory(at: staging, withIntermediateDirectories: true) }
        defer { if importing { try? files.removeItem(at: staging) } }

        var render: PulsoRender?
        var rate = 0.0
        var totalFrames: Int64 = 0
        for (index, url) in urls.enumerated() {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "flac" else { throw invalid("Selecciona archivos FLAC.") }
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            guard file.length > 0, file.length <= 24_000_000, (1...2).contains(format.channelCount) else {
                throw invalid("Usa pistas FLAC mono o estéreo dentro del límite de memoria.")
            }
            totalFrames += file.length
            guard totalFrames <= 40_000_000 else { throw invalid("Esta canción supera el límite de memoria de esta versión.") }
            if render == nil {
                rate = format.sampleRate
                render = PulsoRender(rate: UInt32(rate))
            }
            guard format.sampleRate == rate else { throw invalid("Todas las pistas deben tener la misma frecuencia de muestreo.") }
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(file.length)) else {
                throw invalid("No se pudo reservar memoria para la pista.")
            }
            try file.read(into: pcm)
            let name = url.lastPathComponent.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let cue = ["click", "guide", "guia", "metron"].contains { name.contains($0) }
            guard render?.add(pcm, index: index, cue: cue) == true else { throw invalid("No se pudo cargar una pista.") }
            if importing {
                try files.copyItem(at: url, to: staging.appendingPathComponent("\(index)-\(url.lastPathComponent)"))
            }
        }
        guard let render else { throw invalid("No se encontró audio.") }
        if importing {
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else {
                try files.moveItem(at: staging, to: destination)
            }
        }
        return (render, rate)
    }
}
