import SwiftUI

/// «Резюме мастеров»: craftsmen with photos from hh.ru and Avito Работа. Only for the owner of АртСтрой
/// (resumes are personal data of applicants and must not be shown to the app's clients).
struct ResumeSearchSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var key = ""
    @State private var unlocking = false
    @State private var text = ""
    @State private var city = "Сочи"
    @State private var board = "all"
    @State private var items: [MarketResume] = []
    @State private var errors: [String: String] = [:]
    @State private var page = 0
    @State private var isLoading = false
    @State private var searched = false
    @State private var error: String?
    @State private var opened: MarketVacanciesSection.MarketLink?

    private let quick = ["Отделочник", "Плиточник", "Сантехник", "Электрик", "Маляр", "Кровельщик", "Сварщик", "Бетонщик", "Разнорабочий"]

    var body: some View {
        if store.ownerUnlocked { search } else { lock }
    }

    // MARK: Owner lock

    private var lock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.black)
                    .frame(width: 48, height: 48).background(Theme.orange, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Только для владельца").font(.headline)
                    Text("Резюме с фото — личные данные соискателей. Раздел открывается ключом владельца АртСтроя.").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            SecureField("Ключ владельца (HH_ADMIN_KEY с сервера)", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).panelCard(14)
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }
            PrimaryButton(title: unlocking ? "Проверяем…" : "Открыть резюме", icon: "key.fill") {
                Task {
                    unlocking = true
                    defer { unlocking = false }
                    do { try await store.unlockOwner(key); key = ""; error = nil; Haptics.success() }
                    catch { self.error = error.localizedDescription; Haptics.warning() }
                }
            }
            .disabled(unlocking || key.trimmingCharacters(in: .whitespaces).count < 16)
        }
        .padding(18).panelCard(20)
    }

    // MARK: Search

    private var search: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.orange)
                TextField("Профессия или навык", text: $text).submitLabel(.search).onSubmit { Task { await run(reset: true) } }
                Divider().frame(height: 22)
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.muted)
                TextField("Город", text: $city).frame(maxWidth: 92).submitLabel(.search).onSubmit { Task { await run(reset: true) } }
            }
            .padding(14).panelCard(16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quick, id: \.self) { word in
                        Button { Haptics.tap(); text = word; Task { await run(reset: true) } } label: {
                            Text(word).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                                .background(text == word ? Theme.orange : Theme.panel, in: Capsule())
                                .foregroundStyle(text == word ? .black : .white)
                        }
                    }
                }
            }

            Picker("Площадка", selection: $board) {
                Text("Все").tag("all"); Text("hh.ru").tag("hh"); Text("Avito").tag("avito")
            }
            .pickerStyle(.segmented)
            .onChange(of: board) { _, _ in Task { await run(reset: true) } }

            ForEach(errors.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                Label("\(item.key == "hh" ? "hh.ru" : "Avito"): \(item.value)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.muted)
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }

            if items.isEmpty && !isLoading {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle.stack").font(.title2).foregroundStyle(Theme.orange)
                    Text(searched ? "Никого не нашлось" : "Выберите профессию").font(.headline)
                    Text("Ищем мастеров по резюме на hh.ru и Avito в выбранном городе.").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(24).panelCard(20)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(items, id: \.uid) { resume in
                    Button { if let url = URL(string: resume.url) { opened = .init(url: url) } } label: { ResumeCard(resume: resume) }
                        .buttonStyle(PremiumCardPressStyle())
                }
            }
            if isLoading { ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(16) }
            if !items.isEmpty && !isLoading {
                Button { Task { await run(reset: false) } } label: { SecondaryActionLabel(title: "Показать ещё", icon: "arrow.down.circle") }
                    .buttonStyle(PremiumPressStyle())
            }
            HStack {
                InfoNote(text: "Контакты открываются на сайте площадки по вашему тарифу. Не пересылайте резюме третьим лицам.")
            }
            Button("Выйти из режима владельца") { store.lockOwner(); items = [] }.font(.caption).foregroundStyle(Theme.muted)
        }
        .task { if items.isEmpty { text = text.isEmpty ? "Отделочник" : text; await run(reset: true) } }
        .sheet(item: $opened) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    private func run(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; searched = true }
        let next = reset ? 0 : page + 1
        do {
            let result = try await store.searchResumes(text: text.trimmingCharacters(in: .whitespaces), city: city.trimmingCharacters(in: .whitespaces), board: board, page: next)
            withAnimation(.snappy) {
                if reset { items = result.items } else { items += result.items.filter { new in !items.contains { $0.uid == new.uid } } }
            }
            errors = result.errors
            page = next
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ResumeCard: View {
    let resume: MarketResume
    private var isHH: Bool { resume.board == "hh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = URL(string: resume.photo), !resume.photo.isEmpty {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { placeholder }
                        }
                    } else { placeholder }
                }
                .frame(maxWidth: .infinity).frame(height: 150).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(isHH ? "hh" : "A").font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(isHH ? Color(red: 0.85, green: 0.1, blue: 0.13) : Color(red: 0.0, green: 0.6, blue: 0.95), in: Circle())
                    .padding(6)
            }
            Text(resume.title.isEmpty ? "Мастер" : resume.title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
            if !resume.name.isEmpty { Text(resume.name).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1) }
            if !resume.salary.isEmpty { Text(resume.salary).font(.caption.weight(.bold)).foregroundStyle(Theme.orange) }
            Text([resume.city, resume.experience.isEmpty ? "" : "опыт \(resume.experience)", resume.age.map { "\($0) лет" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
            if !resume.lastJob.isEmpty { Text(resume.lastJob).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(16)
    }

    private var placeholder: some View {
        ZStack {
            Theme.panelRaised
            Image(systemName: "person.fill").font(.system(size: 44)).foregroundStyle(Theme.muted)
        }
    }
}
