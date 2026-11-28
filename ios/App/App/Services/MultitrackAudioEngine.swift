import Foundation
import AVFoundation
import Accelerate
import os

/// Candado por archivo para la conversión PCM: evita que la precarga y la carga activa
/// escriban el mismo `.caf.tmp` a la vez. Espera de forma asíncrona (no bloquea hilos del pool).
actor PCMConversionGate {
    static let shared = PCMConversionGate()
    private var busy: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ key: String) async {
        guard busy.contains(key) else {
            busy.insert(key)
            return
        }
        // La propiedad del candado se transfiere directamente en release()
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }

    func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            next.resume()
        } else {
            busy.remove(key)
        }
    }
}

/// Motor de audio multitrack sample-locked con pre-decodificación PCM (.caf) y mezcla SIMD (AVAudioSourceNode + vDSP)
@MainActor
final class MultitrackAudioEngine: ObservableObject {
    static let shared = MultitrackAudioEngine()

    static let sampleRate: Double = 44100.0

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var deck: MultitrackDeck?
    private var stemIds: [String] = []
    private var stemIndexById: [String: Int] = [:]
    private var stemMixState: [String: (gainDb: Float, muted: Bool, solo: Bool)] = [:]
    private var masterDbValue: Float = 0.0

    @Published var isPlaying: Bool = false
    @Published var hasLoadedTracks: Bool = false
    @Published var isPreparingAudio: Bool = false
    /// Avance 0…1 de la preparación PCM de la canción en carga
    @Published var preparingProgress: Double = 0
    @Published var waveformPeaks: [String: [Float]] = [:]

    /// Posición en segundos sin @Published para no invalidar SwiftUI en cada fotograma
    private(set) var currentSeconds: Double = 0.0

    var liveSeconds: Double {
        guard let deck = deck else { return currentSeconds }
        if isPlaying {
            let frames = deck.currentReadFrame()
            return min(songDuration, max(0.0, Double(frames) / Self.sampleRate))
        }
        return currentSeconds
    }

    func meterSnapshot() -> [String?: Float] {
        guard let deck = deck else { return [:] }
        return deck.consumePeaks(stemIds: stemIds)
    }

