import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int, String?)
    case clientError(Int, String?)
    case decodingError(Error)
    case networkError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request"
        case .unauthorized: return "Please sign in again"
        case .forbidden: return "Upgrade your plan to access this feature"
        case .notFound: return "Resource not found"
        case .rateLimited: return "You've reached your daily limit"
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))"
        case .clientError(_, let message):
            return message ?? "Something went wrong"
        case .decodingError: return "Unexpected response format"
        case .networkError: return "No internet connection"
        case .unknown: return "Something went wrong"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var isRefreshingToken = false

    private init() {
        self.baseURL = AppConstants.apiBaseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        allowRetry: Bool = true
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = Keychain.loadString(forKey: AppConstants.accessTokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            if authenticated && allowRetry && !isRefreshingToken && !path.contains("/auth/") {
                return try await refreshAndRetry(method, path: path, body: body)
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited
        case 400...499:
            let message = Self.extractErrorMessage(from: data)
            throw APIError.clientError(httpResponse.statusCode, message)
        case 500...599:
            let message = Self.extractErrorMessage(from: data)
            throw APIError.serverError(httpResponse.statusCode, message)
        default:
            throw APIError.unknown
        }
    }

    private func refreshAndRetry<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        isRefreshingToken = true
        defer { isRefreshingToken = false }

        guard let refreshToken = Keychain.loadString(forKey: AppConstants.refreshTokenKey) else {
            throw APIError.unauthorized
        }

        let tokens: AuthTokens = try await request(
            "POST", path: "/auth/refresh",
            body: RefreshBody(refreshToken: refreshToken),
            authenticated: false,
            allowRetry: false
        )
        Keychain.saveString(tokens.accessToken, forKey: AppConstants.accessTokenKey)
        Keychain.saveString(tokens.refreshToken, forKey: AppConstants.refreshTokenKey)

        return try await request(method, path: path, body: body, allowRetry: false)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path: path)
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PATCH", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: path)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request("DELETE", path: path)
    }

    func healthCheck() async throws -> HealthStatus {
        try await request("GET", path: "/health", authenticated: false)
    }

    // MARK: - File Upload / Download

    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> FileUploadResponse {
        guard let url = URL(string: baseURL + "/files/upload") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = Keychain.loadString(forKey: AppConstants.accessTokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw APIError.unauthorized
            case 413: throw APIError.serverError(413, nil)
            default: throw APIError.serverError(httpResponse.statusCode, nil)
            }
        }

        do {
            return try decoder.decode(FileUploadResponse.self, from: responseData)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func downloadFile(fileId: String) async throws -> (Data, String, String) {
        guard let url = URL(string: baseURL + "/files/\(fileId)/download") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = Keychain.loadString(forKey: AppConstants.accessTokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.notFound
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let filename = Self.extractFilename(from: disposition)

        return (data, filename, contentType)
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String else { return nil }
        return error
    }

    private static func extractFilename(from disposition: String) -> String {
        if let range = disposition.range(of: "filename=\""),
           let end = disposition[range.upperBound...].range(of: "\"") {
            let encoded = String(disposition[range.upperBound..<end.lowerBound])
            return encoded.removingPercentEncoding ?? encoded
        }
        return "download"
    }
}

struct HealthStatus: Decodable {
    let status: String
    let services: Services?

    struct Services: Decodable {
        let database: String?
        let openclawGateway: String?
    }

    var isHealthy: Bool { status == "ok" }
}

private struct RefreshBody: Codable { let refreshToken: String }
private struct EmptyResponse: Decodable {}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
