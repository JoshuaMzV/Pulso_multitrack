import SwiftUI

// MARK: - Song Models Matching PULSO Database & Schema

struct SectionItem: Identifiable, Hashable, Codable {
    let id: Int
    var name: String
    var startBar: Int
    var lengthBars: Int
    var colorHex: String = "#3B82F6"

    var color: Color {
        Color(hexString: colorHex)
    }

    init(id: Int, name: String, startBar: Int, lengthBars: Int, color: Color) {
        self.id = id
        self.name = name
        self.startBar = startBar
        self.lengthBars = lengthBars
        self.colorHex = "#3B82F6"
    }

    init(id: Int, name: String, startBar: Int, lengthBars: Int, colorHex: String = "#3B82F6") {
        self.id = id
        self.name = name
        self.startBar = startBar
        self.lengthBars = lengthBars
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startBar, bar, lengthBars, len, colorHex, color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "SECCIÓN"
        self.startBar = (try? container.decode(Int.self, forKey: .startBar)) ??
                        (try? container.decode(Int.self, forKey: .bar)) ?? 1
        self.lengthBars = (try? container.decode(Int.self, forKey: .lengthBars)) ??
                          (try? container.decode(Int.self, forKey: .len)) ?? 8
        self.colorHex = (try? container.decode(String.self, forKey: .colorHex)) ??
                        (try? container.decode(String.self, forKey: .color)) ?? "#3B82F6"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startBar, forKey: .startBar)
        try container.encode(lengthBars, forKey: .lengthBars)
        try container.encode(colorHex, forKey: .colorHex)
    }
}

struct StemItem: Identifiable, Hashable, Codable {
    let id: String
    var label: String
    var category: String
    var colorHex: String
    var bus: Int // 0: Master (FOH), 1: Cue (Monitors/Click)
    var gainDb: Float = 0.0 // -60 to +10 dB
    var pan: Float = 0.0 // -1.0 to +1.0
    var muted: Bool = false
    var solo: Bool = false
    var rms: Float = 0.0 // 0.0 to 1.0 real-time peak meter
    var filename: String? = nil
    var original: String? = nil
    var url: String? = nil
    var localPath: String? = nil

    var accentColor: Color {
        Color(hexString: colorHex)
    }

    init(id: String, label: String, category: String, colorHex: String, bus: Int = 0, gainDb: Float = 0.0, pan: Float = 0.0, muted: Bool = false, solo: Bool = false, filename: String? = nil, original: String? = nil, url: String? = nil) {
        self.id = id
        self.label = label
        self.category = category
        self.colorHex = colorHex
        self.bus = bus
        self.gainDb = gainDb
        self.pan = pan
        self.muted = muted
        self.solo = solo
        self.filename = filename
        self.original = original
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case id, label, category, colorHex, color, bus, gainDb, gain, pan, muted, solo, filename, original, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.label = (try? container.decode(String.self, forKey: .label)) ?? self.id.uppercased()
        self.category = (try? container.decode(String.self, forKey: .category)) ?? "other"
        self.colorHex = (try? container.decode(String.self, forKey: .colorHex)) ??
                        (try? container.decode(String.self, forKey: .color)) ?? "#C3C7CC"
        self.bus = (try? container.decode(Int.self, forKey: .bus)) ?? ((self.category == "click" || self.category == "guide") ? 1 : 0)

        if let g = try? container.decode(Float.self, forKey: .gainDb) {
            self.gainDb = g
        } else if let g = try? container.decode(Double.self, forKey: .gain) {
            // Gain linear 0.0..1.0 convert to approx dB
            self.gainDb = g > 0.01 ? Float(20.0 * log10(g)) : -60.0
        } else {
            self.gainDb = 0.0
        }

        self.pan = (try? container.decode(Float.self, forKey: .pan)) ?? 0.0
        self.muted = (try? container.decode(Bool.self, forKey: .muted)) ?? false
        self.solo = (try? container.decode(Bool.self, forKey: .solo)) ?? false
        self.rms = 0.0
        self.filename = try? container.decode(String.self, forKey: .filename)
        self.original = try? container.decode(String.self, forKey: .original)
        self.url = try? container.decode(String.self, forKey: .url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(category, forKey: .category)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(bus, forKey: .bus)
        try container.encode(gainDb, forKey: .gainDb)
        try container.encode(pan, forKey: .pan)
        try container.encode(muted, forKey: .muted)
        try container.encode(solo, forKey: .solo)
        try container.encodeIfPresent(filename, forKey: .filename)
        try container.encodeIfPresent(original, forKey: .original)
        try container.encodeIfPresent(url, forKey: .url)
    }
}

enum TransitionMode: String, CaseIterable, Hashable, Codable {
    case stop = "stop" // Con pausa
    case instant = "instant" // Al terminar
    case overlap = "overlap" // Traslape con fundido