    var onSongDurationDetected: ((Double) -> Void)?
    private(set) var missingTracks: [String] = []
    private var songDuration: Double = 240.0
    private var loadRevision: UInt = 0
    private var endCheckTimer: Timer?

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(Self.sampleRate)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
        } catch {
            print("[PULSO AUDIO] Error configurando AVAudioSession: \(error)")
        }
    }

    /// Conversión PCM protegida por el candado del archivo destino
    nonisolated static func convertGated(sourceURL: URL, cafURL: URL, peaksURL: URL) async -> [Float] {
        let key = cafURL.standardizedFileURL.path
        await PCMConversionGate.shared.acquire(key)
        let peaks = convertToUniformPCMIfNeeded(sourceURL: sourceURL, cafURL: cafURL, peaksURL: peaksURL)
        await PCMConversionGate.shared.release(key)
        return peaks
    }

    /// Pre-decodifica en segundo plano los stems descargados a .caf PCM uniforme (tipo shader cache).
    /// Va stem por stem para no competir con la UI ni con la carga activa en iPads antiguos,
    /// y se detiene entre stems si la tarea se cancela.
    nonisolated static func prewarmSongCache(folderName: String, stems: [StemItem]) async {
        guard let songDir = resolveSongDirectory(folderName: folderName) else { return }
        guard var remaining = try? FileManager.default.contentsOfDirectory(atPath: songDir.path) else { return }
        let pcmDir = songDir.appendingPathComponent(".pulso_pcm")
        try? FileManager.default.createDirectory(at: pcmDir, withIntermediateDirectories: true)

        for stem in stems {
            if Task.isCancelled { return }
            guard let url = findStemSourceURL(stem: stem, songDir: songDir, dirContents: &remaining) else { continue }
            let cafURL = pcmDir.appendingPathComponent("\(stem.id).caf")
            let peaksURL = pcmDir.appendingPathComponent("\(stem.id).peaks")
            _ = await convertGated(sourceURL: url, cafURL: cafURL, peaksURL: peaksURL)
        }
    }

    /// Prepara y conecta todas las pistas de audio de la canción desde almacenamiento local
    func loadSongTracks(folderName: String, stems: [StemItem], duration: Double) {
        stop()
        loadRevision &+= 1
        let revision = loadRevision

        teardownDeck()
        waveformPeaks.removeAll()
        stemIds = stems.map { $0.id }
        stemIndexById = Dictionary(uniqueKeysWithValues: stems.enumerated().map { ($0.element.id, $0.offset) })
        stemMixState.removeAll()
        for stem in stems {
            stemMixState[stem.id] = (stem.gainDb, stem.muted, stem.solo)
        }
        missingTracks = stems.map { $0.label }
        self.songDuration = duration
        self.currentSeconds = 0.0
        self.hasLoadedTracks = false

        guard let songDir = Self.resolveSongDirectory(folderName: folderName),
              var dirContents = try? FileManager.default.contentsOfDirectory(atPath: songDir.path) else {
            print("[PULSO AUDIO] Carpeta no encontrada para canción: \(folderName)")
            self.isPreparingAudio = false
            return
        }

        var resolvedPairs: [(index: Int, stem: StemItem, sourceURL: URL)] = []
        for (idx, stem) in stems.enumerated() {
            if let url = Self.findStemSourceURL(stem: stem, songDir: songDir, dirContents: &dirContents) {
                resolvedPairs.append((idx, stem, url))
            } else {
                print("[PULSO AUDIO] Archivo no encontrado para stem \(stem.label) (\(stem.id))")
            }
        }

        missingTracks = stems.filter { s in !resolvedPairs.contains(where: { $0.stem.id == s.id }) }.map { $0.label }
        guard !resolvedPairs.isEmpty else {
            self.isPreparingAudio = false
            return
        }

        let resolvedStemIds = resolvedPairs.map { $0.stem.id }
        self.stemIds = resolvedStemIds
        self.stemIndexById = Dictionary(uniqueKeysWithValues: resolvedStemIds.enumerated().map { ($0.element, $0.offset) })

        let pcmDir = songDir.appendingPathComponent(".pulso_pcm")
        try? FileManager.default.createDirectory(at: pcmDir, withIntermediateDirectories: true)
        self.preparingProgress = 0
        self.isPreparingAudio = true

        Task.detached(priority: .userInitiated) { [weak self] in
            var preparedMap: [Int: (stem: StemItem, url: URL, peaks: [Float])] = [:]

            await withTaskGroup(of: (Int, StemItem, URL?, [Float]).self) { group in
                for (seqIdx, pair) in resolvedPairs.enumerated() {
                    let cafURL = pcmDir.appendingPathComponent("\(pair.stem.id).caf")
                    let peaksURL = pcmDir.appendingPathComponent("\(pair.stem.id).peaks")
                    group.addTask {
                        let peaks = await Self.convertGated(
                            sourceURL: pair.sourceURL,
                            cafURL: cafURL,
                            peaksURL: peaksURL
                        )
                        let valid = FileManager.default.fileExists(atPath: cafURL.path) ? cafURL : nil
                        return (seqIdx, pair.stem, valid, peaks)
                    }
                }
                let totalToPrepare = Double(max(resolvedPairs.count, 1))
                var completed = 0
                for await (seqIdx, stem, cafURL, peaks) in group {
                    if let url = cafURL {
                        preparedMap[seqIdx] = (stem, url, peaks)
                    }
                    // Publicar onda y avance por stem: la vista se llena progresivamente en vez de quedar vacía
                    completed += 1
                    let progress = Double(completed) / totalToPrepare
                    await MainActor.run { [weak self] in
                        guard let self = self, self.loadRevision == revision else { return }
                        if !peaks.isEmpty { self.waveformPeaks[stem.id] = peaks }
                        self.preparingProgress = progress
                    }
                }
            }

            let orderedPrepared = resolvedPairs.indices.compactMap { preparedMap[$0] }
            var openFiles: [AVAudioFile] = []
            var loadedStems: [StemItem] = []
            var extractedPeaks: [String: [Float]] = [:]
            var maxFrames: AVAudioFramePosition = 0

            for item in orderedPrepared {
                if let af = try? AVAudioFile(forReading: item.url), af.length > 0 {
                    openFiles.append(af)
                    loadedStems.append(item.stem)
                    extractedPeaks[item.stem.id] = item.peaks
                    if af.length > maxFrames { maxFrames = af.length }
                }
            }

            guard !openFiles.isEmpty, maxFrames > 0 else {
                await MainActor.run { [weak self] in
                    guard let self = self, self.loadRevision == revision else { return }
                    self.isPreparingAudio = false
                    self.hasLoadedTracks = false
                }
                return
            }

            let detectedDuration = Double(maxFrames) / Self.sampleRate
            let newDeck = MultitrackDeck(files: openFiles, totalFrames: maxFrames)

            await MainActor.run { [weak self] in
                guard let self = self, self.loadRevision == revision else {
                    newDeck.shutdown()
                    return
                }
                let finalIds = loadedStems.map { $0.id }
                self.stemIds = finalIds
                self.stemIndexById = Dictionary(uniqueKeysWithValues: finalIds.enumerated().map { ($0.element, $0.offset) })
                self.attachDeck(newDeck, stems: loadedStems, detectedDuration: detectedDuration, peaks: extractedPeaks)
            }
        }
    }

    private func attachDeck(_ newDeck: MultitrackDeck, stems: [StemItem], detectedDuration: Double, peaks: [String: [Float]]) {
        self.deck = newDeck
        self.waveformPeaks = peaks
        self.songDuration = detectedDuration
        self.onSongDurationDetected?(detectedDuration)

        // Aplicar ganancias iniciales
        let anySolo = stems.contains(where: { $0.solo })
        for (idx, stem) in stems.enumerated() {
            let state = stemMixState[stem.id] ?? (stem.gainDb, stem.muted, stem.solo)
            let linear: Float = (state.muted || (anySolo && !state.solo)) ? 0.0 : pow(10.0, state.gainDb / 20.0)
            newDeck.setTargetGain(index: idx, linear: linear)
        }
        newDeck.setMasterGain(pow(10.0, masterDbValue / 20.0))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else {
            self.isPreparingAudio = false
            return
        }

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            return newDeck.render(frameCount: frameCount, audioBufferList: audioBufferList)
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.sourceNode = node

        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            self.hasLoadedTracks = true
            self.isPreparingAudio = false
            print("[PULSO AUDIO] Motor sample-locked listo: \(stems.count) stems PCM (\(String(format: "%.1f", detectedDuration))s)")
        } catch {
            print("[PULSO AUDIO] Error iniciando AVAudioEngine: \(error)")
            self.isPreparingAudio = false
        }
    }

    private func teardownDeck() {
        stopEndCheckTimer()
        if engine.isRunning {
            engine.stop()
        }
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        deck?.shutdown()
        deck = nil
    }

    // MARK: - Transporte

    /// Inicia reproducción 100% sample-locked de todos los stems simultáneamente
    func play() {
        guard hasLoadedTracks, let deck = deck else { return }

        do {
            if !engine.isRunning {
                try engine.start()
            }
            let startFrame = AVAudioFramePosition(round(currentSeconds * Self.sampleRate))
            deck.play(fromFrame: startFrame)
            self.isPlaying = true
            startEndCheckTimer()
        } catch {
            print("[PULSO AUDIO] Fallo al reproducir: \(error)")
        }
    }

    /// Pausa conservando la posición exacta de muestra
    func pause() {
        guard let deck = deck else { return }
        self.currentSeconds = self.liveSeconds
        deck.pause()
        self.isPlaying = false
        stopEndCheckTimer()
    }

    /// Detiene y rebobina a 0
    func stop() {
        stopEndCheckTimer()
        deck?.stop()
        self.isPlaying = false
        self.currentSeconds = 0.0
    }

    /// Salta instantáneamente a una posición en segundos manteniendo sincronización absoluta
    func seek(to seconds: Double) {
        let clamped = max(0.0, min(songDuration, seconds))
        self.currentSeconds = clamped
        guard let deck = deck else { return }

        let targetFrame = AVAudioFramePosition(round(clamped * Self.sampleRate))
        if isPlaying {
            deck.play(fromFrame: targetFrame)
        } else {
            deck.seekPaused(toFrame: targetFrame)
        }
    }

    // MARK: - Mezcla sin latencia

    func updateVolumeDirect(stemId: String, gainDb: Float, muted: Bool, solo: Bool, anySolo: Bool) {
        stemMixState[stemId] = (gainDb, muted, solo)
        guard let deck = deck, let idx = stemIndexById[stemId] else { return }
        let linear: Float = (muted || (anySolo && !solo)) ? 0.0 : pow(10.0, gainDb / 20.0)
        deck.setTargetGain(index: idx, linear: linear)
    }

    func updateVolume(stem: StemItem, soloActive: Bool) {
        updateVolumeDirect(stemId: stem.id, gainDb: stem.gainDb, muted: stem.muted, solo: stem.solo, anySolo: soloActive)
    }

    func setMasterDb(_ db: Float) {
        masterDbValue = db
        deck?.setMasterGain(pow(10.0, db / 20.0))
    }

    private func startEndCheckTimer() {
        stopEndCheckTimer()
        endCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                if self.liveSeconds >= self.songDuration {
                    self.stop()
                }
            }
        }
    }

    private func stopEndCheckTimer() {
        endCheckTimer?.invalidate()
        endCheckTimer = nil
    }

    // MARK: - Resolución de archivos y pre-decodificación PCM

    private nonisolated static func resolveSongDirectory(folderName: String) -> URL? {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidateDirs = [
            docDir.appendingPathComponent("Songs").appendingPathComponent(folderName),
            docDir.appendingPathComponent("Songs").appendingPathComponent(folderName.replacingOccurrences(of: " ", with: "_")),
            docDir.appendingPathComponent("Songs").appendingPathComponent(folderName.replacingOccurrences(of: "_", with: " "))
        ]
        return candidateDirs.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private nonisolated static func findStemSourceURL(stem: StemItem, songDir: URL, dirContents: inout [String]) -> URL? {
        let audioExts = ["flac", "wav", "mp3", "m4a", "aac", "aiff"]
        var candidateFilenames: [String] = []
        let declared = [stem.filename, stem.original].compactMap { $0 }.filter { !$0.isEmpty }
        if !declared.isEmpty {
            candidateFilenames = declared
        } else {
            candidateFilenames.append("\(stem.label).wav")
            candidateFilenames.append("\(stem.label).mp3")
            candidateFilenames.append("\(stem.label).flac")
            candidateFilenames.append("\(stem.label).m4a")
            candidateFilenames.append("\(stem.id).wav")
            candidateFilenames.append("\(stem.id).mp3")
            let cat = stem.category.lowercased()
            let lab = stem.label.lowercased()
            if cat == "click" || lab.contains("click") {
                candidateFilenames += ["Click Track.wav", "Click Track.mp3", "Click.wav", "Click.mp3"]
            } else if cat == "drums" || lab.contains("drum") || lab.contains("bater") {
                candidateFilenames += ["Drums (Live).wav", "Drums (Live).mp3", "Drums.wav", "Drums.mp3", "Bateria.mp3"]
            } else if cat == "keys" || lab.contains("key") || lab.contains("teclado") {
                candidateFilenames += ["Keys 1.wav", "Keys 1.mp3", "Keys.wav", "Teclados 1.mp3"]
            } else if lab.contains("piano") {
                candidateFilenames += ["Piano.wav", "Piano.mp3"]
            } else if cat == "pad" || lab.contains("pad") || lab.contains("string") {
                candidateFilenames += ["Strings.wav", "Strings.mp3", "Pad.wav", "Pad.mp3"]
            } else if cat == "guitars" || lab.contains("eg") || lab.contains("guitar") {
                candidateFilenames += ["EG 1.wav", "EG 2.wav", "EG 1.mp3", "EG 2.mp3", "Electrica 1.mp3", "Electrica 2.mp3"]
            } else if cat == "bass" || lab.contains("bajo") {
                candidateFilenames += ["Bass.wav", "Bass.mp3", "Bajo.mp3"]
            } else if cat == "guide" || lab.contains("guia") || lab.contains("guía") {
                candidateFilenames += ["Guide.wav", "Guide.mp3"]
            }
        }

        for candidate in candidateFilenames {
            let lowerCand = candidate.lowercased()
            let basename = (lowerCand as NSString).lastPathComponent
            if let matched = dirContents.first(where: { $0.lowercased() == lowerCand }) ??
                dirContents.first(where: { ($0 as NSString).lastPathComponent.lowercased() == basename }) {
                dirContents.removeAll { $0 == matched }
                return songDir.appendingPathComponent(matched)
            }
        }

        if declared.isEmpty {
            let stemCat = stem.category.lowercased()
            let stemLab = stem.label.lowercased()
            if let matched = dirContents.first(where: { f in
                let nameNoExt = (f as NSString).deletingPathExtension.lowercased()
                let ext = (f as NSString).pathExtension.lowercased()
                return audioExts.contains(ext) && (nameNoExt.contains(stemCat) || nameNoExt.contains(stemLab))
            }) {
                dirContents.removeAll { $0 == matched }
                return songDir.appendingPathComponent(matched)
            }
        }
        return nil
    }

    /// Convierte el stem origen a PCM lineal uniforme (.caf 44.1kHz Int16) y extrae peaks de forma de onda en una sola pasada
    private nonisolated static func convertToUniformPCMIfNeeded(sourceURL: URL, cafURL: URL, peaksURL: URL, targetPoints: Int = 220) -> [Float] {
        let cafSize = (try? FileManager.default.attributesOfItem(atPath: cafURL.path)[.size] as? Int64) ?? 0
        if cafSize > 4096, let af = try? AVAudioFile(forReading: cafURL), af.length > 0 {
            if let data = try? Data(contentsOf: peaksURL),
               let cachedPeaks = try? JSONDecoder().decode([Float].self, from: data),
               !cachedPeaks.isEmpty {
                return cachedPeaks
            }
            let peaks = extractPeaksFast(from: af, targetPoints: targetPoints)
            if let encoded = try? JSONEncoder().encode(peaks) {
                try? encoded.write(to: peaksURL)
            }
            return peaks
        }

        guard let inFile = try? AVAudioFile(forReading: sourceURL) else { return [] }
        let inFormat = inFile.processingFormat
        guard let workFloatFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let converter = AVAudioConverter(from: inFormat, to: workFloatFormat) else {
            return []
        }

        let tmpURL = cafURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmpURL)

        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let inChunk: AVAudioFrameCount = 16384
        let outCapacity = AVAudioFrameCount(Double(inChunk) * (sampleRate / max(8000.0, inFormat.sampleRate)) + 1024)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inChunk),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: workFloatFormat, frameCapacity: outCapacity) else {
            return []
        }

        // Acumulador de peaks durante la conversión (sin doble lectura de disco)
        let estimatedOutFrames = max(1, Int64(Double(inFile.length) * (sampleRate / max(8000.0, inFormat.sampleRate))))
        let framesPerBin = max(1, estimatedOutFrames / Int64(targetPoints))
        var peaks = Array<Float>(repeating: 0.0, count: targetPoints)
        var writtenFrames: Int64 = 0
        var inputDone = false

        // Scope dedicado para cerrar y hacer flush del header CAF antes de mover el archivo
        do {
            let outFile = try AVAudioFile(forWriting: tmpURL, settings: outSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            while !inputDone {
                outBuffer.frameLength = 0
                var convError: NSError?
                let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
                    if inputDone {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    do {
                        try inFile.read(into: inBuffer, frameCount: inChunk)
                        if inBuffer.frameLength == 0 {
                            inputDone = true
                            outStatus.pointee = .endOfStream
                            return nil
                        }
                        outStatus.pointee = .haveData
                        return inBuffer
                    } catch {
                        inputDone = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                }

                if status == .error { break }
                if outBuffer.frameLength > 0 {
                    try? outFile.write(from: outBuffer)
                    if let chData = outBuffer.floatChannelData {
                        let n = Int(outBuffer.frameLength)
                        let ptr = chData[0]
                        var offset = 0
                        while offset < n {
                            let binIdx = min(targetPoints - 1, Int((writtenFrames + Int64(offset)) / framesPerBin))
                            let binEnd = min(n, offset + Int(framesPerBin))
                            var segPeak: Float = 0
                            vDSP_maxmgv(ptr.advanced(by: offset), 1, &segPeak, vDSP_Length(binEnd - offset))
                            peaks[binIdx] = max(peaks[binIdx], min(1.0, segPeak * 1.6))
                            offset = binEnd
                        }
                    }
                    writtenFrames += Int64(outBuffer.frameLength)
                }
                if status == .endOfStream { break }
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return []
        }

        if writtenFrames > 0, FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: cafURL)
            try? FileManager.default.moveItem(at: tmpURL, to: cafURL)
        } else {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        if let encoded = try? JSONEncoder().encode(peaks) {
            try? encoded.write(to: peaksURL)
        }
        return peaks
    }

    private nonisolated static func extractPeaksFast(from file: AVAudioFile, targetPoints: Int) -> [Float] {
        let totalFrames = file.length
        guard totalFrames > 0 else { return [] }
        let framesPerSegment = max(1, totalFrames / Int64(targetPoints))
        let chunkSize = AVAudioFrameCount(min(framesPerSegment, 1024))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkSize) else { return [] }

        var peaks: [Float] = []
        peaks.reserveCapacity(targetPoints)
        for i in 0..<targetPoints {
            file.framePosition = min(max(0, totalFrames - Int64(chunkSize)), Int64(i) * framesPerSegment)
            do {
                try file.read(into: buffer, frameCount: chunkSize)
                if let ch = buffer.floatChannelData, buffer.frameLength > 0 {
                    var maxAmp: Float = 0
                    vDSP_maxmgv(ch[0], 1, &maxAmp, vDSP_Length(buffer.frameLength))
                    peaks.append(min(1.0, maxAmp * 1.6))
                } else {
                    peaks.append(0)
                }
            } catch {
                peaks.append(0)
            }
        }
        return peaks
    }
}

