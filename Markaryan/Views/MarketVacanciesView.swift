import SwiftUI
import SafariServices

/// «Вакансии рынка»: what other employers offer on hh.ru and Avito Работа for construction in your city.
struct MarketVacanciesSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var text = ""
    @State private var city = "Сочи"
    @State private var board = "all"
    @State private var items: [MarketVacancy] = []
    @State private var sources: MarketResult.Sources?
    @State private var page = 0
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var error: String?
    @State private var opened: MarketLink?

    private let quick = ["Отделочник", "Плиточник", "Сантехник", "Электрик", "Кровельщик", "Сварщик", "Бетонщик", "Разнорабочий"]

    struct MarketLink: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Что предлагают другие работодатели на hh.ru и Avito: ставки, условия, спрос на мастеров. Нажмите на вакансию — откроется на сайте.")
                .font(.caption).foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.orange)
                TextField("Профессия или работа", text: $text)
                    .submitLabel(.search)
                    .onSubmit { Task { await search(reset: true) } }
                Divider().frame(height: 22)
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.muted)
                TextField("Город", text: $city).frame(maxWidth: 92)
                    .submitLabel(.search)
                    .onSubmit { Task { await search(reset: true) } }
            }
            .padding(14).panelCard(16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quick, id: \.self) { word in
                        Button {
                            Haptics.tap(); text = word
                            Task { await search(reset: true) }
                        } label: {
                            Text(word).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                                .background(text == word ? Theme.orange : Theme.panel, in: Capsule())
                                .foregroundStyle(text == word ? .black : .white)
                        }
                    }
                }
            }

            Picker("Площадка", selection: $board) {
                Text("Все").tag("all")
                Text("hh.ru").tag("hh")
                Text("Avito").tag("avito")
            }
            .pickerStyle(.segmented)
            .onChange(of: board) { _, _ in Task { await search(reset: true) } }

            if let sources, (!sources.hh || !sources.avito), board == "all" {
                Label(!sources.hh && !sources.avito ? "Площадки сейчас не ответили. Потяните вниз, чтобы обновить." : (!sources.hh ? "hh.ru сейчас не ответил — показаны вакансии Avito." : "Avito сейчас не ответил — показаны вакансии hh.ru."), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }

            if items.isEmpty && !isLoading {
                VStack(spacing: 10) {
                    Image(systemName: "briefcase").font(.title2).foregroundStyle(Theme.orange)
                    Text(sources == nil ? "Ищем вакансии…" : "Ничего не нашлось").font(.headline)
                    Text("Попробуйте другую профессию или город.").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(24).panelCard(20)
            }

            LazyVStack(spacing: 12) {
                ForEach(items, id: \.uid) { vacancy in
                    Button {
                        if let url = URL(string: vacancy.url) { opened = MarketLink(url: url) }
                    } label: { MarketVacancyCard(vacancy: vacancy) }
                    .buttonStyle(PremiumCardPressStyle())
                }
                if isLoading { ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(16) }
                if !items.isEmpty && canLoadMore && !isLoading && board != "avito" {
                    Button { Task { await search(reset: false) } } label: { SecondaryActionLabel(title: "Показать ещё", icon: "arrow.down.circle") }
                        .buttonStyle(PremiumPressStyle())
                }
            }
        }
        .task { if items.isEmpty { await search(reset: true) } }
        .sheet(item: $opened) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    private func search(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let next = reset ? 0 : page + 1
        do {
            let result = try await store.searchMarket(text: text.trimmingCharacters(in: .whitespaces), city: city.trimmingCharacters(in: .whitespaces), board: board, page: next)
            withAnimation(.snappy) {
                if reset { items = result.items } else { items += result.items.filter { new in !items.contains { $0.uid == new.uid } } }
            }
            sources = result.sources
            page = next
            canLoadMore = !result.items.isEmpty
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct MarketVacancyCard: View {
    let vacancy: MarketVacancy
    private var isHH: Bool { vacancy.board == "hh" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(isHH ? "hh" : "A").font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(isHH ? Color(red: 0.85, green: 0.1, blue: 0.13) : Color(red: 0.0, green: 0.6, blue: 0.95), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(vacancy.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(2)
                if !vacancy.salary.isEmpty {
                    Text(vacancy.salary).font(.subheadline.weight(.bold)).foregroundStyle(Theme.orange)
                }
                Text([vacancy.company, vacancy.city].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                if !vacancy.snippet.isEmpty {
                    Text(vacancy.snippet).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(2).multilineTextAlignment(.leading)
                }
                if let date = Self.date(vacancy.publishedAt) {
                    Text(date).font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right.square").font(.subheadline).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(16)
    }

    private static func date(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        let fixed = raw.replacingOccurrences(of: #"([+-]\d{2})(\d{2})$"#, with: "$1:$2", options: .regularExpression)
        guard let date = parser.date(from: fixed) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }
}

/// In-app Safari for vacancy pages.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
