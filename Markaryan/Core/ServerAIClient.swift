import Foundation
import UIKit

/// Common interface of the AI the app talks to: the АртСтрой AI server (release) or Claude directly (owner's debug builds).
protocol AIEngine {
    func stream(system: String, turns: [ClaudeTurn], maxTokens: Int) -> AsyncThrowingStream<String, Error>
    func complete(system: String, turns: [ClaudeTurn], maxTokens: Int) async throws -> String
    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> Data
}

extension AIEngine {
    func stream(system: String, turns: [ClaudeTurn]) -> AsyncThrowingStream<String, Error> { stream(system: system, turns: turns, maxTokens: 2000) }
    func complete(system: String, turns: [ClaudeTurn]) async throws -> String { try await complete(system: system, turns: turns, maxTokens: 1500) }
    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any]) async throws -> Data {
        try await structured(system: system, turns: turns, toolName: toolName, toolDescription: toolDescription, schema: schema, maxTokens: 4000)
    }
}

extension ClaudeClient: AIEngine {}

/// Address of the AI server and the optional app token — from AIServer.plist. No AI keys in the app.
enum AIServerConfig {
    private static var plist: [String: Any] {
        guard let url = Bundle.main.url(forResource: "AIServer", withExtension: "plist"), let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        return value
    }
    static var baseURL: URL? {
        guard let raw = (plist["AI_SERVER_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.lowercased().hasPrefix("https://"), !raw.contains("example") else { return nil }
        return URL(string: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    static var appToken: String { (plist["APP_TOKEN"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    /// Random id of this installation (kept in the Keychain): the server counts daily limits by it.
    static var installID: String {
        if let saved = KeychainStore.read("ai-install-id"), saved.count >= 16 { return saved }
        let id = UUID().uuidString
        KeychainStore.save(id, account: "ai-install-id")
        return id
    }
}

/// What the server can do right now (and how much of today's limit is left).
struct AICapabilities: Decodable {
    var chat = false
    var vision = false
    var imageGenerate = false
    var imageEdit: [String] = []
    var providers: [String] = []
}

/// Client of the АртСтрой AI server (GigaChat / YandexGPT behind it, keys only on the server).
struct ServerAIClient: AIEngine {
    let base: URL

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 200
        configuration.timeoutIntervalForResource = 320
        return URLSession(configuration: configuration)
    }()

    private func request(_ path: String, body: [String: Any]?, accept: String = "application/json") throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 200
        request.setValue(AIServerConfig.installID, forHTTPHeaderField: "X-Install-ID")
        if !AIServerConfig.appToken.isEmpty { request.setValue(AIServerConfig.appToken, forHTTPHeaderField: "X-App-Token") }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func messages(_ turns: [ClaudeTurn]) -> [[String: Any]] {
        turns.map { turn in
            var item: [String: Any] = ["role": turn.role.rawValue, "text": turn.text]
            if let image = turn.image, let jpeg = ClaudeClient.jpeg(image) { item["image"] = jpeg.base64EncodedString() }
            return item
        }
    }

    private static func failure(_ data: Data, status: Int) -> Error {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        switch status {
        case 429: return ClaudeError.api(message ?? "Дневной лимит ИИ исчерпан. Попробуйте завтра.")
        case 503: return ClaudeError.api(message ?? "ИИ временно недоступен. Попробуйте позже.")
        default: return ClaudeError.api(message ?? "Сервер ИИ ответил с кодом \(status).")
        }
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let (data, response) = try await Self.session.data(for: try request(path, body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Self.failure(data, status: status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeError.badResponse }
        return json
    }

    func stream(system: String, turns: [ClaudeTurn], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: [String: Any] = ["system": system, "messages": Self.messages(turns), "maxTokens": maxTokens, "stream": true]
                    let (bytes, response) = try await Self.session.bytes(for: try request("v1/ai/chat", body: body, accept: "text/event-stream"))
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(status) else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.failure(data, status: status)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                        if let delta = event["delta"] as? String { continuation.yield(delta) }
                        if let error = event["error"] as? String { throw ClaudeError.api(error) }
                        if event["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func complete(system: String, turns: [ClaudeTurn], maxTokens: Int) async throws -> String {
        let json = try await post("v1/ai/chat", ["system": system, "messages": Self.messages(turns), "maxTokens": maxTokens])
        guard let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeError.emptyAnswer }
        return text
    }

    func structured(system: String, turns: [ClaudeTurn], toolName: String, toolDescription: String, schema: [String: Any], maxTokens: Int) async throws -> Data {
        let body: [String: Any] = ["system": system, "messages": Self.messages(turns), "name": toolName, "description": toolDescription, "schema": schema, "maxTokens": maxTokens]
        do {
            let json = try await post("v1/ai/json", body)
            guard let result = json["json"] else { throw ClaudeError.badResponse }
            return try JSONSerialization.data(withJSONObject: result)
        } catch let error as URLError where [.networkConnectionLost, .timedOut].contains(error.code) {
            let json = try await post("v1/ai/json", body) // one retry on a dropped mobile connection
            guard let result = json["json"] else { throw ClaudeError.badResponse }
            return try JSONSerialization.data(withJSONObject: result)
        }
    }

    // MARK: Images

    func capabilities() async throws -> AICapabilities {
        let (data, response) = try await Self.session.data(for: try request("v1/ai/capabilities", body: nil))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Self.failure(data, status: status) }
        return try JSONDecoder().decode(AICapabilities.self, from: data)
    }

    /// Photoreal edit of the exact 3D render on the server ("flux" or "gpt").
    func editImage(_ image: UIImage, prompt: String, engine: String) async throws -> UIImage {
        let maxSide: CGFloat = 1536
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.88) else { throw ClaudeError.api("Не удалось подготовить изображение.") }
        let json = try await post("v1/ai/image-edit", ["image": jpeg.base64EncodedString(), "prompt": prompt, "engine": engine, "size": "1536x1152"])
        guard let base64 = json["image"] as? String, let data = Data(base64Encoded: base64), let result = UIImage(data: data) else { throw ClaudeError.badResponse }
        return result
    }

    /// Picture by description (Kandinsky / YandexART on the server).
    func generateImage(prompt: String) async throws -> UIImage {
        let json = try await post("v1/ai/image", ["prompt": prompt])
        guard let base64 = json["image"] as? String, let data = Data(base64Encoded: base64), let result = UIImage(data: data) else { throw ClaudeError.badResponse }
        return result
    }
}
