import Foundation

// Cliente da API do Fyin (cmd/api). Uma instância por app, criada em FyinApp.
struct APIClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send("GET", path, query: query)
    }

    /// POST sem corpo (ações como sincronizar); o servidor responde 2xx com JSON.
    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send("POST", path)
    }

    /// POST com corpo JSON já serializado (ex.: páginas cruas da B3, que o app só repassa).
    func post<T: Decodable>(_ path: String, json body: Data) async throws -> T {
        try await send("POST", path, body: body)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractions
        return try decoder.decode(T.self, from: data)
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    // Go manda RFC 3339 com ou sem fração de segundo.
    static let iso8601WithFractions = custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) { return date }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "data inválida \(text)"))
    }
}
