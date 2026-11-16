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
    @Published var showingArrangerPanel: Bool = false
    @Published var showingTransposeDialog: Bool = false

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
    @Published var padActive: Bool = false
    @Published var padKey: String = "Bb"

    // Stems for active song
    @Published var stems: [StemItem] = []
    @Published var selectedTrackId: String = "guide"

    // Timer for simulation / playhead if no audio hardware connected yet
    private var timer: Timer?

    init() {
        self.loadSong(MockSongData.song1)
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
    }

    func jumpToSection(index: Int) {
        guard currentSong.sections.indices.contains(index) else { return }
        activeSectionIndex = index
        let sec = currentSong.sections[index]
        currentBar = sec.startBar
        let secondsPerBar = (60.0 / currentSong.bpm) * 4.0
        currentSeconds = Double(sec.startBar - 1) * secondsPerBar
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

    func login(username: String) {
        let initial = username.prefix(2).uppercased()
        currentUser = UserProfile(username: username, role: .admin, avatar: initial.isEmpty ? "US" : initial)
        isLoggedIn = true
    }

    func logout() {
        currentUser = UserProfile(username: "invitado", role: .guest, avatar: "IN")
        isLoggedIn = false
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
                        self.stems[i].rms = Float.random(in: 0.2...0.85)
                    } else {
                        self.stems[i].rms = 0.0
                    }
                }
            }
        }
    }

    private func stopSimulationTimer() {
        timer?.invalidate()
        timer = nil
    }
}