// MARK: - Ring Buffer Lock-Free Multitrack Deck (Cero Drift Entre Stems)

private final class MultitrackDeck: @unchecked Sendable {
    let stemCount: Int
    let totalFrames: Int64
    let ringCapacity: Int = 131_072 // ~2.97s @ 44.1kHz (potencia de 2)
    let ringMask: Int64 = 131_071

    private let files: [AVAudioFile]
    private let leftBuffers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let rightBuffers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let targetGains: UnsafeMutablePointer<Float>
    private let currentGains: UnsafeMutablePointer<Float>
    private let peakLevels: UnsafeMutablePointer<Float>
    private let masterGainPtr: UnsafeMutablePointer<Float>
    private let readCursor: UnsafeMutablePointer<Int64>
    private let writeCursor: UnsafeMutablePointer<Int64>
    private let playingFlag: UnsafeMutablePointer<Int32>
    private let seekingFlag: UnsafeMutablePointer<Int32>
    private let shutdownFlag: UnsafeMutablePointer<Int32>
    private let stateLockPtr: UnsafeMutablePointer<os_unfair_lock_s>
    private let peakLockPtr: UnsafeMutablePointer<os_unfair_lock_s>

    private let readerQueue = DispatchQueue(label: "pulso.pcm.reader", qos: .userInteractive)
    private var readerTimer: DispatchSourceTimer?
    private let readBuffer: AVAudioPCMBuffer
    private let readChunkSize: AVAudioFrameCount = 8192
    private let targetBufferFill: Int64 = 88_200 // 2.0 segundos adelantados