    var icon: String {
        switch self {
        case .stop: return "⤓"
        case .instant: return "↴"
        case .overlap: return "⇄"
        }
    }

    var label: String {
        switch self {
        case .stop: return "Con pausa"
        case .instant: return "Al terminar"
        case .overlap: return "Traslape con fundido"
        }
    }
}

struct SongItem: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var artist: String
    var bpm: Double
    var key: String
    var timeSignature: String
    var durationSeconds: Double
    var stems: [StemItem]
    var sections: [SectionItem]
    var coverUrl: String?
    var downloadUrl: String?
    var folderId: String?
    var transition: TransitionMode = .stop

    /// Nombre de la carpeta en disco para almacenar los stems
    var folderName: String {
        if let f = folderId, !f.isEmpty { return f }
        return id.replacingOccurrences(of: "song_", with: "").replacingOccurrences(of: "cloud_", with: "")
    }

    /// Comprueba si los stems de audio existen físicamente descargados en el iPad
    var isDownloadedLocally: Bool {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidateFolder = folderName
        let cleanTitle = title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")

        let candidatePaths = [
            docDir.appendingPathComponent("Songs").appendingPathComponent(candidateFolder),
            docDir.appendingPathComponent("Songs").appendingPathComponent(cleanTitle),
            docDir.appendingPathComponent("Songs").appendingPathComponent(id)
        ]

        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: path.path), !files.isEmpty {
                    let hasAudio = files.contains {
                        $0.hasSuffix(".mp3") || $0.hasSuffix(".wav") || $0.hasSuffix(".flac") || $0.hasSuffix(".m4a")
                    }
                    if hasAudio { return true }
                }
            }
        }
        return false
    }

    init(id: String, title: String, artist: String, bpm: Double, key: String, timeSignature: String = "4/4", durationSeconds: Double = 270.0, stems: [StemItem] = [], sections: [SectionItem] = [], coverUrl: String? = nil, downloadUrl: String? = nil, folderId: String? = nil, transition: TransitionMode = .stop) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.key = key
        self.timeSignature = timeSignature
        self.durationSeconds = durationSeconds
        self.stems = stems
        self.sections = sections
        self.coverUrl = coverUrl
        self.downloadUrl = downloadUrl
        self.folderId = folderId
        self.transition = transition
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, bpm, key, timeSignature, durationSeconds, stems, backendStems, sections, coverUrl, cover, downloadUrl, folderId, transition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Sin título"
        self.artist = (try? container.decode(String.self, forKey: .artist)) ?? "Desconocido"
        self.bpm = (try? container.decode(Double.self, forKey: .bpm)) ?? 120.0
        self.key = (try? container.decode(String.self, forKey: .key)) ?? "C"
        self.timeSignature = (try? container.decode(String.self, forKey: .timeSignature)) ?? "4/4"
        self.durationSeconds = (try? container.decode(Double.self, forKey: .durationSeconds)) ?? 270.0

        if let st = try? container.decode([StemItem].self, forKey: .stems) {
            self.stems = st
        } else if let bSt = try? container.decode([StemItem].self, forKey: .backendStems) {
            self.stems = bSt
        } else {
            self.stems = []
        }

        self.sections = (try? container.decode([SectionItem].self, forKey: .sections)) ?? []
        self.coverUrl = (try? container.decode(String.self, forKey: .coverUrl)) ??
                        (try? container.decode(String.self, forKey: .cover))
        self.downloadUrl = try? container.decode(String.self, forKey: .downloadUrl)
        self.folderId = try? container.decode(String.self, forKey: .folderId)
        self.transition = (try? container.decode(TransitionMode.self, forKey: .transition)) ?? .stop
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(key, forKey: .key)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(stems, forKey: .stems)
        try container.encode(sections, forKey: .sections)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(downloadUrl, forKey: .downloadUrl)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encode(transition, forKey: .transition)
    }
}

struct SetlistItem: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var description: String? = nil
    var songs: [SongItem]
    var currentIndex: Int = 0
    var group_id: String? = nil
    var group_name: String? = nil

    var currentSong: SongItem? {
        guard songs.indices.contains(currentIndex) else { return songs.first }
        return songs[currentIndex]
    }

    var nextSong: SongItem? {
        guard songs.indices.contains(currentIndex + 1) else { return nil }
        return songs[currentIndex + 1]
    }

    init(id: String, name: String, description: String? = nil, songs: [SongItem] = [], currentIndex: Int = 0, group_id: String? = nil, group_name: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.songs = songs
        self.currentIndex = currentIndex
        self.group_id = group_id
        self.group_name = group_name
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, songs, currentIndex, group_id, group_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "SETLIST"
        self.description = try? container.decode(String.self, forKey: .description)
        self.songs = (try? container.decode([SongItem].self, forKey: .songs)) ?? []
        self.currentIndex = (try? container.decode(Int.self, forKey: .currentIndex)) ?? 0
        self.group_id = try? container.decode(String.self, forKey: .group_id)
        self.group_name = try? container.decode(String.self, forKey: .group_name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(songs, forKey: .songs)
        try container.encode(currentIndex, forKey: .currentIndex)
        try container.encodeIfPresent(group_id, forKey: .group_id)
        try container.encodeIfPresent(group_name, forKey: .group_name)
    }
}

