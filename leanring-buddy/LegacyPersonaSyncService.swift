//
//  LegacyPersonaSyncService.swift
//  leanring-buddy
//
//  Syncs a LegacyPersona to and from the Cloudflare Worker's KV-backed
//  /persona/:id endpoint so the user's "digital you" survives reinstalls and
//  can be restored on another machine. Memories stay local (they include audio);
//  only the lightweight persona record is synced here.
//

import Foundation

@MainActor
final class LegacyPersonaSyncService {

    private let personaSyncBaseURL: String
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    /// - Parameter personaSyncBaseURL: the Worker base URL plus "/persona"
    ///   (the persona id is appended per request).
    init(personaSyncBaseURL: String) {
        self.personaSyncBaseURL = personaSyncBaseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
    }

    enum PersonaSyncError: LocalizedError {
        case invalidURL
        case serverError(statusCode: Int, message: String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The persona sync URL is invalid."
            case .serverError(let statusCode, let message):
                return "Persona sync failed (\(statusCode)): \(message)"
            case .notFound:
                return "No saved persona was found to restore."
            }
        }
    }

    /// Uploads the persona JSON to the Worker, keyed by its id (PUT).
    func uploadPersona(_ persona: LegacyPersona) async throws {
        guard let requestURL = URL(string: "\(personaSyncBaseURL)/\(persona.id.uuidString)") else {
            throw PersonaSyncError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(persona)

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PersonaSyncError.serverError(statusCode: statusCode, message: message)
        }
    }

    /// Restores a persona from the Worker by id (GET). Throws `.notFound` if no
    /// persona has been uploaded under that id yet.
    func downloadPersona(withID personaID: UUID) async throws -> LegacyPersona {
        guard let requestURL = URL(string: "\(personaSyncBaseURL)/\(personaID.uuidString)") else {
            throw PersonaSyncError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PersonaSyncError.serverError(statusCode: -1, message: "Invalid response")
        }

        if httpResponse.statusCode == 404 {
            throw PersonaSyncError.notFound
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw PersonaSyncError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return try jsonDecoder.decode(LegacyPersona.self, from: responseData)
    }
}