    init(files: [AVAudioFile], totalFrames: AVAudioFramePosition) {
        self.files = files
        self.stemCount = files.count
        self.totalFrames = totalFrames

        self.leftBuffers = .allocate(capacity: stemCount)
        self.rightBuffers = .allocate(capacity: stemCount)
        for i in 0..<stemCount {
            let lPtr = UnsafeMutablePointer<Float>.allocate(capacity: ringCapacity)
            let rPtr = UnsafeMutablePointer<Float>.allocate(capacity: ringCapacity)
            lPtr.initialize(repeating: 0, count: ringCapacity)
            rPtr.initialize(repeating: 0, count: ringCapacity)
            leftBuffers.advanced(by: i).initialize(to: lPtr)
            rightBuffers.advanced(by: i).initialize(to: rPtr)
        }

        self.targetGains = .allocate(capacity: stemCount)
        self.targetGains.initialize(repeating: 1.0, count: stemCount)
        self.currentGains = .allocate(capacity: stemCount)
        self.currentGains.initialize(repeating: 1.0, count: stemCount)
        self.peakLevels = .allocate(capacity: stemCount + 1)
        self.peakLevels.initialize(repeating: 0.0, count: stemCount + 1)

        self.masterGainPtr = .allocate(capacity: 1)
        self.masterGainPtr.initialize(to: 1.0)
        self.readCursor = .allocate(capacity: 1)
        self.readCursor.initialize(to: 0)
        self.writeCursor = .allocate(capacity: 1)
        self.writeCursor.initialize(to: 0)
        self.playingFlag = .allocate(capacity: 1)
        self.playingFlag.initialize(to: 0)
        self.seekingFlag = .allocate(capacity: 1)
        self.seekingFlag.initialize(to: 0)
        self.shutdownFlag = .allocate(capacity: 1)
        self.shutdownFlag.initialize(to: 0)
        self.stateLockPtr = .allocate(capacity: 1)
        self.stateLockPtr.initialize(to: os_unfair_lock_s())
        self.peakLockPtr = .allocate(capacity: 1)
        self.peakLockPtr.initialize(to: os_unfair_lock_s())

        let fmt = AVAudioFormat(standardFormatWithSampleRate: MultitrackAudioEngine.sampleRate, channels: 2)!
        self.readBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: readChunkSize)!

