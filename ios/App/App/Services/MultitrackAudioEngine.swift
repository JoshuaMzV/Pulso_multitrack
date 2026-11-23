import Foundation
import AVFoundation

/// Motor de audio nativo multitrack sincronizado con AVAudioEngine
@MainActor
final class MultitrackAudioEngine: ObservableObject {
    static let shared = MultitrackAudioEngine()

    private let engine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]
    private var durationPerStem: [String: Double] = [:]

    @Published var isPlaying: Bool = false
    @Published var currentSeconds: Double = 0.0
    @Published var hasLoadedTracks: Bool = false
    @Published var rmsLevels: [String: Float] = [:]
    @Published var masterRmsL: Float = 0.0
    @Published var masterRmsR: Float = 0.0

    private var playbackTimer: Timer?
    private var songDuration: Double = 240.0
    private var startTimeHost: UInt64 = 0
    private var startPlaybackSeconds: Double = 0.0

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
        rmsLevels.removeAll()

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
            candidateFilenames.append("\(stem.id).flac")
            candidateFilenames.append("\(stem.id).mp3")
            candidateFilenames.append("\(stem.id).wav")
            candidateFilenames.append("\(stem.label.lowercased()).mp3")
            candidateFilenames.append("\(stem.label.lowercased()).flac")

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

            guard let url = fileURL else { continue }

            do {
                let audioFile = try AVAudioFile(forReading: url)
                let playerNode = AVAudioPlayerNode()

                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)

                // Instalar tap para medición de nivel RMS real
                let stemId = stem.id
                playerNode.installTap(onBus: 0, bufferSize: 2048, format: audioFile.processingFormat) { [weak self] buffer, _ in
                    guard let channelData = buffer.floatChannelData else { return }
                    let frameLength = Int(buffer.frameLength)
                    guard frameLength > 0 else { return }

                    var sum: Float = 0
                    for i in 0..<frameLength {
                        let sample = channelData[0][i]
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(frameLength))
                    let normalized = min(1.0, rms * 3.5)

                    DispatchQueue.main.async {
                        self?.rmsLevels[stemId] = normalized
                    }
                }

                playerNodes[stem.id] = playerNode
                audioFiles[stem.id] = audioFile
                durationPerStem[stem.id] = Double(audioFile.length) / audioFile.processingFormat.sampleRate

                // Aplicar ganancia inicial
                updateVolume(stem: stem, soloActive: false)
            } catch {
                print("[PULSO AUDIO] Error cargando pista \(stem.label) (\(url.lastPathComponent)): \(error)")
            }
        }

        self.hasLoadedTracks = !playerNodes.isEmpty

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

            let hostTime = mach_absolute_time() + UInt64(0.04 * 1_000_000_000)
            let audioTime = AVAudioTime(hostTime: hostTime)

            for (stemId, node) in playerNodes {
                guard let file = audioFiles[stemId] else { continue }
                let sampleRate = file.processingFormat.sampleRate
                let startFrame = AVAudioFramePosition(currentSeconds * sampleRate)
                let totalFrames = file.length

                if startFrame < totalFrames {
                    let frameCount = AVAudioFrameCount(totalFrames - startFrame)
                    node.stop()
                    node.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil)
                    node.play(at: audioTime)
                }
            }

            self.isPlaying = true
            self.startPlaybackSeconds = currentSeconds
            self.startTimeHost = mach_absolute_time()

            startClockTimer()
        } catch {
            print("[PULSO AUDIO] Fallo al reproducir: \(error)")
        }
    }

    /// Pausa la reproducción
    func pause() {
        for (_, node) in playerNodes {
            node.pause()
        }
        self.isPlaying = false
        stopClockTimer()
    }

    /// Detiene y rebobina a 0
    func stop() {
        for (_, node) in playerNodes {
            node.stop()
        }
        self.isPlaying = false
        self.currentSeconds = 0.0
        stopClockTimer()

        for key in rmsLevels.keys {
            rmsLevels[key] = 0.0
        }
        masterRmsL = 0.0
        masterRmsR = 0.0
    }

    /// Salta instantáneamente a una posición en segundos
    func seek(to seconds: Double) {
        let clamped = max(0.0, min(songDuration, seconds))
        self.currentSeconds = clamped

        if isPlaying {
            play()
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

    private func startClockTimer() {
        stopClockTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.currentSeconds += 0.04

                if self.currentSeconds >= self.songDuration {
                    self.stop()
                    return
                }

                // Master peak calculation a partir de los stems activos
                var activeRmsSum: Float = 0
                for (_, level) in self.rmsLevels {
                    activeRmsSum = max(activeRmsSum, level)
                }
                self.masterRmsL = activeRmsSum
                self.masterRmsR = activeRmsSum
            }
        }
    }

    private func stopClockTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
}
