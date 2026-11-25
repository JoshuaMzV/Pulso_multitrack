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
        guard isPlaying, let anchor = startHostTime else { return currentSeconds }
        let now = mach_absolute_time()
        let elapsed = now > anchor ? AVAudioTime.seconds(forHostTime: now - anchor) : 0
        return min(songDuration, currentSeconds + elapsed)
    }

    func meterSnapshot() -> [String: Float] {
        rmsLock.lock()
        defer { rmsLock.unlock() }
        return rawRmsLevels
    }

    var onSongDurationDetected: ((Double) -> Void)?

    private let rmsLock = NSLock()
    private var rawRmsLevels: [String: Float] = [:]
    private var songDuration: Double = 240.0
    private var startHostTime: UInt64?
    private let transportQueue = DispatchQueue(label: "pulso.transport", qos: .userInitiated)
    private var pendingStart: DispatchWorkItem?
    private var transportRevision: UInt = 0
    private var waveformRevision: UInt = 0
    private let waveformQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PULSO AUDIO] Error configurando AVAudioSession: \(error)")
        }
    }

    /// Prepara y conecta todas las pistas de audio de la canción desde almacenamiento local
    func loadSongTracks(folderName: String, stems: [StemItem], duration: Double) {
        stop()

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
        rmsLock.lock()
        rawRmsLevels.removeAll()
        rmsLock.unlock()

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
        guard let dirContents = try? FileManager.default.contentsOfDirectory(atPath: songDir.path) else {
            self.hasLoadedTracks = false
            return
        }

        let audioExts = ["flac", "wav", "mp3", "m4a", "aac", "aiff"]

        for stem in stems {
            // Candidatos de nombre de archivo para este stem
            var candidateFilenames: [String] = []
            if let f = stem.filename {
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

            var fileURL: URL?
            for candidate in candidateFilenames {
                let lowerCand = candidate.lowercased()
                if let matched = dirContents.first(where: { $0.lowercased() == lowerCand }) {
                    fileURL = songDir.appendingPathComponent(matched)
                    break
                }
            }

            // Búsqueda por categoría o etiqueta si no hubo match directo
            if fileURL == nil {
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
                let playerNode = AVAudioPlayerNode()

                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)

                // Instalar tap con cálculo SIMD (Accelerate vDSP) sin tocar el hilo principal
                let stemId = stem.id
                playerNode.installTap(onBus: 0, bufferSize: 2048, format: audioFile.processingFormat) { [weak self] buffer, _ in
                    guard let channelData = buffer.floatChannelData else { return }
                    let frameLength = Int(buffer.frameLength)
                    guard frameLength > 0 else { return }

                    var rms: Float = 0.0
                    vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameLength))
                    let normalized = min(1.0, rms * 3.5)

                    if let self = self {
                        self.rmsLock.lock()
                        self.rawRmsLevels[stemId] = normalized
                        self.rmsLock.unlock()
                    }
                }

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

        self.hasLoadedTracks = !playerNodes.isEmpty

        // Detección precisa de la duración máxima de los stems
        if let maxDuration = durationPerStem.values.max(), maxDuration > 1.0 {
            self.songDuration = maxDuration
            self.onSongDurationDetected?(maxDuration)
            print("[PULSO AUDIO] Duración real detectada de pistas: \(String(format: "%.1f", maxDuration)) segundos.")
        }

        // Iniciar el motor de audio si está listo
        if hasLoadedTracks {
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
            isPlaying = true
            let work = DispatchWorkItem { [weak self] in
                var scheduled: [AVAudioPlayerNode] = []
                for (node, file) in tracks {
                    node.stop()
                    let frame = AVAudioFramePosition(position * file.processingFormat.sampleRate)
                    guard frame < file.length else { continue }
                    node.scheduleSegment(file, startingFrame: frame,
                                         frameCount: AVAudioFrameCount(file.length - frame), at: nil)
                    scheduled.append(node)
                }
                // El cursor y todos los stems comparten el mismo instante de arranque.
                let anchor = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.04)
                let time = AVAudioTime(hostTime: anchor)
                for node in scheduled { node.play(at: time) }
                DispatchQueue.main.async {
                    guard let self = self, self.transportRevision == revision else { return }
                    self.startHostTime = anchor
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

        rmsLock.lock()
        rawRmsLevels.removeAll()
        rmsLock.unlock()
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
        startHostTime = nil
    }
}