        startReaderLoop()
    }

    deinit {
        for i in 0..<stemCount {
            leftBuffers[i].deallocate()
            rightBuffers[i].deallocate()
        }
        leftBuffers.deallocate()
        rightBuffers.deallocate()
        targetGains.deallocate()
        currentGains.deallocate()
        peakLevels.deallocate()
        masterGainPtr.deallocate()
        readCursor.deallocate()
        writeCursor.deallocate()
        playingFlag.deallocate()
        seekingFlag.deallocate()
        shutdownFlag.deallocate()
        stateLockPtr.deallocate()
        peakLockPtr.deallocate()
    }

    func shutdown() {
        os_unfair_lock_lock(stateLockPtr)
        shutdownFlag.pointee = 1
        playingFlag.pointee = 0
        os_unfair_lock_unlock(stateLockPtr)
        readerTimer?.cancel()
        readerTimer = nil
    }

    func currentReadFrame() -> Int64 {
        os_unfair_lock_lock(stateLockPtr)
        let r = readCursor.pointee
        os_unfair_lock_unlock(stateLockPtr)
        return r
    }

    func setTargetGain(index: Int, linear: Float) {
        guard index >= 0 && index < stemCount else { return }
        targetGains[index] = linear
    }

    func setMasterGain(_ linear: Float) {
        masterGainPtr.pointee = linear
    }

    func consumePeaks(stemIds: [String]) -> [String?: Float] {
        var result: [String?: Float] = [:]
        os_unfair_lock_lock(peakLockPtr)
        for i in 0..<min(stemCount, stemIds.count) {
            result[stemIds[i]] = peakLevels[i]
            peakLevels[i] = 0.0
        }
        result[nil] = peakLevels[stemCount]
        peakLevels[stemCount] = 0.0
        os_unfair_lock_unlock(peakLockPtr)
        return result
    }

    func play(fromFrame frame: AVAudioFramePosition) {
        os_unfair_lock_lock(stateLockPtr)
        seekingFlag.pointee = 1
        playingFlag.pointee = 0
        os_unfair_lock_unlock(stateLockPtr)
        readerQueue.async { [weak self] in
            guard let self = self, self.shutdownFlag.pointee == 0 else { return }
            self.resetAndPrefill(atFrame: frame)
            os_unfair_lock_lock(self.stateLockPtr)
            self.seekingFlag.pointee = 0
            self.playingFlag.pointee = 1
            os_unfair_lock_unlock(self.stateLockPtr)
        }
    }

    func seekPaused(toFrame frame: AVAudioFramePosition) {
        os_unfair_lock_lock(stateLockPtr)
        seekingFlag.pointee = 1
        playingFlag.pointee = 0
        os_unfair_lock_unlock(stateLockPtr)
        readerQueue.async { [weak self] in
            guard let self = self, self.shutdownFlag.pointee == 0 else { return }
            self.resetAndPrefill(atFrame: frame)
            os_unfair_lock_lock(self.stateLockPtr)
            self.seekingFlag.pointee = 0
            os_unfair_lock_unlock(self.stateLockPtr)
        }
    }

    func pause() {
        os_unfair_lock_lock(stateLockPtr)
        playingFlag.pointee = 0
        os_unfair_lock_unlock(stateLockPtr)
    }

    func stop() {
        os_unfair_lock_lock(stateLockPtr)
        playingFlag.pointee = 0
        seekingFlag.pointee = 1
        os_unfair_lock_unlock(stateLockPtr)
        readerQueue.async { [weak self] in
            guard let self = self, self.shutdownFlag.pointee == 0 else { return }
            self.resetAndPrefill(atFrame: 0)
            os_unfair_lock_lock(self.stateLockPtr)
            self.seekingFlag.pointee = 0
            os_unfair_lock_unlock(self.stateLockPtr)
        }
    }

    private func startReaderLoop() {
        let timer = DispatchSource.makeTimerSource(queue: readerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.shutdownFlag.pointee == 0, self.seekingFlag.pointee == 0 else { return }
            self.fillRingBufferIfNeeded()
        }
        readerTimer = timer
        timer.resume()
    }

    private func resetAndPrefill(atFrame frame: Int64) {
        let clamped = max(0, min(totalFrames, frame))
        os_unfair_lock_lock(stateLockPtr)
        readCursor.pointee = clamped
        writeCursor.pointee = clamped
        os_unfair_lock_unlock(stateLockPtr)
        for file in files {
            file.framePosition = min(clamped, file.length)
        }
        // Pre-llenar ~0.74s antes de liberar el audio para arranque instantáneo sin huecos
        let prefillTarget = min(totalFrames, clamped + 32_768)
        while writeCursor.pointee < prefillTarget && shutdownFlag.pointee == 0 {
            if !writeOneChunk() { break }
        }
    }

    private func fillRingBufferIfNeeded() {
        os_unfair_lock_lock(stateLockPtr)
        let r = readCursor.pointee
        let w = writeCursor.pointee
        os_unfair_lock_unlock(stateLockPtr)
        var currentW = w
        while (currentW - r) < targetBufferFill && currentW < totalFrames && shutdownFlag.pointee == 0 {
            if !writeOneChunk() { break }
            currentW = writeCursor.pointee
        }
    }

    @discardableResult
    private func writeOneChunk() -> Bool {
        let w = writeCursor.pointee
        let remainingSong = totalFrames - w
        guard remainingSong > 0 else { return false }
        let chunk = Int(min(Int64(readChunkSize), remainingSong))
        let startSlot = Int(w & ringMask)
        let firstPart = min(chunk, ringCapacity - startSlot)
        let secondPart = chunk - firstPart

        for i in 0..<stemCount {
            let file = files[i]
            let dstL = leftBuffers[i]
            let dstR = rightBuffers[i]
            let fileRemaining = file.length - file.framePosition

            if fileRemaining > 0 {
                let toRead = AVAudioFrameCount(min(Int64(chunk), fileRemaining))
                readBuffer.frameLength = 0
                try? file.read(into: readBuffer, frameCount: toRead)
                let readCount = Int(readBuffer.frameLength)
                if let ch = readBuffer.floatChannelData, readCount > 0 {
                    let srcL = ch[0]
                    let srcR = readBuffer.format.channelCount > 1 ? ch[1] : ch[0]
                    let f1 = min(readCount, firstPart)
                    dstL.advanced(by: startSlot).update(from: srcL, count: f1)
                    dstR.advanced(by: startSlot).update(from: srcR, count: f1)
                    if readCount > f1 {
                        let rem = readCount - f1
                        dstL.update(from: srcL.advanced(by: f1), count: rem)
                        dstR.update(from: srcR.advanced(by: f1), count: rem)
                    }
                    // Rellenar con silencio si este stem terminó antes que la canción
                    if readCount < chunk {
                        zeroRingRange(dstL: dstL, dstR: dstR, startSlot: Int((w + Int64(readCount)) & ringMask), count: chunk - readCount)
                    }
                } else {
                    zeroRingRange(dstL: dstL, dstR: dstR, startSlot: startSlot, count: chunk)
                }
            } else {
                zeroRingRange(dstL: dstL, dstR: dstR, startSlot: startSlot, count: chunk)
            }
            _ = secondPart
        }

        os_unfair_lock_lock(stateLockPtr)
        writeCursor.pointee = w + Int64(chunk)
        os_unfair_lock_unlock(stateLockPtr)
        return true
    }

    private func zeroRingRange(dstL: UnsafeMutablePointer<Float>, dstR: UnsafeMutablePointer<Float>, startSlot: Int, count: Int) {
        let f1 = min(count, ringCapacity - startSlot)
        vDSP_vclr(dstL.advanced(by: startSlot), 1, vDSP_Length(f1))
        vDSP_vclr(dstR.advanced(by: startSlot), 1, vDSP_Length(f1))
        let f2 = count - f1
        if f2 > 0 {
            vDSP_vclr(dstL, 1, vDSP_Length(f2))
            vDSP_vclr(dstR, 1, vDSP_Length(f2))
        }
    }

    /// Callback de tiempo real: mezcla todos los stems en el mismo frame exacto usando vDSP SIMD
    func render(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let outL = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let outR = (abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil) ?? outL
        let count = Int(frameCount)

        vDSP_vclr(outL, 1, vDSP_Length(count))
        if outR != outL {
            vDSP_vclr(outR, 1, vDSP_Length(count))
        }

        guard os_unfair_lock_trylock(stateLockPtr) else { return noErr }
        let isPlay = playingFlag.pointee == 1
        let isSeek = seekingFlag.pointee == 1
        let r = readCursor.pointee
        let w = writeCursor.pointee
        os_unfair_lock_unlock(stateLockPtr)

        guard isPlay, !isSeek, (w - r) >= Int64(count) else { return noErr }

        let startSlot = Int(r & ringMask)
        let firstPart = min(count, ringCapacity - startSlot)
        let secondPart = count - firstPart

        let canLogPeaks = os_unfair_lock_trylock(peakLockPtr)

        for i in 0..<stemCount {
            let target = targetGains[i]
            let prev = currentGains[i]
            let g = prev + (target - prev) * 0.35
            currentGains[i] = abs(target - g) < 0.0001 ? target : g

            if g > 0.0001 {
                var gainVar = g
                let sL = leftBuffers[i]
                let sR = rightBuffers[i]
                vDSP_vsma(sL.advanced(by: startSlot), 1, &gainVar, outL, 1, outL, 1, vDSP_Length(firstPart))
                if outR != outL {
                    vDSP_vsma(sR.advanced(by: startSlot), 1, &gainVar, outR, 1, outR, 1, vDSP_Length(firstPart))
                }
                if secondPart > 0 {
                    vDSP_vsma(sL, 1, &gainVar, outL.advanced(by: firstPart), 1, outL.advanced(by: firstPart), 1, vDSP_Length(secondPart))
                    if outR != outL {
                        vDSP_vsma(sR, 1, &gainVar, outR.advanced(by: firstPart), 1, outR.advanced(by: firstPart), 1, vDSP_Length(secondPart))
                    }
                }
                if canLogPeaks {
                    var p1: Float = 0, p2: Float = 0
                    vDSP_maxmgv(sL.advanced(by: startSlot), 1, &p1, vDSP_Length(firstPart))
                    if secondPart > 0 {
                        vDSP_maxmgv(sL, 1, &p2, vDSP_Length(secondPart))
                    }
                    let stemPeak = max(p1, p2) * g
                    if stemPeak > peakLevels[i] { peakLevels[i] = stemPeak }
                }
            }
        }

        var mGain = masterGainPtr.pointee
        if abs(mGain - 1.0) > 0.0001 {
            vDSP_vsmul(outL, 1, &mGain, outL, 1, vDSP_Length(count))
            if outR != outL {
                vDSP_vsmul(outR, 1, &mGain, outR, 1, vDSP_Length(count))
            }
        }

        if canLogPeaks {
            var mL: Float = 0, mR: Float = 0
            vDSP_maxmgv(outL, 1, &mL, vDSP_Length(count))
            if outR != outL {
                vDSP_maxmgv(outR, 1, &mR, vDSP_Length(count))
            }
            let mPeak = max(mL, mR)
            if mPeak > peakLevels[stemCount] { peakLevels[stemCount] = mPeak }
            os_unfair_lock_unlock(peakLockPtr)
        }

        os_unfair_lock_lock(stateLockPtr)
        if seekingFlag.pointee == 0 {
            readCursor.pointee = r + Int64(count)
        }
        os_unfair_lock_unlock(stateLockPtr)
        return noErr
    }
}