// MARK: - Preloaded Sample Data from PULSO Database

enum MockSongData {
    static let seOyeStems: [StemItem] = [
        StemItem(id: "click", label: "CLICK", category: "click", colorHex: "#9297A0", bus: 1, gainDb: -1.5),
        StemItem(id: "guide", label: "GUIDE", category: "guide", colorHex: "#F0A028", bus: 1, gainDb: -3.0),
        StemItem(id: "drums", label: "DRUMS", category: "drums", colorHex: "#FF4B33", bus: 0, gainDb: 0.0),
        StemItem(id: "bass", label: "BASS", category: "bass", colorHex: "#3DDC84", bus: 0, gainDb: 0.0),
        StemItem(id: "keys", label: "KEYS", category: "keys", colorHex: "#4DA6FF", bus: 0, gainDb: -2.0),
        StemItem(id: "keys_2", label: "PIANO", category: "keys", colorHex: "#4DA6FF", bus: 0, gainDb: -2.0),
        StemItem(id: "pad", label: "PAD", category: "pad", colorHex: "#B388FF", bus: 0, gainDb: -4.0),
        StemItem(id: "guitars", label: "EG 1", category: "guitars", colorHex: "#FFBE55", bus: 0, gainDb: -2.5),
        StemItem(id: "guitars_2", label: "EG 2", category: "guitars", colorHex: "#FFBE55", bus: 0, gainDb: -2.5),
        StemItem(id: "horns", label: "HORNS", category: "other", colorHex: "#C3C7CC", bus: 0, gainDb: -3.0),
        StemItem(id: "loop", label: "LOOP", category: "other", colorHex: "#C3C7CC", bus: 0, gainDb: -3.0)
    ]

    static let seOyeSections: [SectionItem] = [
        SectionItem(id: 0, name: "INTRO", startBar: 1, lengthBars: 8, color: PulsoTheme.blue),
        SectionItem(id: 1, name: "LEVÁNTATE", startBar: 9, lengthBars: 8, color: PulsoTheme.teal),
        SectionItem(id: 2, name: "VERSO", startBar: 17, lengthBars: 8, color: PulsoTheme.teal),
        SectionItem(id: 3, name: "PRECORO", startBar: 25, lengthBars: 8, color: PulsoTheme.amber),
        SectionItem(id: 4, name: "CORO", startBar: 33, lengthBars: 12, color: PulsoTheme.red),
        SectionItem(id: 5, name: "PUENTE", startBar: 45, lengthBars: 8, color: PulsoTheme.purple),
        SectionItem(id: 6, name: "FINAL", startBar: 53, lengthBars: 8, color: PulsoTheme.textDim)
    ]

    static let song1 = SongItem(
        id: "Se_Oye_en_las_Naciones___Levantate",
        title: "Se Oye en las Naciones / Levantate",
        artist: "Marcos Witt",
        bpm: 145.0,
        key: "Bb",
        timeSignature: "4/4",
        durationSeconds: 265.0,
        stems: seOyeStems,
        sections: seOyeSections,
        downloadUrl: "https://stems.tld-list.lat/songs/Se_Oye_en_las_Naciones___Levantate_145bpm.zip",
        folderId: "Se_Oye_en_las_Naciones___Levantate"
    )

    static let song2 = SongItem(
        id: "Danzare",
        title: "Danzare",
        artist: "Gateway Worship",
        bpm: 128.0,
        key: "E",
        timeSignature: "4/4",
        durationSeconds: 310.0,
        stems: seOyeStems,
        sections: [
            SectionItem(id: 0, name: "INTRO", startBar: 1, lengthBars: 8, color: PulsoTheme.blue),
            SectionItem(id: 1, name: "VERSO", startBar: 9, lengthBars: 8, color: PulsoTheme.teal),
            SectionItem(id: 2, name: "CORO", startBar: 17, lengthBars: 8, color: PulsoTheme.red),
            SectionItem(id: 3, name: "PUENTE", startBar: 25, lengthBars: 8, color: PulsoTheme.purple),
            SectionItem(id: 4, name: "FINAL", startBar: 33, lengthBars: 8, color: PulsoTheme.textDim)
        ],
        downloadUrl: "https://stems.tld-list.lat/songs/Danzare_130bpm.zip",
        folderId: "Danzare"
    )

    static let defaultSetlist = SetlistItem(
        id: "setlist-domingo",
        name: "SETLIST DOMINGO",
        description: "Servicio",
        songs: [song1, song2],
        currentIndex: 0
    )
}
