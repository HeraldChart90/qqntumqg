import SwiftUI

/// Cards inside an order: hh.ru and Avito vacancies and the way to responses.
struct HHOrderCard: View {
    let order: WorkOrder
    var body: some View {
        VStack(spacing: 10) {
            ForEach(JobBoard.allCases) { board in BoardOrderCard(order: order, board: board) }
        }
    }
}

struct BoardOrderCard: View {
    @EnvironmentObject private var store: AppStore
    let order: WorkOrder
    let board: JobBoard
    private var color: Color { board == .hh ? Color(red: 0.85, green: 0.1, blue: 0.13) : Color(red: 0.0, green: 0.6, blue: 0.95) }

    var body: some View {
        if let link = store.boardLink(board, order.id) {
            NavigationLink { HHResponsesView(order: order, board: board) } label: {
                HStack(spacing: 12) {
                    Text(board.badge).font(.headline.weight(.heavy)).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(color, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Отклики с \(board.title)").font(.headline).foregroundStyle(.white)
                        Text("Вакансия №\(link.vacancyId) · чат с исполнителями в приложении").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                }
                .padding(14).panelCard(16)
            }
            .buttonStyle(PremiumCardPressStyle())
        } else if store.isPublishing(board, order.id) {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.orange)
                Text("Публикуем заявку на \(board.title)…").font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).panelCard(16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let note = store.boardNote(board, order.id) {
                    Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(Theme.muted)
                }
                Button { Task { await store.publish(order, to: board) } } label: {
                    SecondaryActionLabel(title: "Опубликовать на \(board.title)", icon: "megaphone.fill")
                }
                .buttonStyle(PremiumPressStyle())
            }
        }
    }
}

struct HHResponsesView: View {
    @EnvironmentObject private var store: AppStore
    let order: WorkOrder
    var board: JobBoard = .hh
    @State private var data: HHResponses?
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let vacancy = data?.vacancy {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vacancy.title).font(.headline)
                        HStack {
                            Text(vacancy.status).font(.caption.weight(.bold)).foregroundStyle(Theme.orange)
                            Spacer()
                            if let url = URL(string: vacancy.url) { Link("Открыть на \(board.title)", destination: url).font(.caption.weight(.semibold)) }
                        }
                    }
                    .padding(16).panelCard(16)
                }
                if isLoading && data == nil { ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(30) }
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }
                if let data, data.applicants.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.clock").font(.title).foregroundStyle(Theme.orange)
                        Text("Откликов пока нет").font(.headline)
                        Text("После модерации \(board.title) вакансию увидят исполнители. Отклики появятся здесь, писать им можно прямо из приложения.")
                            .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(24).panelCard(18)
                }
                ForEach(data?.applicants ?? []) { applicant in
                    NavigationLink { HHChatView(order: order, applicant: applicant, board: board) } label: { HHApplicantRow(applicant: applicant) }
                        .buttonStyle(PremiumCardPressStyle())
                        .disabled(applicant.chatId == nil)
                }
                InfoNote(text: "Отклики приходят с \(board.title) на аккаунт АртСтроя. Контакты соискателей не показываются — договаривайтесь в чате.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Отклики \(board.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { data = try await store.boardResponses(board, orderID: order.id); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct HHApplicantRow: View {
    let applicant: HHApplicant
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(applicant.name.prefix(1))).font(.headline).foregroundStyle(.black)
                .frame(width: 42, height: 42).background(Theme.orange, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(applicant.name).font(.headline).foregroundStyle(.white)
                    Spacer()
                    if applicant.unread > 0 {
                        Text("\(applicant.unread)").font(.caption2.weight(.bold)).foregroundStyle(.black)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.orange, in: Capsule())
                    }
                }
                if !applicant.title.isEmpty { Text(applicant.title).font(.subheadline).foregroundStyle(.white.opacity(0.85)) }
                Text([applicant.area, applicant.experience.isEmpty ? "" : "опыт \(applicant.experience)", applicant.state].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted)
                if !applicant.skills.isEmpty {
                    Text(applicant.skills.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
        }
        .padding(14).panelCard(16)
    }
}

struct HHChatView: View {
    @EnvironmentObject private var store: AppStore
    let order: WorkOrder
    let applicant: HHApplicant
    var board: JobBoard = .hh
    @State private var messages: [HHMessage] = []
    @State private var canWrite = true
    @State private var text = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty { Text("Сообщений пока нет. Напишите исполнителю — ответ придёт сюда.").font(.footnote).foregroundStyle(Theme.muted).padding(16).panelCard(16) }
                        ForEach(messages) { message in
                            HStack {
                                if message.fromClient { Spacer(minLength: 40) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.name).font(.caption2.weight(.bold)).foregroundStyle(message.fromClient ? .black.opacity(0.6) : Theme.orange)
                                    Text(message.text).font(.subheadline).foregroundStyle(message.fromClient ? .black : .white)
                                }
                                .padding(12)
                                .background(message.fromClient ? Theme.orange : Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                if !message.fromClient { Spacer(minLength: 40) }
                            }
                            .id(message.id)
                        }
                        if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                TextField(canWrite ? "Сообщение исполнителю…" : "Переписка закрыта на \(board.title)", text: $text, axis: .vertical)
                    .lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 11).panelCard(18)
                    .disabled(!canWrite)
                Button { Task { await send() } } label: {
                    Image(systemName: isSending ? "hourglass" : "arrow.up").font(.headline.weight(.bold)).foregroundStyle(.black)
                        .frame(width: 46, height: 46).background(Theme.orange, in: Circle())
                }
                .disabled(isSending || !canWrite || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(applicant.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await load()
            }
        }
    }

    private func load() async {
        guard let chatID = applicant.chatId else { return }
        do {
            let chat = try await store.boardChat(board, orderID: order.id, chatID: chatID)
            if chat.messages.count != messages.count || chat.messages.last?.id != messages.last?.id { messages = chat.messages }
            canWrite = chat.canWrite
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func send() async {
        guard let chatID = applicant.chatId else { return }
        isSending = true
        defer { isSending = false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.boardSend(board, orderID: order.id, chatID: chatID, text: clean)
            text = ""
            Haptics.tap()
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
