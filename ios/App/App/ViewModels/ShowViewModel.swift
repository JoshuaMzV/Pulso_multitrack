import SwiftUI
import Combine

enum PulsoViewMode {
    case show
    case edition
}

enum ShowSubmode {
    case stage // Modern hero & arranger (Image 1)
    case mixer // Stems mixer console (Image 2)
}

enum UserRole: String {
    case admin = "ADMIN"
    case leader = "LÍDER"
    case musician = "MÚSICO"
    case guest = "INVITADO"

    static func from(backendRole: String) -> UserRole {
        switch backendRole.lowercased() {
        case "admin": return .admin
        case "director", "lider", "líder": return .leader
        case "user", "miembro", "musico", "músico": return .musician
        default: return .guest
        }
    }
}

struct UserProfile {
    var username: String
    var role: UserRole
    var avatar: String

    static let `default` = UserProfile(username: "admin_josh", role: .admin, avatar: "AD")
}

final class MusicalPosition: ObservableObject {
    @Published private(set) var beatIndex = 0
    @Published var beatsPerBar = 4
    var bar: Int { beatIndex / beatsPerBar + 1 }
    var beat: Int { beatIndex % beatsPerBar + 1 }

    func update(_ index: Int) {
        if beatIndex != index { beatIndex = index }
    }
}

@MainActor
final class ShowViewModel: ObservableObject {
    // Mode
    @Published var mode: PulsoViewMode = .show
    @Published var showSubmode: ShowSubmode = .stage

    // Authentication State & Modal
    @Published var currentUser: UserProfile = .default
    @Published var isLoggedIn: Bool = true
    @Published var showingAuthModal: Bool = false
    @Published var showingUserDropdown: Bool = false
    @Published var isDarkMode: Bool = true

    // Dialogs & Modals
    @Published var showingAddSongModal: Bool = false
    @Published var showingCloudCatalogModal: Bool = false
    @Published var showingArrangerPanel: Bool = false
    @Published var showingTransposeDialog: Bool = false
    @Published var showingSetlistSelectorModal: Bool = false
    @Published var showingLocalFilePicker: Bool = false
    @Published var showingUploadSongWizard: Bool = false

    // Setlists del Servidor
    @Published var availableSetlists: [SetlistItem] = []
    @Published var isLoadingSetlists: Bool = false
    @Published var isSavingSetlist: Bool = false
    @Published var setlistSavedSuccess: Bool = false

    // Cloud Catalog & Downloads
    @Published var cloudCatalog: [CloudSong] = []
    @Published var isLoadingCatalog: Bool = false
    @Published var isDownloadingSong: Bool = false
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedSongIds: Set<String> = []

    // Setlist & Song
    @Published var setlist: SetlistItem = MockSongData.defaultSetlist
    @Published var currentSong: SongItem = MockSongData.song1
    @Published var nextSong: SongItem? = MockSongData.song2

    // Playback State (currentSeconds sin @Published para evitar re-render masivo en 60-120fps)
    @Published var isPlaying: Bool = false
    let musicalPosition = MusicalPosition()
    var currentBar: Int { musicalPosition.bar }
    @Published var activeSectionIndex: Int = 0
    @Published var loopSection: Bool = false
    private var fallbackSeconds: Double = 0.0


    var currentSeconds: Double {
        get {
            MultitrackAudioEngine.shared.hasLoadedTracks
                ? MultitrackAudioEngine.shared.liveSeconds
                : fallbackSeconds
        }
        set {
            fallbackSeconds = newValue
        }
    }

    // Master & Pad
    @Published var masterDb: Float = 0.0 {
        didSet {
            MultitrackAudioEngine.shared.setMasterDb(masterDb)
        }
    }
    @Published var padActive: Bool = false
    @Published var padKey: String = "Bb"

    // Stems for active song
    @Published var stems: [StemItem] = []
    @Published var selectedTrackId: String = "guide"

    // Server Configuration
    @Published var serverURL: String = BackendAPIService.shared.baseURL {
        didSet {
            BackendAPIService.shared.baseURL = serverURL
        }
    }

    // Timer for simulation / playhead if no audio hardware connected yet
    private var timer: Timer?

