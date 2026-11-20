import Foundation

// MARK: - Server Response Models

struct ServerUser: Codable {
    let id: Int
    let username: String
    let role: String
    let grupo_id: String?
    let group_name: String?

    var userRole: UserRole {
        UserRole.from(backendRole: role)
    }

    var avatar: String {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        let prefix = trimmed.prefix(2).uppercased()
        return prefix.isEmpty ? "US" : prefix
    }
}

struct AuthResponse: Codable {
    let status: String?
    let message: String?
    let token: String?
    let user: ServerUser?
    let error: String?
}

struct AuthMeResponse: Codable {
    let authenticated: Bool
    let user: ServerUser?
}

struct CloudSongStem: Codable, Identifiable {
    let id: String
    let original: String?
    let filename: String?
    let label: String?
    let category: String?
    let url: String?
    let existsOnServer: Bool?
}

struct CloudSong: Codable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let bpm: Double?
    let key: String?
    let filename: String?
    let downloadUrl: String?
    let cover: String?
    let extractedFolder: String?
    let stems: [CloudSongStem]?
    let date: String?
}

struct CloudCatalogResponse: Codable {
    let status: String?
    let service: String?
    let songs: [CloudSong]?
}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case serverError(String)
    case networkError(Error)
    case unauthorized
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "La URL del servidor no es válida."
        case .serverError(let message):
            return message
        case .networkError(let error):
            return "Error de red: \(error.localizedDescription)"
        case .unauthorized:
            return "Sesión no válida o expirada."
        case .decodingError:
            return "Respuesta del servidor no comprensible."
        }
    }
}

// MARK: - Backend API Service

final class BackendAPIService {
    static let shared = BackendAPIService()

    private let defaults = UserDefaults.standard
    private let tokenKey = "pulso_auth_token"
    private let serverURLKey = "pulso_server_url"

    private init() {}

    static let defaultURL = "https://stems.tld-list.lat"

    /// Base URL of the backend API (configurable)
    var baseURL: String {
        get {
            defaults.string(forKey: serverURLKey) ?? Self.defaultURL
        }
        set {
            var cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasSuffix("/") {
                cleaned.removeLast()
            }
            defaults.set(cleaned, forKey: serverURLKey)
        }
    }

    /// Active session token
    var authToken: String? {
        get {
            defaults.string(forKey: tokenKey)
        }
        set {
            if let token = newValue {
                defaults.set(token, forKey: tokenKey)
            } else {
                defaults.removeObject(forKey: tokenKey)
            }
        }
    }

    var isAuthenticated: Bool {
        authToken != nil
    }

    // MARK: - Authentication Methods

    /// Inicia sesión con credenciales
    func login(username: String, password: String) async throws -> ServerUser {
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username.trimmingCharacters(in: .whitespaces),
            "password": password
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode >= 400 {
            let errorMsg = parseErrorMessage(from: data) ?? "Credenciales inválidas."
            throw APIError.serverError(errorMsg)
        }

        do {
            let authRes = try JSONDecoder().decode(AuthResponse.self, from: data)
            if let token = authRes.token {
                self.authToken = token
            }
            guard let user = authRes.user else {
                throw APIError.serverError("No se recibieron datos de usuario.")
            }
            return user
        } catch {
            throw APIError.decodingError
        }
    }

    /// Registra usuario mediante código de invitación
    func register(username: String, password: String, inviteCode: String) async throws -> ServerUser {
        guard let url = URL(string: "\(baseURL)/api/auth/register") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username.trimmingCharacters(in: .whitespaces),
            "password": password,
            "invite_code": inviteCode.trimmingCharacters(in: .whitespaces).uppercased()
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode >= 400 {
            let errorMsg = parseErrorMessage(from: data) ?? "Error al registrar usuario."
            throw APIError.serverError(errorMsg)
        }

        do {
            let authRes = try JSONDecoder().decode(AuthResponse.self, from: data)
            if let token = authRes.token {
                self.authToken = token
            }
            guard let user = authRes.user else {
                throw APIError.serverError("No se recibieron datos de usuario.")
            }
            return user
        } catch {
            throw APIError.decodingError
        }
    }

    /// Verifica la sesión activa actual con el servidor
    func checkSession() async throws -> ServerUser? {
        guard let token = authToken, !token.isEmpty else {
            return nil
        }
        guard let url = URL(string: "\(baseURL)/api/auth/me") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)

        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            self.authToken = nil
            return nil
        }

        if let meRes = try? JSONDecoder().decode(AuthMeResponse.self, from: data),
           meRes.authenticated, let user = meRes.user {
            return user
        } else {
            self.authToken = nil
            return nil
        }
    }

    /// Cierra la sesión activa
    func logout() async {
        if let token = authToken, let url = URL(string: "\(baseURL)/api/auth/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await performRequest(request)
        }
        self.authToken = nil
    }

    // MARK: - Cloud Catalog & Song Download Methods

    /// Obtiene el catálogo de canciones disponibles en la nube
    func fetchCatalog() async throws -> [CloudSong] {
        guard let url = URL(string: "\(baseURL)/api/songs") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError("Error al obtener canciones del servidor")
        }

        // 1. Intentar decodificar como array directo de CloudSong
        if let list = try? JSONDecoder().decode([CloudSong].self, from: data) {
            return list
        }

        // 2. Intentar decodificar como objeto catálogo { "songs": [...] }
        if let cat = try? JSONDecoder().decode(CloudCatalogResponse.self, from: data), let songs = cat.songs {
            return songs
        }

        // 3. Fallback directo a /catalog.json
        if let catUrl = URL(string: "\(baseURL)/catalog.json") {
            let catReq = URLRequest(url: catUrl)
            if let (catData, _) = try? await performRequest(catReq),
               let cat = try? JSONDecoder().decode(CloudCatalogResponse.self, from: catData),
               let songs = cat.songs {
                return songs
            }
        }
        return []
    }

    /// Descarga un stem individual directamente al directorio local de la canción
    func downloadStem(from remoteURL: URL, to destinationURL: URL) async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError("Error al descargar pista (\(remoteURL.lastPathComponent))")
        }
        let folder = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    }

    // MARK: - Internal HTTP Helper

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        req.timeoutInterval = 10.0

        if req.value(forHTTPHeaderField: "Authorization") == nil, let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            return try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            return error
        }
        return nil
    }
}
