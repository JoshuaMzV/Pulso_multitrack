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

    // Cloud Catalog & Downloads
    @Published var cloudCatalog: [CloudSong] = []
    @Published var isLoadingCatalog: Bool = false
    @Published var isDownloadingSong: Bool = false
    @Published var downloadProgress: [String: Double] = [:]

    // Setlist & Song
    @Published var setlist: SetlistItem = MockSongData.defaultSetlist
    @Published var currentSong: SongItem = MockSongData.song1
    @Published var nextSong: SongItem? = MockSongData.song2

    // Playback State
    @Published var isPlaying: Bool = false
    @Published var currentSeconds: Double = 0.0
    @Published var currentBar: Int = 1
    @Published var currentBeat: Int = 1 // 1..4
    @Published var activeSectionIndex: Int = 0
    @Published var loopSection: Bool = false

    // Master & Pad
    @Published var masterDb: Float = 0.0
    @Published var masterRmsL: Float = 0.0
    @Published var masterRmsR: Float = 0.0
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

    init() {
        self.loadSong(MockSongData.song1)
        self.checkSessionWithBackend()
    }

    func selectTrack(id: String) {
        selectedTrackId = id
    }

    func loadSong(_ song: SongItem) {
        self.currentSong = song
        self.stems = song.stems
        self.padKey = song.key
        self.currentSeconds = 0.0
        self.currentBar = 1
        self.currentBeat = 1
        self.activeSectionIndex = 0
        self.isPlaying = false

        let idx = setlist.songs.firstIndex(where: { $0.id == song.id }) ?? 0
        setlist.currentIndex = idx
        if idx + 1 < setlist.songs.count {
            nextSong = setlist.songs[idx + 1]
        } else {
            nextSong = nil
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

    func addSection(name: String, color: Color) {
        let lastBar = currentSong.sections.map { $0.startBar + $0.lengthBars }.max() ?? 1
        let newSec = SectionItem(
            id: currentSong.sections.count,
            name: name,
            startBar: lastBar,
            lengthBars: 8,
            color: color
        )
        currentSong.sections.append(newSec)
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
        isPlaying.toggle()
        if isPlaying {
            startSimulationTimer()
        } else {
            stopSimulationTimer()
        }
    }

    func stop() {
        isPlaying = false
        currentSeconds = 0.0
        currentBar = 1
        currentBeat = 1
        activeSectionIndex = 0
        stopSimulationTimer()
        for i in stems.indices {
            stems[i].rms = 0.0
        }
        masterRmsL = 0.0
        masterRmsR = 0.0
    }

    func jumpToSection(index: Int) {
        guard currentSong.sections.indices.contains(index) else { return }
        activeSectionIndex = index
        let sec = currentSong.sections[index]
        currentBar = sec.startBar
        let secondsPerBar = (60.0 / currentSong.bpm) * 4.0
        currentSeconds = Double(sec.startBar - 1) * secondsPerBar
    }

    func seek(to seconds: Double) {
        let clamped = max(0.0, min(currentSong.durationSeconds, seconds))
        currentSeconds = clamped
        let beatsPerSecond = currentSong.bpm / 60.0
        let totalBeats = Int(currentSeconds * beatsPerSecond)
        currentBar = (totalBeats / 4) + 1
        currentBeat = (totalBeats % 4) + 1

        for (idx, sec) in currentSong.sections.enumerated() {
            if currentBar >= sec.startBar && currentBar < (sec.startBar + sec.lengthBars) {
                activeSectionIndex = idx
                break
            }
        }
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
    }

    func toggleMute(id: String) {
        guard let idx = stems.firstIndex(where: { $0.id == id }) else { return }
        stems[idx].muted.toggle()
    }

    func toggleSolo(id: String) {
        guard let idx = stems.firstIndex(where: { $0.id == id }) else { return }
        stems[idx].solo.toggle()
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
                    let stemName = stem.filename ?? stem.original ?? "\(stem.id).mp3"
                    let localStemURL = songDir.appendingPathComponent(stemName)

                    if let urlString = stem.url, let remoteURL = URL(string: urlString) {
                        if !FileManager.default.fileExists(atPath: localStemURL.path) {
                            try await BackendAPIService.shared.downloadStem(from: remoteURL, to: localStemURL)
                        }
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
                        gainDb: 0.0
                    ))
                }

                // Crear SongItem nativo
                let newSong = SongItem(
                    id: cloudSong.id,
                    title: cloudSong.title,
                    artist: cloudSong.artist ?? "Desconocido",
                    bpm: cloudSong.bpm ?? 120.0,
                    key: cloudSong.key ?? "C",
                    timeSignature: "4/4",
                    durationSeconds: 270.0,
                    stems: downloadedStems,
                    sections: [
                        SectionItem(id: 1, name: "INTRO", startBar: 1, lengthBars: 8, color: PulsoTheme.amber),
                        SectionItem(id: 2, name: "VERSO", startBar: 9, lengthBars: 8, color: Color(hexString: "#26a69a")),
                        SectionItem(id: 3, name: "CORO", startBar: 17, lengthBars: 8, color: Color(hexString: "#ef5350"))
                    ],
                    coverUrl: cloudSong.cover
                )

                if !self.setlist.songs.contains(where: { $0.id == newSong.id || $0.title == newSong.title }) {
                    self.setlist.songs.append(newSong)
                }
                self.currentSong = newSong
                self.downloadProgress[cloudSong.id] = 1.0
                self.isDownloadingSong = false
            } catch {
                print("Error descargando canción: \(error)")
                self.isDownloadingSong = false
                self.downloadProgress[cloudSong.id] = nil
            }
        }
    }

    // MARK: - Internal Simulation Clock (Active until Phase 2 AudioEngine attaches)

    private func startSimulationTimer() {
        timer?.invalidate()
        let interval = 0.05
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.currentSeconds += interval
                if self.currentSeconds >= self.currentSong.durationSeconds {
                    self.stop()
                    return
                }

                let beatsPerSecond = self.currentSong.bpm / 60.0
                let totalBeats = Int(self.currentSeconds * beatsPerSecond)
                self.currentBar = (totalBeats / 4) + 1
                self.currentBeat = (totalBeats % 4) + 1

                // Active section tracking
                for (idx, sec) in self.currentSong.sections.enumerated().reversed() {
                    if self.currentBar >= sec.startBar {
                        self.activeSectionIndex = idx
                        if self.loopSection && self.currentBar >= (sec.startBar + sec.lengthBars) {
                            self.jumpToSection(index: idx)
                        }
                        break
                    }
                }

                // Animate meters slightly for visual feedback
                for i in self.stems.indices {
                    if !self.stems[i].muted {
                        let gainLinear = pow(10.0, self.stems[i].gainDb / 20.0)
                        self.stems[i].rms = Float.random(in: 0.3...0.85) * min(1.2, gainLinear)
                    } else {
                        self.stems[i].rms = 0.0
                    }
                }
                let masterLinear = pow(10.0, self.masterDb / 20.0)
                self.masterRmsL = Float.random(in: 0.35...0.88) * min(1.2, masterLinear)
                self.masterRmsR = Float.random(in: 0.35...0.88) * min(1.2, masterLinear)
            }
        }
    }

    private func stopSimulationTimer() {
        timer?.invalidate()
        timer = nil
    }
}