    private var beatDuration: Double {
        let unit = Int(currentSong.timeSignature.split(separator: "/").last ?? "4") ?? 4
        return 60 / max(1, currentSong.bpm) * 4 / Double(max(1, unit))
    }
    private var barDuration: Double { beatDuration * Double(musicalPosition.beatsPerBar) }
    var timelineBarSpan: Double { max(0.001, currentSong.durationSeconds / barDuration) }
    @Published var transportMessage: String?

    func isSongDownloaded(_ song: SongItem) -> Bool {
        downloadedSongIds.contains(song.id)
    }

    func refreshDownloadedSongsCache() {
        var ids = Set<String>()
        if MultitrackAudioEngine.shared.hasLoadedTracks {
            ids.insert(currentSong.id)
        }
        for s in setlist.songs where s.id != currentSong.id && s.isDownloadedLocally {
            ids.insert(s.id)
        }
        if ids != downloadedSongIds {
            downloadedSongIds = ids
        }
    }

    func formattedPlaybackTime(at seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var formattedPlaybackTime: String {
        formattedPlaybackTime(at: currentSeconds)
    }

    var formattedTotalDuration: String {
        let s = Int(max(0, currentSong.durationSeconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var formattedRemainingTime: String {
        let rem = max(0, currentSong.durationSeconds - currentSeconds)
        let s = Int(rem)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    init() {
        // Sincronizar duración real detectada desde archivos de audio en disco
        MultitrackAudioEngine.shared.onSongDurationDetected = { [weak self] detectedDuration in
            guard let self = self else { return }
            self.currentSong.durationSeconds = detectedDuration
        }
        self.loadSong(MockSongData.song1)
        self.checkSessionWithBackend()
        self.loadSetlistsFromBackend()
    }

    func selectTrack(id: String) {
        selectedTrackId = id
    }

    func loadSong(_ song: SongItem, checkDownload: Bool = true) {
        var loadedSong = song

        // Asegurar que las secciones y stems nunca estén vacíos
        if loadedSong.sections.isEmpty {
            let lowerTitle = loadedSong.title.lowercased()
            if lowerTitle.contains("danzare") || loadedSong.id.contains("danzare") {
                loadedSong.sections = MockSongData.danzareSections
                if loadedSong.stems.isEmpty { loadedSong.stems = MockSongData.danzareStems }
            } else if lowerTitle.contains("se oye") || loadedSong.id.contains("se_oye") {
                loadedSong.sections = MockSongData.seOyeSections
                if loadedSong.stems.isEmpty { loadedSong.stems = MockSongData.seOyeStems }
            } else {
                loadedSong.sections = [
                    SectionItem(id: 0, name: "INTRO", startBar: 1, lengthBars: 8, colorHex: "#3B82F6"),
                    SectionItem(id: 1, name: "VERSO", startBar: 9, lengthBars: 8, colorHex: "#14B8A6"),
                    SectionItem(id: 2, name: "CORO", startBar: 17, lengthBars: 8, colorHex: "#EF4444"),
                    SectionItem(id: 3, name: "PUENTE", startBar: 25, lengthBars: 8, colorHex: "#8B5CF6"),
                    SectionItem(id: 4, name: "FINAL", startBar: 33, lengthBars: 8, colorHex: "#6B7280")
                ]
            }
        } else if loadedSong.stems.isEmpty {
            let lowerTitle = loadedSong.title.lowercased()
            if lowerTitle.contains("danzare") || loadedSong.id.contains("danzare") {
                loadedSong.stems = MockSongData.danzareStems
            } else if lowerTitle.contains("se oye") || loadedSong.id.contains("se_oye") {
                loadedSong.stems = MockSongData.seOyeStems
            }
        }

        musicalPosition.beatsPerBar = max(1, Int(loadedSong.timeSignature.split(separator: "/").first ?? "4") ?? 4)
        self.currentSong = loadedSong
        self.stems = loadedSong.stems
        self.padKey = loadedSong.key
        self.currentSeconds = 0.0
        stopPositionTimer()
        musicalPosition.update(0)
        self.activeSectionIndex = 0
        self.isPlaying = false

        let idx = setlist.songs.firstIndex(where: { $0.id == loadedSong.id }) ?? 0
        setlist.currentIndex = idx
        if idx + 1 < setlist.songs.count {
            nextSong = setlist.songs[idx + 1]
        } else {
            nextSong = nil
        }

        // Cargar pistas en el motor nativo multitrack
        MultitrackAudioEngine.shared.loadSongTracks(
            folderName: loadedSong.folderName,
            stems: loadedSong.stems,
            duration: loadedSong.durationSeconds
        )

        // Si la canción no tiene stems descargados localmente, descargarlos automáticamente
        refreshDownloadedSongsCache()
        if checkDownload && !MultitrackAudioEngine.shared.hasLoadedTracks {
            verifyAndDownloadStemsIfNeeded(for: loadedSong)
        }
    }

    // MARK: - Setlists del Servidor

    func loadSetlistsFromBackend() {
        isLoadingSetlists = true
        Task {
            do {
                let fetched = try await BackendAPIService.shared.fetchSetlists()
                self.availableSetlists = fetched
                self.isLoadingSetlists = false

                // Si hay un setlist guardado en el servidor que coincide con el actual o el primero
                if let match = fetched.first(where: { $0.id == self.setlist.id }) {
                    self.setlist = match
                    if let first = match.songs.first {
                        self.loadSong(first)
                    }
                } else if let firstSetlist = fetched.first, self.setlist.songs.isEmpty || self.setlist.id == "mock-setlist" {
                    self.setlist = firstSetlist
                    if let first = firstSetlist.songs.first {
                        self.loadSong(first)
                    }
                }
            } catch {
                print("[PULSO SETLISTS] Error cargando setlists: \(error)")
                self.isLoadingSetlists = false
            }
        }
    }

    func switchSetlist(to newSetlist: SetlistItem) {
        self.setlist = newSetlist
        if let first = newSetlist.songs.first {
            self.loadSong(first)
        }
        self.showingSetlistSelectorModal = false
    }

    func createNewSetlist(name: String, description: String = "") {
        let newId = "setlist-\(Int(Date().timeIntervalSince1970 * 1000))"
        let newSetlist = SetlistItem(
            id: newId,
            name: name,
            description: description.isEmpty ? nil : description,
            songs: []
        )
        self.availableSetlists.append(newSetlist)
        self.setlist = newSetlist
        self.showingSetlistSelectorModal = false
        Task {
            await self.saveSetlistsToBackend()
        }
    }

    func saveSetlistsToBackend() async {
        isSavingSetlist = true
        setlistSavedSuccess = false

        // Actualizar el setlist actual dentro de availableSetlists
        if let idx = availableSetlists.firstIndex(where: { $0.id == setlist.id }) {
            availableSetlists[idx] = setlist
        } else {
            availableSetlists.append(setlist)
        }

        do {
            try await BackendAPIService.shared.saveSetlists(availableSetlists)
            isSavingSetlist = false
            setlistSavedSuccess = true

            // Ocultar mensaje de guardado tras 2.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.setlistSavedSuccess = false
            }
        } catch {
            print("[PULSO SETLISTS] Error guardando setlists en servidor: \(error)")
            isSavingSetlist = false
        }
    }

    func moveSong(from source: IndexSet, to destination: Int) {
        setlist.songs.move(fromOffsets: source, toOffset: destination)
    }

    func cycleTransition(for songId: String) {
        guard let idx = setlist.songs.firstIndex(where: { $0.id == songId }) else { return }
        let modes = TransitionMode.allCases
        let currentMode = setlist.songs[idx].transition
        let nextIdx = (modes.firstIndex(of: currentMode)! + 1) % modes.count
        setlist.songs[idx].transition = modes[nextIdx]
    }

    func addSection(name: String, colorHex: String = "#3B82F6", startBar: Int? = nil, lengthBars: Int = 8) {
        let bar: Int
        if let sb = startBar {
            bar = max(1, sb)
        } else {
            bar = currentSong.sections.map { $0.startBar + $0.lengthBars }.max() ?? 1
        }
        let nextId = (currentSong.sections.map { $0.id }.max() ?? -1) + 1
        let newSec = SectionItem(
            id: nextId,
            name: name,
            startBar: bar,
            lengthBars: lengthBars,
            colorHex: colorHex
        )
        currentSong.sections.append(newSec)
        currentSong.sections.sort { $0.startBar < $1.startBar }

        if let idx = setlist.songs.firstIndex(where: { $0.id == currentSong.id }) {
            setlist.songs[idx].sections = currentSong.sections
        }
        objectWillChange.send()
    }

    func removeSection(id: Int) {
        currentSong.sections.removeAll { $0.id == id }
        if let idx = setlist.songs.firstIndex(where: { $0.id == currentSong.id }) {
            setlist.songs[idx].sections = currentSong.sections
        }
        objectWillChange.send()
    }

    // MARK: - Navigation

    func nextSongAction() {
        guard let next = nextSong else { return }
        loadSong(next)
    }

    func prevSongAction() {
        let prevIndex = setlist.currentIndex - 1
        guard prevIndex >= 0 && prevIndex < setlist.songs.count else { return }
        loadSong(setlist.songs[prevIndex])
    }

    // MARK: - Transport

    func togglePlayPause() {
        if MultitrackAudioEngine.shared.hasLoadedTracks {
            if isPlaying {
                MultitrackAudioEngine.shared.pause()
                isPlaying = false
                stopPositionTimer()
            } else {
                MultitrackAudioEngine.shared.play()
                isPlaying = MultitrackAudioEngine.shared.isPlaying
                if isPlaying { startPositionTimer() }
            }
        } else {
            transportMessage = "Faltan pistas de esta canción: " + MultitrackAudioEngine.shared.missingTracks.joined(separator: ", ")
        }
    }

    func stop() {
        isPlaying = false
        fallbackSeconds = 0.0
        musicalPosition.update(0)
        activeSectionIndex = 0
        MultitrackAudioEngine.shared.stop()
        stopPositionTimer()
    }

    func jumpToSection(index: Int) {
        guard currentSong.sections.indices.contains(index) else { return }
        activeSectionIndex = index
        let sec = currentSong.sections[index]
        seek(to: Double(sec.startBar - 1) * barDuration)
    }

    func seek(to seconds: Double) {
        let clamped = max(0.0, min(currentSong.durationSeconds, seconds))
        currentSeconds = clamped
        let totalBeats = max(0.0, clamped / beatDuration)
        musicalPosition.update(Int(totalBeats))

        for (idx, sec) in currentSong.sections.enumerated() {
            if currentBar >= sec.startBar && currentBar < (sec.startBar + sec.lengthBars) {
                activeSectionIndex = idx
                break
            }
        }

        if MultitrackAudioEngine.shared.hasLoadedTracks {
            MultitrackAudioEngine.shared.seek(to: clamped)
        }
        objectWillChange.send()
    }

    func toggleLoop() {
        loopSection.toggle()
    }

    func toggleShowMixer() {
        showSubmode = (showSubmode == .stage) ? .mixer : .stage
    }

    func setSongKey(_ newKey: String) {
        currentSong.key = newKey
        padKey = newKey
    }

    // MARK: - Mixer Actions

    func setStemDb(id: String, db: Float) {
        guard let idx = stems.firstIndex(where: { $0.id == id }) else { return }
        stems[idx].gainDb = db
        let soloActive = stems.contains(where: { $0.solo })
        MultitrackAudioEngine.shared.updateVolume(stem: stems[idx], soloActive: soloActive)
    }

    func toggleMute(id: String) {
        guard let idx = stems.firstIndex(where: { $0.id == id }) else { return }
        stems[idx].muted.toggle()
        let soloActive = stems.contains(where: { $0.solo })
        MultitrackAudioEngine.shared.updateVolume(stem: stems[idx], soloActive: soloActive)
    }

    func toggleSolo(id: String) {
        guard let idx = stems.firstIndex(where: { $0.id == id }) else { return }
        stems[idx].solo.toggle()
        let soloActive = stems.contains(where: { $0.solo })
        for stem in stems {
            MultitrackAudioEngine.shared.updateVolume(stem: stem, soloActive: soloActive)
        }
    }

    func toggleBus(id: String) {
        guard let idx = stems.firstIndex(where: { $0.id == id }) else { return }
        stems[idx].bus = stems[idx].bus == 0 ? 1 : 0
    }

    func togglePad() {
        padActive.toggle()
    }

    // MARK: - Auth Actions

    func checkSessionWithBackend() {
        Task {
            do {
                if let serverUser = try await BackendAPIService.shared.checkSession() {
                    self.currentUser = UserProfile(
                        username: serverUser.username,
                        role: serverUser.userRole,
                        avatar: serverUser.avatar
                    )
                    self.isLoggedIn = true
                } else if !BackendAPIService.shared.isAuthenticated {
                    self.isLoggedIn = false
                    self.currentUser = UserProfile(username: "invitado", role: .guest, avatar: "IN")
                }
            } catch {
                print("[PULSO API] Error comprobando sesión previa: \(error)")
            }
        }
    }

    func loginWithBackend(username: String, password: String) async throws {
        let serverUser = try await BackendAPIService.shared.login(username: username, password: password)
        self.currentUser = UserProfile(
            username: serverUser.username,
            role: serverUser.userRole,
            avatar: serverUser.avatar
        )
        self.isLoggedIn = true
    }

    func registerWithBackend(username: String, password: String, inviteCode: String) async throws {
        let serverUser = try await BackendAPIService.shared.register(
            username: username,
            password: password,
            inviteCode: inviteCode
        )
        self.currentUser = UserProfile(
            username: serverUser.username,
            role: serverUser.userRole,
            avatar: serverUser.avatar
        )
        self.isLoggedIn = true
    }

    func login(username: String) {
        let initial = username.prefix(2).uppercased()
        currentUser = UserProfile(username: username, role: .admin, avatar: initial.isEmpty ? "US" : initial)
        isLoggedIn = true
    }

    func logout() {
        Task {
            await BackendAPIService.shared.logout()
        }
        currentUser = UserProfile(username: "invitado", role: .guest, avatar: "IN")
        isLoggedIn = false
    }

    // MARK: - Cloud Catalog & Song Downloading

    /// Elimina los archivos de audio descargados localmente para permitir su re-descarga limpia (sin borrar la canción del setlist)
    func deleteSongLocalCache(for song: SongItem) {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidateFolder = song.folderName
        let cleanTitle = song.title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")

        let candidatePaths = [
            docDir.appendingPathComponent("Songs").appendingPathComponent(candidateFolder),
            docDir.appendingPathComponent("Songs").appendingPathComponent(cleanTitle),
            docDir.appendingPathComponent("Songs").appendingPathComponent(song.id)
        ]

        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.removeItem(at: path)
            }
        }

        if currentSong.id == song.id {
            MultitrackAudioEngine.shared.stop()
            MultitrackAudioEngine.shared.loadSongTracks(folderName: song.folderName, stems: [], duration: song.durationSeconds)
        }

        downloadProgress[song.id] = nil
        refreshDownloadedSongsCache()
        objectWillChange.send()
    }

    /// Carga el catálogo de canciones disponibles en el servidor
    func loadCloudCatalog() async {
        isLoadingCatalog = true
        do {
            let songs = try await BackendAPIService.shared.fetchCatalog()
            self.cloudCatalog = songs
            self.isLoadingCatalog = false
        } catch {
            print("Error cargando catálogo en la nube: \(error)")
            self.isLoadingCatalog = false
        }
    }

    /// Descarga los stems de una canción desde el CDN y la agrega al setlist activo
    func downloadAndAddSong(_ cloudSong: CloudSong) {
        guard !isDownloadingSong else { return }
        let selectionAtStart = currentSong.id
        isDownloadingSong = true
        downloadProgress[cloudSong.id] = 0.05

        Task {
            do {
                let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let folderName = cloudSong.extractedFolder ?? cloudSong.title.replacingOccurrences(of: " ", with: "_")
                let songDir = docDir.appendingPathComponent("Songs").appendingPathComponent(folderName)
                try FileManager.default.createDirectory(at: songDir, withIntermediateDirectories: true)

                var downloadedStems: [StemItem] = []
                let stemsList = cloudSong.stems ?? []
                let total = Double(max(stemsList.count, 1))

                for (index, stem) in stemsList.enumerated() {
                    let stemName = stem.filename ?? stem.original ?? "\(stem.label ?? stem.id).wav"
                    let localStemURL = songDir.appendingPathComponent(stemName)

                    guard localStemURL.standardizedFileURL.path.hasPrefix(songDir.standardizedFileURL.path + "/") else {
                        throw APIError.invalidURL
                    }
                    let size = (try? localStemURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if size <= 1024 {
                        guard let base = URL(string: BackendAPIService.shared.baseURL) else { throw APIError.invalidURL }
                        let remote: URL
                        if let link = stem.url, !link.isEmpty {
                            guard let resolved = URL(string: link.replacingOccurrences(of: " ", with: "%20"), relativeTo: base) else {
                                throw APIError.invalidURL
                            }
                            remote = resolved.absoluteURL
                        } else {
                            remote = base.appendingPathComponent("songs/extracted").appendingPathComponent(folderName).appendingPathComponent(stemName)
                        }
                        try await BackendAPIService.shared.downloadStem(from: remote, to: localStemURL)
                    }

                    let progress = Double(index + 1) / total
                    self.downloadProgress[cloudSong.id] = progress

                    // Determinar categoría y color
                    let cat = (stem.category ?? "other").lowercased()
                    let bus = (cat == "click" || cat == "guide") ? 1 : 0
                    let colorHex: String
                    switch cat {
                    case "click": colorHex = "#9297A0"
                    case "guide": colorHex = "#F0A028"
                    case "drums": colorHex = "#FF4B33"
                    case "bass": colorHex = "#3DDC84"
                    case "keys", "piano": colorHex = "#4DA6FF"
                    case "pad": colorHex = "#B388FF"
                    case "guitars": colorHex = "#FFBE55"
                    default: colorHex = "#C3C7CC"
                    }

                    downloadedStems.append(StemItem(
                        id: stem.id,
                        label: stem.label ?? stem.id.uppercased(),
                        category: cat,
                        colorHex: colorHex,
                        bus: bus,
                        gainDb: 0.0,
                        filename: stemName,
                        original: stem.original ?? stemName,
                        url: stem.url
                    ))
                }

                // Obtener o inferir secciones correspondientes
                let songSections: [SectionItem]
                let lowerTitle = cloudSong.title.lowercased()
                if lowerTitle.contains("se oye") || cloudSong.id.contains("se_oye") {
                    songSections = MockSongData.seOyeSections
                } else if lowerTitle.contains("danzare") || cloudSong.id.contains("danzare") {
                    songSections = MockSongData.danzareSections
                } else {
                    songSections = [
                        SectionItem(id: 0, name: "INTRO", startBar: 1, lengthBars: 8, colorHex: "#3B82F6"),
                        SectionItem(id: 1, name: "VERSO", startBar: 9, lengthBars: 8, colorHex: "#10B981"),
                        SectionItem(id: 2, name: "CORO", startBar: 17, lengthBars: 8, colorHex: "#EF4444")
                    ]
                }

                // Crear SongItem nativo
                let newSong = SongItem(
                    id: cloudSong.id,
                    title: cloudSong.title,
                    artist: cloudSong.artist ?? "Desconocido",
                    bpm: cloudSong.bpm ?? 120.0,
                    key: cloudSong.key ?? "C",
                    timeSignature: cloudSong.timeSignature ?? cloudSong.signature ?? (currentSong.id == cloudSong.id ? currentSong.timeSignature : "4/4"),
                    durationSeconds: self.currentSong.durationSeconds > 0 ? self.currentSong.durationSeconds : 265.0,
                    stems: downloadedStems,
                    sections: songSections,
                    coverUrl: cloudSong.cover,
                    folderId: folderName
                )

                if !self.setlist.songs.contains(where: { $0.id == newSong.id || $0.title == newSong.title }) {
                    self.setlist.songs.append(newSong)
                }
                self.downloadProgress[cloudSong.id] = 1.0
                self.isDownloadingSong = false
                if self.currentSong.id == selectionAtStart {
                    var readySong = newSong
                    if let index = self.setlist.songs.firstIndex(where: { $0.id == newSong.id }) {
                        let saved = self.setlist.songs[index]
                        readySong = saved
                        readySong.folderId = newSong.folderId
                        readySong.stems = newSong.stems.map { downloaded in
                            guard var stem = saved.stems.first(where: { $0.id == downloaded.id }) else { return downloaded }
                            stem.filename = downloaded.filename
                            stem.original = downloaded.original
                            return stem
                        }
                        self.setlist.songs[index] = readySong
                    }
                    self.loadSong(readySong, checkDownload: false)
                } else {
                    Task.detached(priority: .utility) {
                        await MultitrackAudioEngine.prewarmSongCache(folderName: newSong.folderName, stems: newSong.stems)
                    }
                }
                self.refreshDownloadedSongsCache()
            } catch {
                print("Error descargando canción: \(error)")
                self.isDownloadingSong = false
                self.downloadProgress[cloudSong.id] = nil
            }
        }
    }

    /// Verifica si los stems de la canción están en el almacenamiento local; si no, los descarga automáticamente del servidor
    func verifyAndDownloadStemsIfNeeded(for song: SongItem) {
        if song.id == currentSong.id && MultitrackAudioEngine.shared.hasLoadedTracks { return }

        Task {
            if self.cloudCatalog.isEmpty {
                await self.loadCloudCatalog()
            }

            // Buscar la canción en el catálogo del servidor
            if let cloudSong = self.cloudCatalog.first(where: {
                $0.id == song.id || $0.title.lowercased() == song.title.lowercased()
            }) {
                guard self.currentSong.id == song.id else { return }
                self.downloadAndAddSong(cloudSong)
            } else {
                // Descargar stems según la estructura de la canción
                let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let folderName = song.folderName
                let songDir = docDir.appendingPathComponent("Songs").appendingPathComponent(folderName)
                try? FileManager.default.createDirectory(at: songDir, withIntermediateDirectories: true)

                let total = Double(max(song.stems.count, 1))
                for (idx, stem) in song.stems.enumerated() {
                    let stemFilename = stem.filename ?? stem.original ?? "\(stem.label).wav"
                    let localURL = songDir.appendingPathComponent(stemFilename)
                    let existingSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
                    if existingSize <= 1024 {
                        let remoteURLStr = "\(BackendAPIService.shared.baseURL)/songs/extracted/\(folderName)/\(stemFilename)"
                        let safeRemote = remoteURLStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? remoteURLStr
                        if let remoteURL = URL(string: safeRemote) ?? URL(string: remoteURLStr.replacingOccurrences(of: " ", with: "%20")) {
                            try? await BackendAPIService.shared.downloadStem(from: remoteURL, to: localURL)
                        }
                    }
                    self.downloadProgress[song.id] = Double(idx + 1) / total
                }
                self.downloadProgress[song.id] = nil

                guard self.currentSong.id == song.id else { return }
                self.loadSong(song, checkDownload: false)
                self.refreshDownloadedSongsCache()
            }
        }
    }

    // MARK: - Importador Local de Archivos (ZIP / Audio)

    func handleLocalFilesImported(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                let ext = url.pathExtension.lowercased()
                let fileName = url.deletingPathExtension().lastPathComponent
                let cleanTitle = fileName.replacingOccurrences(of: "_", with: " ").capitalized

                let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let folderName = fileName.replacingOccurrences(of: " ", with: "_")
                let songDir = docDir.appendingPathComponent("Songs").appendingPathComponent(folderName)
                try FileManager.default.createDirectory(at: songDir, withIntermediateDirectories: true)

                if ext == "zip" {
                    let zipData = try Data(contentsOf: url)
                    let audioNames = NativeZipInspector.extractAudioFilenames(from: zipData)
                    var importedStems: [StemItem] = []

                    if !audioNames.isEmpty {
                        for (idx, name) in audioNames.enumerated() {
                            let classification = NativeZipInspector.autoClassify(filename: name)
                            let colorHex: String
                            switch classification.category {
                            case "click": colorHex = "#9297A0"
                            case "guide": colorHex = "#F0A028"
                            case "drums": colorHex = "#FF4B33"
                            case "bass": colorHex = "#3DDC84"
                            case "keys": colorHex = "#4DA6FF"
                            case "pad": colorHex = "#B388FF"
                            case "guitars": colorHex = "#FFBE55"
                            case "vocals": colorHex = "#EC4899"
                            default: colorHex = "#C3C7CC"
                            }

                            let destAudioURL = songDir.appendingPathComponent(name)
                            if !FileManager.default.fileExists(atPath: destAudioURL.path) {
                                FileManager.default.createFile(atPath: destAudioURL.path, contents: Data(), attributes: nil)
                            }

                            importedStems.append(StemItem(
                                id: "local_\(idx)_\(classification.label.lowercased())",
                                label: classification.label,
                                category: classification.category,
                                colorHex: colorHex,
                                bus: classification.bus,
                                gainDb: 0.0
                            ))
                        }
                    }

                    let newLocalSong = SongItem(
                        id: "local_\(Int(Date().timeIntervalSince1970))",
                        title: cleanTitle,
                        artist: "Local (iPad)",
                        bpm: 120.0,
                        key: "C",
                        timeSignature: "4/4",
                        durationSeconds: 240.0,
                        stems: importedStems.isEmpty ? MockSongData.song1.stems : importedStems,
                        sections: [
                            SectionItem(id: 1, name: "INTRO", startBar: 1, lengthBars: 8, color: PulsoTheme.amber),
                            SectionItem(id: 2, name: "VERSO", startBar: 9, lengthBars: 8, color: Color(hexString: "#26a69a")),
                            SectionItem(id: 3, name: "CORO", startBar: 17, lengthBars: 8, color: Color(hexString: "#ef5350"))
                        ]
                    )

                    self.setlist.songs.append(newLocalSong)
                    self.loadSong(newLocalSong)
                } else if ["mp3", "wav", "flac", "m4a", "aac"].contains(ext) {
                    let destURL = songDir.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try? FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)

                    let classification = NativeZipInspector.autoClassify(filename: url.lastPathComponent)
                    let newStem = StemItem(
                        id: classification.label.lowercased(),
                        label: classification.label,
                        category: classification.category,
                        colorHex: "#F0A028",
                        bus: classification.bus,
                        gainDb: 0.0
                    )

                    let newLocalSong = SongItem(
                        id: "local_\(Int(Date().timeIntervalSince1970))",
                        title: cleanTitle,
                        artist: "Local (iPad)",
                        bpm: 120.0,
                        key: "C",
                        timeSignature: "4/4",
                        durationSeconds: 200.0,
                        stems: [newStem],
                        sections: [
                            SectionItem(id: 1, name: "INTRO", startBar: 1, lengthBars: 8, color: PulsoTheme.amber),
                            SectionItem(id: 2, name: "VERSO", startBar: 9, lengthBars: 8, color: Color(hexString: "#26a69a"))
                        ]
                    )

                    self.setlist.songs.append(newLocalSong)
                    self.loadSong(newLocalSong)
                }
            }
        } catch {
            print("[PULSO LOCAL] Error importando archivos: \(error)")
        }
    }

    // MARK: - Low-Frequency Musical Bar/Section Sync (Sin mutar stems/RMS)

    private func startPositionTimer() {
        timer?.invalidate()
        let ticker = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMusicalPosition() }
        }
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    private func updateMusicalPosition() {
        guard isPlaying else { return }
        let nowSec = currentSeconds

        if nowSec >= currentSong.durationSeconds {
            stop()
            return
        }

        let totalBeats = Int(nowSec / beatDuration)
        let newBar = (totalBeats / musicalPosition.beatsPerBar) + 1
        musicalPosition.update(totalBeats)

        // Active section tracking (solo publica si cambia de sección)
        for (idx, sec) in currentSong.sections.enumerated().reversed() {
            if newBar >= sec.startBar {
                if activeSectionIndex != idx {
                    activeSectionIndex = idx
                }
                if loopSection && newBar >= (sec.startBar + sec.lengthBars) {
                    jumpToSection(index: idx)
                }
                break
            }
        }
    }

    private func stopPositionTimer() {
        timer?.invalidate()
        timer = nil
    }
}
