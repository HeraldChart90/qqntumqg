import Foundation
import UIKit

/// Black Forest Labs FLUX.1 Kontext: photorealistic edit of an input image (3D render or photo) by a text prompt.
/// Docs: https://docs.bfl.ai — POST /v1/flux-kontext-pro, header x-key, then poll `polling_url` until "Ready".
struct FluxClient {
    enum Model: String { case pro = "flux-kontext-pro", max = "flux-kontext-max" }

    let apiKey: String
    var model: Model = .pro

    /// Key from FluxKey.plist (owner's own builds) or the Keychain.
    static var configuredKey: String? {
        if let saved = KeychainStore.read("bfl-api-key") { return saved }
        #if !DEBUG
        return nil // in the App Store build FLUX works only through the AI server
        #endif
        guard let url = Bundle.main.url(forResource: "FluxKey", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist["BFL_API_KEY"] as? String, !raw.contains("ВСТАВЬТЕ") else { return nil }
        let key = sanitize(raw)
        return key.count >= 20 ? key : nil
    }
    static var isConfigured: Bool { configuredKey != nil }

    /// Removes what often sneaks in when copying a key: quotes, spaces, line breaks, invisible characters, "x-key:" prefix.
    static func sanitize(_ raw: String) -> String {
        var key = raw
        for prefix in ["x-key:", "X-Key:", "BFL_API_KEY=", "Bearer "] where key.hasPrefix(prefix) { key = String(key.dropFirst(prefix.count)) }
        return String(key.unicodeScalars.filter { $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\"" && $0 != "'" && $0 != "«" && $0 != "»" }.map(Character.init))
    }

    private static let base = URL(string: "https://api.bfl.ai/v1/")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 240
        return URLSession(configuration: configuration)
    }()

    enum FluxError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1536
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.88)
    }

    private static func failure(status: Int, data: Data) -> FluxError {
        let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { raw -> String? in
            if let text = raw["detail"] as? String { return text }
            if let list = raw["detail"] as? [[String: Any]] { return list.compactMap { $0["msg"] as? String }.joined(separator: "; ") }
            return raw["message"] as? String
        }
        switch status {
        case 401, 403: return .message("Ключ FLUX не подошёл. Проверьте его в FluxKey.plist.")
        case 402: return .message("На счёте FLUX закончились кредиты. Пополните баланс на bfl.ai.")
        case 429: return .message("FLUX занят: слишком много одновременных задач. Попробуйте через минуту.")
        default: return .message("FLUX: \(detail ?? "ошибка \(status)")")
        }
    }

    /// Sends the image with the prompt, waits for the result (usually 5–30 s) and downloads it.
    func edit(_ image: UIImage, prompt: String) async throws -> UIImage {
        guard let jpeg = Self.jpeg(image) else { throw FluxError.message("Не удалось подготовить изображение.") }
        var request = URLRequest(url: Self.base.appendingPathComponent(model.rawValue))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let body: [String: Any] = [
            "prompt": String(prompt.prefix(2500)),
            "input_image": jpeg.base64EncodedString(),
            "output_format": "jpeg",
            "safety_tolerance": 2,
            "prompt_upsampling": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await submitAndWait(request)
    }

    /// FLUX.2 [pro] text-to-image: a finished photo from a detailed description (no input image → no layout blocks).
    func generate(prompt: String, width: Int = 1536, height: Int = 1024) async throws -> UIImage {
        var request = URLRequest(url: Self.base.appendingPathComponent("flux-2-pro"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let body: [String: Any] = [
            "prompt": String(prompt.prefix(3000)),
            "width": width,
            "height": height,
            "output_format": "jpeg",
            "safety_tolerance": 2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await submitAndWait(request)
    }

    private func submitAndWait(_ request: URLRequest) async throws -> UIImage {
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw Self.failure(status: status, data: data) }
        guard let created = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pollingString = created["polling_url"] as? String, let pollingURL = URL(string: pollingString) else {
            throw FluxError.message("FLUX не вернул номер задачи.")
        }

        // Poll until ready (max ~3 minutes).
        let started = Date()
        while Date().timeIntervalSince(started) < 180 {
            try await Task.sleep(for: .milliseconds(1200))
            var poll = URLRequest(url: pollingURL)
            poll.setValue(apiKey, forHTTPHeaderField: "x-key")
            poll.setValue("application/json", forHTTPHeaderField: "accept")
            let (pollData, pollResponse) = try await Self.session.data(for: poll)
            let pollStatus = (pollResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(pollStatus) else { throw Self.failure(status: pollStatus, data: pollData) }
            guard let raw = try JSONSerialization.jsonObject(with: pollData) as? [String: Any], let state = raw["status"] as? String else { continue }
            switch state {
            case "Ready":
                guard let result = raw["result"] as? [String: Any], let sample = result["sample"] as? String, let sampleURL = URL(string: sample) else {
                    throw FluxError.message("FLUX не вернул картинку.")
                }
                // Signed URL lives 10 minutes: download right away.
                let (imageData, _) = try await Self.session.data(from: sampleURL)
                guard let output = UIImage(data: imageData) else { throw FluxError.message("Не удалось открыть картинку FLUX.") }
                return output
            case "Request Moderated", "Content Moderated":
                throw FluxError.message("FLUX отклонил запрос модерацией. Измените описание или ракурс.")
            case "Error", "Failed", "Task not found", "No Card Generated":
                throw FluxError.message("FLUX не смог создать изображение (\(state)). Попробуйте ещё раз.")
            default:
                continue // Pending, Reasoning, Generating
            }
        }
        throw FluxError.message("FLUX не успел за 3 минуты. Попробуйте ещё раз.")
    }
}
