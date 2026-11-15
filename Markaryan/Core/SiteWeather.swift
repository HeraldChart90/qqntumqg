import SwiftUI

/// 5‑day forecast for Sochi with a simple verdict for outdoor works (concrete, masonry, roofing).
/// Data: Open‑Meteo (free, no key, no personal data — fixed city coordinates, location is never requested).
struct SiteWeatherDay: Identifiable, Equatable {
    let date: Date
    let maxTemp: Double
    let minTemp: Double
    let precipitation: Double
    let rainChance: Double
    let wind: Double
    var id: Date { date }

    enum Verdict { case good, caution, bad }

    var verdict: Verdict {
        if precipitation >= 5 || rainChance >= 75 || wind >= 50 || minTemp < 0 { return .bad }
        if precipitation >= 1 || rainChance >= 45 || wind >= 35 || minTemp < 5 { return .caution }
        return .good
    }
    var verdictTitle: String {
        switch verdict {
        case .good: return "Хороший день для наружных работ"
        case .caution: return "Работы возможны с оглядкой"
        case .bad: return "Лучше перенести бетон и кровлю"
        }
    }
    var advice: String {
        if minTemp < 0 { return "Мороз ночью: бетону нужен прогрев и укрытие." }
        if minTemp < 5 { return "Холодно ночью: укройте свежий бетон и кладку." }
        if precipitation >= 5 || rainChance >= 75 { return "Дождь: не бетонируйте открытые конструкции, закройте материалы." }
        if wind >= 50 { return "Сильный ветер: не работайте на кровле и с краном." }
        if maxTemp >= 30 { return "Жара: поливайте бетон водой первые 3–7 дней." }
        if precipitation >= 1 || rainChance >= 45 { return "Возможен дождь: держите плёнку под рукой." }
        return "Можно бетонировать, вести кладку и кровельные работы."
    }
    var color: Color {
        switch verdict { case .good: return Theme.success; case .caution: return Theme.orangeSoft; case .bad: return Theme.danger }
    }
    var symbol: String {
        if precipitation >= 5 || rainChance >= 70 { return "cloud.rain.fill" }
        if precipitation >= 1 || rainChance >= 40 { return "cloud.drizzle.fill" }
        if wind >= 40 { return "wind" }
        if maxTemp >= 28 { return "sun.max.fill" }
        return "cloud.sun.fill"
    }
}

@MainActor final class SiteWeatherModel: ObservableObject {
    @Published var days: [SiteWeatherDay] = []
    @Published var failed = false
    private var loadedAt: Date?

    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_sum: [Double?]
            let precipitation_probability_max: [Double?]
            let wind_speed_10m_max: [Double?]
        }
        let daily: Daily
    }

    func load(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 1800, !days.isEmpty { return }
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=43.5855&longitude=39.7231&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max&timezone=Europe%2FMoscow&forecast_days=5") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let daily = try JSONDecoder().decode(Response.self, from: data).daily
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(identifier: "Europe/Moscow")
            parser.dateFormat = "yyyy-MM-dd"
            var result: [SiteWeatherDay] = []
            for index in daily.time.indices {
                guard let date = parser.date(from: daily.time[index]) else { continue }
                func value(_ array: [Double?]) -> Double { index < array.count ? (array[index] ?? 0) : 0 }
                result.append(SiteWeatherDay(date: date, maxTemp: value(daily.temperature_2m_max), minTemp: value(daily.temperature_2m_min), precipitation: value(daily.precipitation_sum), rainChance: value(daily.precipitation_probability_max), wind: value(daily.wind_speed_10m_max)))
            }
            days = result
            failed = result.isEmpty
            loadedAt = .now
        } catch {
            failed = days.isEmpty
        }
    }
}

struct SiteWeatherCard: View {
    @StateObject private var model = SiteWeatherModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ПОГОДА НА СТРОЙКЕ · СОЧИ", systemImage: "cloud.sun.fill")
                    .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(Theme.muted)
                Spacer()
                if model.days.isEmpty && !model.failed { ProgressView().controlSize(.small).tint(Theme.orange) }
            }
            if let today = model.days.first {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: today.symbol).symbolRenderingMode(.multicolor).font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(today.maxTemp.rounded()))° / \(Int(today.minTemp.rounded()))°").font(.title2.bold()).monospacedDigit()
                        HStack(spacing: 6) {
                            Circle().fill(today.color).frame(width: 7, height: 7)
                            Text(today.verdictTitle).font(.caption.weight(.semibold)).foregroundStyle(today.color)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(today.advice).font(.footnote).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    ForEach(model.days.dropFirst()) { day in
                        VStack(spacing: 6) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                            Image(systemName: day.symbol).symbolRenderingMode(.multicolor).font(.callout)
                            Text("\(Int(day.maxTemp.rounded()))°").font(.caption.weight(.semibold)).monospacedDigit()
                            Capsule().fill(day.color).frame(width: 18, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))): \(Int(day.maxTemp.rounded())) градусов. \(day.verdictTitle)")
                    }
                }
            } else if model.failed {
                HStack {
                    Text("Прогноз недоступен без интернета.").font(.footnote).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Повторить") { Task { await model.load(force: true) } }.font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(18)
        .panelCard(22)
        .task { await model.load() }
    }
}
