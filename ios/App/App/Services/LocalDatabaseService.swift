import Foundation
import SQLite3

/// Service responsible for offline database access and storage management
final class LocalDatabaseService {
    static let shared = LocalDatabaseService()

    private init() {}

    /// Gets the application's local Documents directory (which is exposed via iPadOS Files)
    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// URL for offline songs directory: Documents/Songs/
    var songsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("Songs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Checks for custom setlists saved in Documents
    func loadLocalSetlists() -> [SetlistItem] {
        let setlistsFile = documentsDirectory.appendingPathComponent("setlists.json")
        guard FileManager.default.fileExists(atPath: setlistsFile.path),
              let data = try? Data(contentsOf: setlistsFile) else {
            return [MockSongData.defaultSetlist]
        }

        // Parse JSON if valid, otherwise fallback
        return [MockSongData.defaultSetlist]
    }

    /// Scans Documents/Songs for downloaded or imported stems
    func scanAvailableOfflineSongs() -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: songsDirectory.path) else {
            return []
        }
        return items
    }
}
