import Foundation
import AVFoundation
import Accelerate

/// Motor de audio nativo multitrack sincronizado con AVAudioEngine
@MainActor
final class MultitrackAudioEngine: ObservableObject {
    static let shared = MultitrackAudioEngine()

    private let engine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]
    private var durationPerStem: [String: Double] = [:]

    @Published var isPlaying: Bool = false
    @Published var hasLoadedTracks: Bool = false
    @Published var waveformPeaks: [String: [Float]] = [:]

    /// Posición base y niveles RMS sin @Published para evitar re-renderizar SwiftUI en cada fotograma
    private(set) var currentSeconds: Double = 0.0

    var liveSeconds: Double {
        guard isPlaying, let node = clockNode, let render = node.lastRenderTime,
              let player = node.playerTime(forNodeTime: render), player.sampleRate > 0 else {
            return currentSeconds
        }
        return min(songDuration, currentSeconds + max(0, Double(player.sampleTime) / player.sampleRate))
    }

    func meterSnapshot() -> [String?: Float] {
        peakLock.lock()
        defer { peakLock.unlock() }
        let snapshot = pendingPeaks
        pendingPeaks.removeAll(keepingCapacity: true)
        return snapshot
    }

    var onSongDurationDetected: ((Double) -> Void)?
    private let peakLock = NSLock()
    private var pendingPeaks: [String?: Float] = [:]
    private(set) var missingTracks: [String] = []
    private var hasMasterTap = false
    private var songDuration: Double = 240.0
    private var clockNode: AVAudioPlayerNode?
    private let transportQueue = DispatchQueue(label: "pulso.transport", qos: .userInitiated)
    private var pendingStart: DispatchWorkItem?
    private var transportRevision: UInt = 0
    private var waveformRevision: UInt = 0
    private let waveformQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        return queue
    }()

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        } catch {
            print("[PULSO AUDIO] Error configurando AVAudioSession: \(error)")
        }
    }

    /// Prepara y conecta todas las pistas de audio de la canción desde almacenamiento local
    func loadSongTracks(folderName: String, stems: [StemItem], duration: Double) {
        stop()

        missingTracks = stems.map { $0.label }
        waveformQueue.cancelAllOperations()
        waveformRevision &+= 1
        waveformPeaks.removeAll()

        // Limpiar nodos previos
        for (id, node) in playerNodes {
            node.removeTap(onBus: 0)
            node.stop()
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        playerNodes.removeAll()
        audioFiles.removeAll()
        durationPerStem.removeAll()
        peakLock.lock()
        pendingPeaks.removeAll()
        peakLock.unlock()

        self.songDuration = duration
        self.currentSeconds = 0.0

        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidateDirs = [
            docDir.appendingPathComponent("Songs").appendingPathComponent(folderName),
            docDir.appendingPathComponent("Songs").appendingPathComponent(folderName.replacingOccurrences(of: " ", with: "_")),
            docDir.appendingPathComponent("Songs").appendingPathComponent(folderName.replacingOccurrences(of: "_", with: " "))
        ]

        var resolvedDir: URL?
        for dir in candidateDirs {
            if FileManager.default.fileExists(atPath: dir.path) {
                resolvedDir = dir
                break
            }
        }

        guard let songDir = resolvedDir else {
            print("[PULSO AUDIO] Carpeta no encontrada para canción: \(folderName)")
            self.hasLoadedTracks = false
            return
        }

        // Buscar archivos para cada stem
        guard var dirContents = try? FileManager.default.subpathsOfDirectory(atPath: songDir.path) else {
            self.hasLoadedTracks = false
            return
        }

        let audioExts = ["flac", "wav", "mp3", "m4a", "aac", "aiff"]

        for stem in stems {
            // Candidatos de nombre de archivo para este stem
            var candidateFilenames: [String] = []
            if let f = stem.filename {
                candidateFilenames.append(f)
                candidateFilenames.append((f as NSString).lastPathComponent)
            }
            if let o = stem.original {
                candidateFilenames.append(o)
            }
            candidateFilenames.append("\(stem.label).wav")
            candidateFilenames.append("\(stem.label).mp3")
            candidateFilenames.append("\(stem.label).flac")
            candidateFilenames.append("\(stem.label).m4a")
            candidateFilenames.append("\(stem.id).wav")
            candidateFilenames.append("\(stem.id).mp3")
            candidateFilenames.append("\(stem.id).flac")
            candidateFilenames.append("\(stem.id).m4a")

            // Aliases específicos por categoría o etiqueta
            let cat = stem.category.lowercased()
            let lab = stem.label.lowercased()
            if cat == "click" || lab.contains("click") {
                candidateFilenames.append("Click Track.wav")
                candidateFilenames.append("Click Track.mp3")
                candidateFilenames.append("Click Track.m4a")
                candidateFilenames.append("Click.wav")
                candidateFilenames.append("Click.mp3")
            } else if cat == "drums" || lab.contains("drum") || lab.contains("bater") {
                candidateFilenames.append("Drums (Live).wav")
                candidateFilenames.append("Drums (Live).mp3")
                candidateFilenames.append("Drums.wav")
                candidateFilenames.append("Drums.mp3")
                candidateFilenames.append("Bateria.mp3")
            } else if cat == "keys" || lab.contains("key") || lab.contains("teclado") {
                candidateFilenames.append("Keys 1.wav")
                candidateFilenames.append("Keys 1.mp3")
                candidateFilenames.append("Keys.wav")
                candidateFilenames.append("Teclados 1.mp3")
            } else if lab.contains("piano") {
                candidateFilenames.append("Piano.wav")
                candidateFilenames.append("Piano.mp3")
            } else if cat == "pad" || lab.contains("pad") || lab.contains("string") {
                candidateFilenames.append("Strings.wav")
                candidateFilenames.append("Strings.mp3")
                candidateFilenames.append("Pad.wav")
                candidateFilenames.append("Pad.mp3")
            } else if cat == "guitars" || lab.contains("eg") || lab.contains("guitar") {
                candidateFilenames.append("EG 1.wav")
                candidateFilenames.append("EG 2.wav")
                candidateFilenames.append("EG 1.mp3")
                candidateFilenames.append("EG 2.mp3")
                candidateFilenames.append("Electrica 1.mp3")
                candidateFilenames.append("Electrica 2.mp3")
            } else if cat == "bass" || lab.contains("bajo") {
                candidateFilenames.append("Bass.wav")
                candidateFilenames.append("Bass.mp3")
                candidateFilenames.append("Bajo.mp3")
            } else if cat == "guide" || lab.contains("guia") || lab.contains("gu\u{00ed}a") {
                candidateFilenames.append("Guide.wav")
                candidateFilenames.append("Guide.mp3")
            } else if lab.contains("horn") || lab.contains("metal") {
                candidateFilenames.append("Horns.wav")
                candidateFilenames.append("Horns.mp3")
            } else if lab.contains("loop") {
                candidateFilenames.append("Loop.wav")
                candidateFilenames.append("Loop.mp3")
            }

            let declared = [stem.filename, stem.original].compactMap { $0 }.filter { !$0.isEmpty }
            if !declared.isEmpty { candidateFilenames = declared }
            var fileURL: URL?
            for candidate in candidateFilenames {
                let lowerCand = candidate.lowercased()
                let basename = (lowerCand as NSString).lastPathComponent
                if let matched = dirContents.first(where: { $0.lowercased() == lowerCand }) ??
                    dirContents.first(where: { ($0 as NSString).lastPathComponent.lowercased() == basename }) {
                    fileURL = songDir.appendingPathComponent(matched)
                    break
                }
            }

            // Búsqueda por categoría o etiqueta si no hubo match directo
            if fileURL == nil && declared.isEmpty {
                let stemCat = stem.category.lowercased()
                let stemLab = stem.label.lowercased()
                if let matched = dirContents.first(where: { f in
                    let nameNoExt = (f as NSString).deletingPathExtension.lowercased()
                    let ext = (f as NSString).pathExtension.lowercased()
                    return audioExts.contains(ext) && (nameNoExt.contains(stemCat) || nameNoExt.contains(stemLab))
                }) {
                    fileURL = songDir.appendingPathComponent(matched)
                }
            }

            guard let url = fileURL else {
                print("[PULSO AUDIO] Archivo no encontrado para stem \(stem.label) (\(stem.id))")
                continue
            }

            do {
                let audioFile = try AVAudioFile(forReading: url)
                dirContents.removeAll { songDir.appendingPathComponent($0) == url }
                let playerNode = AVAudioPlayerNode()

                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)

                installPeakTap(on: playerNode, id: stem.id)
                playerNodes[stem.id] = playerNode
                audioFiles[stem.id] = audioFile
                let durationSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
                durationPerStem[stem.id] = durationSeconds

                // Aplicar ganancia inicial
                updateVolume(stem: stem, soloActive: false)

                // Extraer forma de onda real en segundo plano
                extractWaveformPeaks(stemId: stem.id, url: url)
            } catch {
                print("[PULSO AUDIO] Error cargando pista \(stem.label) (\(url.lastPathComponent)): \(error)")
            }
        }

        missingTracks = stems.filter { playerNodes[$0.id] == nil }.map { $0.label }
        self.hasLoadedTracks = !playerNodes.isEmpty && missingTracks.isEmpty

        // Detección precisa de la duración máxima de los stems
        if let maxDuration = durationPerStem.values.max(), maxDuration > 1.0 {
            self.songDuration = maxDuration
            self.onSongDurationDetected?(maxDuration)
            print("[PULSO AUDIO] Duración real detectada de pistas: \(String(format: "%.1f", maxDuration)) segundos.")
        }

        // Iniciar el motor de audio si está listo
        if hasLoadedTracks {
            if !hasMasterTap {
                installPeakTap(on: engine.mainMixerNode, id: nil)
                hasMasterTap = true
            }
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                print("[PULSO AUDIO] Motor preparado con \(playerNodes.count) pistas cargadas con éxito.")
            } catch {
                print("[PULSO AUDIO] Error iniciando AVAudioEngine: \(error)")
            }
        }
    }

    private func installPeakTap(on node: AVAudioNode, id: String?) {
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self, let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                var channelPeak: Float = 0
                vDSP_maxmgv(data[channel], vDSP_Stride(buffer.stride), &channelPeak, vDSP_Length(buffer.frameLength))
                peak = max(peak, channelPeak)
            }
            self.peakLock.lock()
            self.pendingPeaks[id] = max(self.pendingPeaks[id] ?? 0, peak)
            self.peakLock.unlock()
        }
    }

    /// Inicia reproducción sincronizada de todos los stems
    func play() {
        guard hasLoadedTracks else { return }

        do {
            if !engine.isRunning {
                try engine.start()
            }

            invalidateStart()
            let revision = transportRevision
            let position = currentSeconds
            let tracks = playerNodes.compactMap { id, node in
                audioFiles[id].map { (node, $0) }
            }
            let reference = durationPerStem.max { $0.value < $1.value }.flatMap { playerNodes[$0.key] }
            // Margen amplio tras prepare() para que todos los stems (incl. MP3) reciban play(at:) antes del arranque.
            let lead = max(0.14, 6 * AVAudioSession.sharedInstance().ioBufferDuration)
            isPlaying = true
            let work = DispatchWorkItem { [weak self] in
                var scheduled: [AVAudioPlayerNode] = []
                for (node, _) in tracks { node.stop() }
                for (node, file) in tracks {
                    let frame = AVAudioFramePosition(round(position * file.processingFormat.sampleRate))
                    guard frame < file.length else { continue }
                    let remaining = file.length - frame
                    node.scheduleSegment(file, startingFrame: frame,
                                         frameCount: AVAudioFrameCount(remaining), at: nil)
                    node.prepare(withFrameCount: AVAudioFrameCount(min(32768, remaining)))
                    scheduled.append(node)
                }
                // Calcular anchor DESPUÉS de preparar todos los buffers para arranque sample-accurate simultáneo.
                let anchor = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead)
                let time = AVAudioTime(hostTime: anchor)
                for node in scheduled { node.play(at: time) }
                DispatchQueue.main.async {
                    guard let self = self, self.transportRevision == revision else { return }
                    self.clockNode = reference
                    self.pendingStart = nil
                }
            }
            pendingStart = work
            transportQueue.async(execute: work)
        } catch {
            print("[PULSO AUDIO] Fallo al reproducir: \(error)")
        }
    }

    /// Pausa la reproducción conservando la posición exacta
    func pause() {
        self.currentSeconds = self.liveSeconds
        invalidateStart()
        let nodes = Array(playerNodes.values)
        transportQueue.async { for node in nodes { node.pause() } }
        self.isPlaying = false
    }

    /// Detiene y rebobina a 0
    func stop() {
        invalidateStart()
        let nodes = Array(playerNodes.values)
        transportQueue.sync { for node in nodes { node.stop() } }
        self.isPlaying = false
        self.currentSeconds = 0.0

        peakLock.lock()
        pendingPeaks.removeAll()
        peakLock.unlock()
    }

    /// Salta instantáneamente a una posición en segundos
    func seek(to seconds: Double) {
        let clamped = max(0.0, min(songDuration, seconds))
        self.currentSeconds = clamped

        if isPlaying {
            play()
        }
    }

    /// Actualización directa de volumen para fader de alta fluidez (sin latencia de bindings)
    func updateVolumeDirect(stemId: String, gainDb: Float, muted: Bool, solo: Bool, anySolo: Bool) {
        guard let node = playerNodes[stemId] else { return }
        if muted || (anySolo && !solo) {
            node.volume = 0.0
        } else {
            let gain = pow(10.0, gainDb / 20.0)
            node.volume = Float(gain)
        }
    }

    /// Actualiza volumen, mute y solo de un stem individual
    func updateVolume(stem: StemItem, soloActive: Bool) {
        guard let node = playerNodes[stem.id] else { return }

        if stem.muted {
            node.volume = 0.0
        } else if soloActive && !stem.solo {
            node.volume = 0.0
        } else {
            // Conversión de dB a ganancia lineal (0 dB = 1.0, -6 dB = 0.5)
            let gain = pow(10.0, stem.gainDb / 20.0)
            node.volume = Float(gain)
        }
    }

    /// Actualiza el volumen Master
    func setMasterDb(_ db: Float) {
        let gain = pow(10.0, db / 20.0)
        engine.mainMixerNode.outputVolume = Float(gain)
    }

    /// Extrae los peaks reales de amplitud PCM para representar la forma de onda
    private func extractWaveformPeaks(stemId: String, url: URL, targetPoints: Int = 220) {
        let revision = waveformRevision
        waveformQueue.addOperation { [weak self] in
            guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return }
            let totalFrames = file.length
            let framesPerSegment = max(1, totalFrames / Int64(targetPoints))
            let chunkSize = AVAudioFrameCount(min(framesPerSegment, 1024))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkSize) else {
                return
            }

            var peaks: [Float] = []
            peaks.reserveCapacity(targetPoints)

            for i in 0..<targetPoints {
                let framePos = min(totalFrames - Int64(chunkSize), Int64(i) * framesPerSegment)
                file.framePosition = max(0, framePos)

                do {
                    try file.read(into: buffer, frameCount: chunkSize)
                    guard let channelData = buffer.floatChannelData else {
                        peaks.append(0.0)
                        continue
                    }
                    let count = Int(buffer.frameLength)
                    var maxAmp: Float = 0.0
                    let ptr = channelData[0]
                    for j in 0..<count {
                        let absVal = abs(ptr[j])
                        if absVal > maxAmp { maxAmp = absVal }
                    }
                    peaks.append(min(1.0, maxAmp * 1.6))
                } catch {
                    peaks.append(0.0)
                }
            }

            let result = peaks
            DispatchQueue.main.async {
                guard let self = self, self.waveformRevision == revision else { return }
                self.waveformPeaks[stemId] = result
            }
        }
    }

    private func invalidateStart() {
        transportRevision &+= 1
        pendingStart?.cancel()
        pendingStart = nil
        clockNode = nil
    }
}
