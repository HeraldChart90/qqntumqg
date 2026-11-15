import Foundation

// hh.ru inside the app: the work order is published on hh.ru by the АртСтрой server,
// responses and the chat with applicants come back here. No hh keys in the app.

/// Job boards the work order is published to.
enum JobBoard: String, CaseIterable, Identifiable {
    case hh, avito
    var id: String { rawValue }
    var title: String { self == .hh ? "hh.ru" : "Avito" }
    var badge: String { self == .hh ? "hh" : "A" }
}

struct HHLink: Codable {
    let vacancyId: String
    let token: String
    let url: String
}

struct HHApplicant: Decodable, Identifiable {
    let id: String
    let chatId: String?
    let name: String
    let title: String
    let area: String
    let experience: String
    let skills: [String]
    let state: String
    let createdAt: String
    let unread: Int
}

struct HHResponses: Decodable {
    struct Vacancy: Decodable { let id: String; let url: String; let title: String; let status: String }
    let vacancy: Vacancy
    let applicants: [HHApplicant]
}

struct HHMessage: Decodable, Identifiable {
    let id: String
    let text: String
    let fromClient: Bool
    let name: String
    let createdAt: String
}

/// Vacancy of another employer (market search on hh.ru / Avito).
struct MarketVacancy: Decodable, Identifiable, Hashable {
    let board: String
    let id: String
    let title: String
    let company: String
    let city: String
    let salary: String
    let url: String
    let publishedAt: String
    let snippet: String
    var uid: String { board + ":" + id }
}

struct MarketResult: Decodable {
    struct Sources: Decodable { let hh: Bool; let avito: Bool }
    let items: [MarketVacancy]
    let sources: Sources
}

/// Resume of a craftsman (owner-only search on hh.ru / Avito).
struct MarketResume: Decodable, Identifiable, Hashable {
    let board: String
    let id: String
    let name: String
    let title: String
    let city: String
    let age: Int?
    let experience: String
    let salary: String
    let photo: String
    let lastJob: String
    let url: String
    let updatedAt: String
    var uid: String { board + ":" + id }
}

struct ResumeResult: Decodable {
    let items: [MarketResume]
    let errors: [String: String]
}

struct HHChat: Decodable {
    let canWrite: Bool
    let messages: [HHMessage]
}

private struct HHPublishResult: Decodable {
    let status: String
    let vacancyId: String
    let url: String
    let token: String
    let note: String?
}

enum HHError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct HHClient {
    let base: URL
    var board: JobBoard = .hh
    private var prefix: String { "/v1/\(board.rawValue)" }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()

    private func request(_ path: String, token: String? = nil, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: URL(string: base.absoluteString + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        if let token { request.setValue(token, forHTTPHeaderField: "X-HH-Order-Token"); request.setValue(token, forHTTPHeaderField: "X-Order-Token") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func load<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw HHError.message(message ?? (status == 404 ? "Связь с \(board.title) на сервере ещё не настроена." : "\(board.title): ошибка \(status)."))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func publish(_ order: WorkOrder) async throws -> (link: HHLink, note: String?) {
        let body: [String: Any] = ["orderId": order.id, "category": order.category, "city": order.city, "details": order.details, "budget": order.budget]
        let result = try await load(try request("\(prefix)/vacancies", body: body), as: HHPublishResult.self)
        return (HHLink(vacancyId: result.vacancyId, token: result.token, url: result.url), result.note)
    }

    func market(text: String, city: String, board: String, page: Int) async throws -> MarketResult {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "city", value: city), URLQueryItem(name: "board", value: board), URLQueryItem(name: "page", value: String(page))]
        return try await load(try request("/v1/market/vacancies?" + (components.percentEncodedQuery ?? "")), as: MarketResult.self)
    }

    func resumes(text: String, city: String, board: String, page: Int, ownerKey: String) async throws -> ResumeResult {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "city", value: city), URLQueryItem(name: "board", value: board), URLQueryItem(name: "page", value: String(page))]
        var request = try request("/v1/market/resumes?" + (components.percentEncodedQuery ?? ""))
        request.setValue(ownerKey, forHTTPHeaderField: "X-Admin-Key")
        return try await load(request, as: ResumeResult.self)
    }

    func checkOwner(_ key: String) async throws {
        struct OK: Decodable { let ok: Bool }
        var request = try request("/v1/market/owner")
        request.setValue(key, forHTTPHeaderField: "X-Admin-Key")
        _ = try await load(request, as: OK.self)
    }

    func responses(orderID: String, token: String) async throws -> HHResponses {
        try await load(try request("\(prefix)/orders/\(Self.escape(orderID))/responses", token: token), as: HHResponses.self)
    }

    func chat(orderID: String, token: String, chatID: String) async throws -> HHChat {
        try await load(try request("\(prefix)/orders/\(Self.escape(orderID))/chats/\(Self.escape(chatID))/messages", token: token), as: HHChat.self)
    }

    func send(orderID: String, token: String, chatID: String, text: String) async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await load(try request("\(prefix)/orders/\(Self.escape(orderID))/chats/\(Self.escape(chatID))/messages", token: token, body: ["text": text]), as: OK.self)
    }

    private static func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value }
}
