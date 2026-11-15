import SwiftUI

// MARK: - Song Models Matching PULSO Database & Schema

struct SectionItem: Identifiable, Hashable {
    let id: Int
    var name: String
    var startBar: Int
    var lengthBars: Int
    var color: Color
}

struct StemItem: Identifiable, Hashable {
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

    var accentColor: Color {
        Color(hexString: colorHex)
    }
}

struct SongItem: Identifiable, Hashable {
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
}

struct SetlistItem: Identifiable {
    let id: String
    var name: String
    var songs: [SongItem]
    var currentIndex: Int = 0

    var currentSong: SongItem? {
        guard songs.indices.contains(currentIndex) else { return songs.first }
        return songs[currentIndex]
    }

    var nextSong: SongItem? {
        guard songs.indices.contains(currentIndex + 1) else { return nil }
        return songs[currentIndex + 1]
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
        SectionItem(id: 1, name: "VERSO", startBar: 9, lengthBars: 8, color: PulsoTheme.teal),
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
        sections: seOyeSections
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
        ]
    )

    static let defaultSetlist = SetlistItem(
        id: "setlist-domingo",
        name: "SETLIST DOMINGO",
        songs: [song1, song2],
        currentIndex: 0
    )
}
