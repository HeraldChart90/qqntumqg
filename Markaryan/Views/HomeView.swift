import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "ДОБРОЕ УТРО"
        case 12..<18: return "ДОБРЫЙ ДЕНЬ"
        case 18..<23: return "ДОБРЫЙ ВЕЧЕР"
        default: return "ДОБРОЙ НОЧИ"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image("BrandMark").resizable().scaledToFit().frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("АРТСТРОЙ").font(.headline).tracking(1.2)
                        Text("ИП МАРКАРЯН А.В. · СОЧИ").font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Link(destination: Brand.phoneURL) {
                        Image(systemName: "phone.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                            .frame(width: 40, height: 40).background(Theme.orange, in: Circle())
                    }
                    .accessibilityLabel("Позвонить в АртСтрой")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Theme.orange)
                    Text("Стройка —\nв одном месте.").font(.system(.largeTitle, design: .default, weight: .bold)).tracking(-1.25)
                    Text("Смета, AR‑замеры, ИИ‑помощник и контроль объекта — от идеи до приёмки.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                if let alert = store.priceAlert { PriceAlertBanner(text: alert) { store.priceAlert = nil } }

                NavigationLink { ProjectHubView() } label: {
                    HomeProjectCard(name: store.projectDisplayName, stage: store.passport.stage, progress: store.projectProgress, next: store.nextMilestone?.title, planned: store.budgetPlanned, actual: store.budgetActual)
                }
                .buttonStyle(PremiumCardPressStyle())

                SectionTitle(eyebrow: "Быстрый старт", title: "Что делаем сегодня?")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    NavigationLink { FullEstimateHubView() } label: { HomeActionCard(icon: "house.and.flag.fill", title: "Смета дома", subtitle: "Работы и материалы", accent: Theme.orange) }
                    NavigationLink { AIAssistantView(context: .general) } label: { HomeActionCard(icon: "sparkles", title: "СтройПомощник", subtitle: "Спросить ИИ", accent: Theme.success) }
                    Button { store.showAR = true } label: { HomeActionCard(icon: "viewfinder", title: "AR‑замер", subtitle: "Площадь камерой", accent: Theme.sky) }
                    NavigationLink { AIVisionStudioView(initialStyle: .object) } label: { HomeActionCard(icon: "wand.and.stars", title: "Визуализация", subtitle: "Дом по фото", accent: Theme.orangeSoft) }
                }
                .buttonStyle(PremiumCardPressStyle())

                NavigationLink { FloorPlansView() } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "cube.transparent").font(.title2.weight(.semibold)).foregroundStyle(.black)
                            .frame(width: 52, height: 52).background(Theme.sky, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("НОВОЕ · СКАН КОМНАТЫ").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(Theme.sky)
                            Text("Планировка и дизайн по скану").font(.headline).foregroundStyle(.white)
                            Text("План сверху, мебель и бюджет от ИИ").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                    .padding(16).panelCard(20)
                }
                .buttonStyle(PremiumCardPressStyle())

                SiteWeatherCard()

                if !store.calculations.isEmpty {
                    HStack {
                        SectionTitle(eyebrow: "Недавнее", title: "Мои расчёты")
                        Spacer()
                        NavigationLink("Все") { CalculationHistoryView() }.font(.subheadline.weight(.semibold))
                    }
                    ForEach(store.calculations.prefix(2)) { item in
                        NavigationLink { SavedCalculationView(item: item) } label: {
                            AppTabRow(icon: item.kind.icon, title: item.kind.title, subtitle: "\(item.object) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                        }
                        .buttonStyle(PremiumCardPressStyle())
                    }
                }

                SectionTitle(eyebrow: "Почему АртСтрой", title: "Строим с \(String(Brand.foundedYear)) года")
                HStack(spacing: 10) {
                    HomeMetric(value: "\(Brand.yearsOnMarket)", caption: "лет в Сочи")
                    HomeMetric(value: "\(Brand.completedObjects)+", caption: "объектов")
                    HomeMetric(value: "\(store.calculations.count)", caption: "ваших расчётов")
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["Смета и договор до начала работ", "Этапы по актам и фотоотчётам", "Полный цикл: от фундамента до благоустройства"], id: \.self) { item in
                        Label(item, systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(.white)
                            .symbolRenderingMode(.palette).foregroundStyle(Theme.orange, .white)
                    }
                    NavigationLink { PortfolioView() } label: {
                        HStack { Text("Смотреть объекты").font(.subheadline.weight(.semibold)); Image(systemName: "arrow.right") }.foregroundStyle(Theme.orange)
                    }
                    .padding(.top, 4)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).panelCard(20)

                PrimaryButton(title: "Получить точную смету от АртСтроя", icon: "square.and.pencil") { store.showRequest = true }
                Link(destination: Brand.whatsAppURL(text: "Здравствуйте! Хочу обсудить объект: \(store.projectDisplayName), \(store.projectCity).")) {
                    SecondaryActionLabel(title: "Написать в WhatsApp", icon: "message.fill")
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refreshPriceBook(silent: true) }
    }
}

struct PriceAlertBanner: View {
    let text: String
    let onClose: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.title3).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 5) { Text("Цены обновились").font(.headline); Text(text).font(.caption).foregroundStyle(Theme.muted) }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(Theme.muted).padding(4) }.accessibilityLabel("Скрыть")
        }
        .padding(16).background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct HomeProjectCard: View {
    let name: String
    let stage: String
    let progress: Double
    let next: String?
    let planned: Double
    let actual: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ТЕКУЩИЙ ОБЪЕКТ").font(.caption2.weight(.bold)).tracking(1.25).foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text("\(Int(progress * 100))%").font(.headline.bold()).monospacedDigit().foregroundStyle(Theme.orange)
            }
            Text(name).font(.title3.bold()).foregroundStyle(.white)
            ProgressView(value: progress).tint(Theme.orange)
            HStack(spacing: 7) {
                Circle().fill(Theme.success).frame(width: 7, height: 7)
                Text(next.map { "Этап: \(stage) · далее: \($0)" } ?? "Все этапы закрыты").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
            }
            if planned > 0 {
                HStack {
                    Text("Бюджет \(CalculationEngine.money(planned))").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("потрачено \(CalculationEngine.money(actual))").font(.caption).foregroundStyle(actual > planned ? Theme.danger : Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.orange.opacity(0.18), lineWidth: 1))
    }
}

struct HomeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(accent)
                .frame(width: 40, height: 40).background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 4)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            Text(subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(16)
        .panelCard(19)
    }
}

struct HomeMetric: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(.white)
            Text(caption).font(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panelCard(16)
    }
}

struct ObjectPassportView: View {
    @EnvironmentObject private var store: AppStore
    private let stages = ["Планирование", "Подготовка", "Фундамент", "Коробка", "Кровля", "Отделка", "Сдан"]
    var body: some View {
        Form {
            Section("Объект") {
                TextField("Название объекта", text: $store.passport.name)
                TextField("Адрес или район", text: $store.passport.address)
                TextField("Площадь, м²", text: $store.passport.area).keyboardType(.decimalPad)
                Picker("Текущий этап", selection: $store.passport.stage) { ForEach(stages, id: \.self) { Text($0) } }
            }
            Section("Заметка") { TextEditor(text: $store.passport.notes).frame(minHeight: 110) }
            Section("Рабочие инструменты") {
                NavigationLink { ChecklistView() } label: { Label("Чек-лист контроля", systemImage: "checklist") }
                NavigationLink { ProjectBudgetTrackerView() } label: { Label("Бюджет по этапам", systemImage: "rublesign.circle") }
                NavigationLink { ConstructionDiaryView() } label: { Label("Журнал решений", systemImage: "book.closed") }
            }
            Section { Button("Добавить паспорт в заявку") { addToRequest() }.fontWeight(.semibold) }
            Section { Text("Паспорт, чек-листы и дневник хранятся только на этом iPhone. Подрядчик увидит их лишь если вы добавите данные в заявку.").font(.footnote).foregroundStyle(Theme.muted) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Паспорт объекта")
    }
    private func addToRequest() {
        store.draft.address = store.passport.address
        if ["Планирование", "Проект готов", "Строительство", "Ремонт и реконструкция"].contains(store.passport.stage) { store.draft.stage = store.passport.stage }
        else if store.passport.stage != "Подготовка" { store.draft.stage = "Строительство" }
        let extra = ["Объект: \(store.projectDisplayName). Этап: \(store.passport.stage).", store.passport.area.isEmpty ? nil : "Площадь: \(store.passport.area) м².", store.passport.notes.isEmpty ? nil : "Заметка: \(store.passport.notes)"].compactMap { $0 }.joined(separator: "\n")
        store.appendToRequest(extra)
    }
}

struct ChecklistView: View {
    @EnvironmentObject private var store: AppStore
    private let groups: [(title: String, items: [(String, String)])] = [
        ("Перед стартом", [
            ("start-1", "Уточнить границы участка и разрешённое использование"),
            ("start-2", "Согласовать смету, договор и график оплаты"),
            ("start-3", "Проверить подъезд, место для материалов и техники"),
            ("start-4", "Сделать геологию или хотя бы шурф под фундамент"),
            ("start-5", "Решить вопрос временного электричества и воды")
        ]),
        ("Во время работ", [
            ("work-1", "Фиксировать скрытые работы на фото до закрытия"),
            ("work-2", "Сверять этап с проектом и сметой"),
            ("work-3", "Проверять паспорта на бетон и арматуру"),
            ("work-4", "Подписывать акты по каждому этапу"),
            ("work-5", "Вести бюджет: план, факт и остаток")
        ]),
        ("Перед приёмкой", [
            ("finish-1", "Проверить геометрию, уровни и вертикали"),
            ("finish-2", "Протестировать электрику, воду и канализацию"),
            ("finish-3", "Собрать исполнительную и гарантийную документацию")
        ])
    ]
    private var allIDs: [String] { groups.flatMap { $0.items.map(\.0) } }
    var done: Int { allIDs.filter { store.checklistDone.contains($0) }.count }
    var body: some View {
        List {
            Section { VStack(alignment: .leading, spacing: 8) { Text("\(done) из \(allIDs.count) пунктов").font(.title3.bold()); ProgressView(value: Double(done), total: Double(max(1, allIDs.count))).tint(Theme.orange) }.padding(.vertical, 4) }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.0) { item in
                        let checked = store.checklistDone.contains(item.0)
                        Button { Haptics.tap(); store.toggleChecklist(item.0) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(checked ? Theme.orange : Theme.muted)
                                Text(item.1).foregroundStyle(checked ? Theme.muted : .primary).strikethrough(checked, color: Theme.muted)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                }
            }
            Section { Text("Это личный список контроля. Он не заменяет проект, технадзор и условия договора.").font(.footnote).foregroundStyle(Theme.muted) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Чек-листы")
    }
}

struct ConstructionDiaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var entry = ""
    var body: some View {
        List {
            Section("Новая запись") {
                TextEditor(text: $entry).frame(minHeight: 100)
                Button("Сохранить запись") { store.addDiary(entry); entry = ""; Haptics.success() }.disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("История") {
                if store.diary.isEmpty { Text("Добавьте первую запись: встреча, решение или выполненный этап.").foregroundStyle(Theme.muted) }
                else { ForEach(store.diary) { item in VStack(alignment: .leading, spacing: 6) { Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.orange); Text(item.text).textSelection(.enabled) } }.onDelete { store.diary.remove(atOffsets: $0) } }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Журнал решений")
        .toolbar { if !store.diary.isEmpty { ShareLink(item: diaryText) { Image(systemName: "square.and.arrow.up") } } }
    }
    private var diaryText: String {
        (["Журнал решений · \(store.projectDisplayName)", ""] + store.diary.map { "\($0.date.formatted(date: .numeric, time: .shortened)) — \($0.text)" } + ["", Brand.shareFooter]).joined(separator: "\n")
    }
}
struct ServiceDetail: View {
    @EnvironmentObject private var store: AppStore
    let service: BuildingService
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            SectionTitle(eyebrow: "Виды работ", title: service.title)
            Text(service.detail).font(.title3).foregroundStyle(Theme.muted)
            ForEach(["Согласуем состав работ и смету до старта", "Фиксируем сроки и порядок оплаты в договоре", "Сдаём этапы по актам и фотоотчётам"], id: \.self) { Label($0, systemImage: "checkmark.circle").padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(16) }
            PrimaryButton(title: "Добавить в заявку") { store.draft.services.insert(service.title); store.showRequest = true }
        }.padding(20) }.background(Theme.background).navigationTitle("Услуга").navigationBarTitleDisplayMode(.inline)
    }
}
struct ContactView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { Text("Маркарян А.В.").font(.title2.bold()); Text("Строительно-монтажные и общестроительные работы. Сочи и Краснодарский край. С \(String(Brand.foundedYear)) года.") }
            Section("Связаться") {
                Link(destination: Brand.phoneURL) { Label(Brand.phoneDisplay, systemImage: "phone") }
                Link(destination: Brand.whatsAppURL(text: "Здравствуйте! Пишу из приложения АртСтрой.")) { Label("WhatsApp", systemImage: "message") }
                Link(destination: Brand.emailURL) { Label(Brand.email, systemImage: "envelope") }
                Link(destination: Brand.siteURL) { Label(Brand.site, systemImage: "globe") }
            }
            Section("Направления работ") {
                ForEach(store.services) { service in NavigationLink(service.title) { ServiceDetail(service: service) } }
            }
            Section("Как работаем") { ForEach(["01 · Осмотр и уточнение задачи", "02 · Смета и договор", "03 · Подготовка площадки", "04 · Работы и контроль", "05 · Приёмка и гарантия по договору"], id: \.self) { Text($0) } }
            Section("Конфиденциальность") {
                Text("Черновик заявки, избранное, расчёты, бюджет и фото-дневник сохраняются на вашем iPhone. Анонимные технические события (открытие экранов, без личных данных) отправляются на сервер АртСтроя.")
                Text("Заявка с именем и телефоном, смета, описание работ, город, ориентир бюджета и прикреплённая визуализация передаются в рабочий кабинет АртСтрой только после нажатия «Отправить». Сообщения по заявке хранятся на сервере для согласования.")
                Text("Камера используется для AR и съёмки объекта. Фото для ИИ-визуализации отправляется только после нажатия «Создать» — на сервер визуализации и поставщику модели для одного результата.")
                Text("Прогноз погоды запрашивается у Open‑Meteo по координатам Сочи — местоположение устройства не используется.")
                Text("Если в «ИИ‑движке» добавлен ключ Claude, вопросы, прикреплённые фото и план комнаты отправляются в Anthropic (api.anthropic.com) только для получения ответа. Скан комнаты и 3D‑модель хранятся на iPhone.")
                Text("Черновик можно очистить в разделе «Заявка», расчёты — в истории. Удаление приложения удаляет его локальные данные.")
            }.font(.footnote)
            Section { Text("Версия \(Brand.appVersion) · iPhone").foregroundStyle(Theme.muted) }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Контакты")
    }
}

struct ProjectHubView: View {
    @EnvironmentObject private var store: AppStore
    private var complete: Int { store.milestones.filter(\.completed).count }
    private var workOrderDraft: WorkOrderDraft {
        let details = "Проект: \(store.projectDisplayName)\nЭтап: \(store.passport.stage)\nПлановый бюджет: \(CalculationEngine.money(store.budgetPlanned))\nФактически: \(CalculationEngine.money(store.budgetActual))\n\nНужно согласовать состав работ, сроки и исполнителя. \(store.passport.notes)"
        return WorkOrderDraft(category: "Проект: \(store.projectDisplayName)", city: store.projectCity, details: details, budget: store.budgetPlanned > 0 ? CalculationEngine.money(store.budgetPlanned) : "", attachment: nil)
    }
    private var projectReport: String {
        var lines = ["ОТЧЁТ ПО ОБЪЕКТУ · \(store.projectDisplayName.uppercased())"]
        if !store.passport.address.isEmpty { lines.append("Адрес: \(store.passport.address)") }
        if !store.passport.area.isEmpty { lines.append("Площадь: \(store.passport.area) м²") }
        lines += ["Этап: \(store.passport.stage) · готовность \(Int(store.projectProgress * 100))%", "", "ДОРОЖНАЯ КАРТА"]
        lines += store.milestones.map { "\($0.completed ? "✓" : "○") \($0.title)" }
        let budget = store.budgetItems.filter { $0.included && ($0.planned > 0 || $0.actual > 0) }
        if !budget.isEmpty {
            lines += ["", "БЮДЖЕТ (план / факт)"] + budget.map { "\($0.title): \(CalculationEngine.money($0.planned)) / \(CalculationEngine.money($0.actual))" }
            lines.append("Итого: \(CalculationEngine.money(store.budgetPlanned)) / \(CalculationEngine.money(store.budgetActual))")
        }
        if let last = store.diary.first { lines += ["", "Последнее решение (\(last.date.formatted(date: .numeric, time: .omitted))): \(last.text)"] }
        lines += ["", Brand.shareFooter]
        return lines.joined(separator: "\n")
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SectionTitle(eyebrow: "Личный кабинет объекта", title: store.projectDisplayName)
            Text(store.passport.address.isEmpty ? "Добавьте район или адрес — он попадёт в вашу заявку и PDF‑сметы." : store.passport.address).font(.subheadline).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 14) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text("Готовность проекта").font(.caption).foregroundStyle(Theme.muted); Text("\(complete) из \(store.milestones.count) этапов").font(.title3.bold()) }; Spacer(); Text("\(Int(store.projectProgress * 100))%").font(.title.bold()).monospacedDigit().foregroundStyle(Theme.orange).contentTransition(.numericText()) }
                ProgressView(value: store.projectProgress).tint(Theme.orange)
                Text(store.nextMilestone.map { "Следующий шаг: \($0.title)" } ?? "Все этапы закрыты — поздравляем!").font(.caption.weight(.medium)).foregroundStyle(.white)
            }.padding(20).panelCard(22)
            if let alert = store.priceAlert { PriceAlertBanner(text: alert) { store.priceAlert = nil } }
            HStack(spacing: 12) {
                ProjectMetric(value: CalculationEngine.money(store.budgetPlanned), title: "План")
                ProjectMetric(value: CalculationEngine.money(store.budgetActual), title: "Потрачено", alert: store.budgetActual > store.budgetPlanned && store.budgetPlanned > 0)
            }
            NavigationLink { ProjectPlanView() } label: { ProjectHubRow(icon: "checklist.checked", title: "План стройки", subtitle: "Этапы, контрольные точки и готовность") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ProjectTasksView() } label: {
                ProjectHubRow(icon: "checklist", title: "Задачи команды", subtitle: store.projectTasks.isEmpty ? "Поставьте задачу и укажите ответственного" : "Открыто: \(store.projectTasks.filter { $0.status != .done }.count) · готово: \(store.projectTasks.filter { $0.status == .done }.count)")
            }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ProjectBudgetTrackerView() } label: { ProjectHubRow(icon: "chart.line.uptrend.xyaxis", title: "Бюджет объекта", subtitle: "План, факт и остаток по каждому этапу") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ProjectPhotoDiaryView() } label: { ProjectHubRow(icon: "photo.stack", title: "Фото‑дневник", subtitle: store.projectPhotos.isEmpty ? "Фиксируйте этапы и скрытые работы" : "Фото на объекте: \(store.projectPhotos.count)") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ObjectPassportView() } label: { ProjectHubRow(icon: "house.and.flag", title: "Данные объекта", subtitle: "Название, район, площадь и текущий этап") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ConstructionDiaryView() } label: { ProjectHubRow(icon: "text.book.closed", title: "Журнал решений", subtitle: store.diary.isEmpty ? "Договорённости, даты, комментарии" : "Записей: \(store.diary.count)") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { ChecklistView() } label: { ProjectHubRow(icon: "checkmark.shield", title: "Чек‑листы контроля", subtitle: "Перед стартом, во время работ и при приёмке") }.buttonStyle(PremiumCardPressStyle())
            NavigationLink { CreateWorkOrderView(prefill: workOrderDraft) } label: {
                Label("Отправить проект в АртСтрой", systemImage: "paperplane.fill").font(.headline).frame(maxWidth: .infinity).padding(16).foregroundStyle(.black).background(Theme.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(PremiumPressStyle())
            ShareLink(item: projectReport, subject: Text("Отчёт по объекту")) { SecondaryActionLabel(title: "Поделиться отчётом по объекту", icon: "square.and.arrow.up") }
            InfoNote(text: "Проект, бюджет и фото хранятся на этом iPhone. Они отправляются исполнителям только после вашего действия.")
        }.padding(20) }.background(Theme.background).navigationTitle("Мой проект").navigationBarTitleDisplayMode(.inline)
    }
}

struct ProjectMetric: View {
    let value: String
    let title: String
    var alert = false
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Theme.muted); Text(value).font(.headline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(alert ? Theme.danger : .white) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).panelCard(18) }
}
struct ProjectHubRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View { HStack(spacing: 14) { Image(systemName: icon).font(.title3).foregroundStyle(Theme.orange).frame(width: 32); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundStyle(.white); Text(subtitle).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted) }.padding(18).panelCard(18) }
}

struct ProjectPlanView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section { Text("Отмечайте закрытые этапы. Карточка «Мой проект» покажет общий прогресс и поможет не потерять следующий шаг.").font(.footnote).foregroundStyle(Theme.muted) }
            Section("Дорожная карта") { ForEach($store.milestones) { $milestone in
                Button { Haptics.tap(); withAnimation(.snappy) { milestone.completed.toggle() } } label: { HStack(spacing: 14) { Image(systemName: milestone.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(milestone.completed ? Theme.orange : Theme.muted); VStack(alignment: .leading, spacing: 4) { Text(milestone.title).foregroundStyle(.primary); Text(milestone.subtitle).font(.caption).foregroundStyle(Theme.muted) }; Spacer() } }.buttonStyle(.plain)
            } }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("План стройки")
    }
}

struct ProjectBudgetTrackerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newTitle = ""
    private var remaining: Double { store.budgetPlanned - store.budgetActual }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("План"); Spacer(); Text(CalculationEngine.money(store.budgetPlanned)).monospacedDigit() }
                    HStack { Text("Потрачено"); Spacer(); Text(CalculationEngine.money(store.budgetActual)).monospacedDigit().foregroundStyle(Theme.orange) }
                    if store.budgetPlanned > 0 { ProgressView(value: min(store.budgetActual, store.budgetPlanned), total: store.budgetPlanned).tint(remaining < 0 ? Theme.danger : Theme.orange) }
                    HStack {
                        Text(remaining < 0 ? "Перерасход" : "Остаток").fontWeight(.semibold)
                        Spacer()
                        Text(CalculationEngine.money(abs(remaining))).fontWeight(.bold).monospacedDigit().foregroundStyle(remaining < 0 ? Theme.danger : .white)
                    }
                }.font(.subheadline)
            }
            Section("Этапы") {
                ForEach(store.budgetItems.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(store.budgetItems[index].title, isOn: $store.budgetItems[index].included)
                        if store.budgetItems[index].included {
                            HStack { budgetField("План, ₽", index: index, keyPath: \.planned); budgetField("Факт, ₽", index: index, keyPath: \.actual) }
                            if store.budgetItems[index].actual > store.budgetItems[index].planned && store.budgetItems[index].planned > 0 {
                                Text("Перерасход \(CalculationEngine.money(store.budgetItems[index].actual - store.budgetItems[index].planned))").font(.caption).foregroundStyle(Theme.danger)
                            }
                        }
                    }
                }
                .onDelete { store.budgetItems.remove(atOffsets: $0) }
                HStack {
                    TextField("Новая статья, например «Забор»", text: $newTitle)
                    Button { addItem() } label: { Image(systemName: "plus.circle.fill").font(.title3) }.disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section { Text("Совет: в полной смете нажмите «В бюджет проекта» — плановые суммы заполнятся автоматически. Фактические суммы не передаются на сервер.").font(.footnote).foregroundStyle(Theme.muted) }
        }
        .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Бюджет")
        .scrollDismissesKeyboard(.interactively)
    }
    private func addItem() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.budgetItems.append(ProjectBudgetItem(id: "budget-\(UUID().uuidString)", title: title))
        newTitle = ""
        Haptics.success()
    }
    /// Whole rubles only: avoids the broken decimal-comma editing of the previous version.
    private func budgetField(_ title: String, index: Int, keyPath: WritableKeyPath<ProjectBudgetItem, Double>) -> some View {
        TextField(title, text: Binding(
            get: {
                guard store.budgetItems.indices.contains(index) else { return "" }
                let value = store.budgetItems[index][keyPath: keyPath]
                return value == 0 ? "" : CalculationEngine.format(value.rounded())
            },
            set: { text in
                guard store.budgetItems.indices.contains(index) else { return }
                store.budgetItems[index][keyPath: keyPath] = Double(text.filter(\.isNumber)) ?? 0
            }))
            .keyboardType(.numberPad)
            .padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ProjectPhotoDiaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var item: PhotosPickerItem?
    @State private var caption = ""
    @State private var error: String?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var pendingDelete: ProjectPhoto?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Объект в динамике", title: "Фото‑дневник")
                Text("Добавляйте фото выполненных этапов, скрытых работ и согласованных решений. Они останутся на вашем iPhone.").font(.subheadline).foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Подпись к фото, например: армирование плиты", text: $caption).padding(14).panelCard(14)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $item, matching: .images) { Label("Из галереи", systemImage: "photo.badge.plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(15).foregroundStyle(.black).background(Theme.orange, in: RoundedRectangle(cornerRadius: 15, style: .continuous)) }.buttonStyle(.plain)
                        Button { showCamera = true } label: { Label("Снять", systemImage: "camera.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(15).foregroundStyle(.white).panelCard(15, fill: Theme.panelRaised) }
                            .buttonStyle(.plain)
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    }
                }
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.danger) }
                if store.projectPhotos.isEmpty { ContentUnavailableView("Пока нет фото", systemImage: "photo.on.rectangle", description: Text("Сохраните первый этап, чтобы вести историю объекта.")) }
                else {
                    LazyVStack(spacing: 16) {
                        ForEach(store.projectPhotos) { photo in
                            VStack(alignment: .leading, spacing: 10) {
                                LocalThumbnail(url: store.projectPhotoURL(photo), maxPixel: 1000)
                                    .frame(height: 220).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) { Text(photo.caption.isEmpty ? "Этап строительства" : photo.caption).font(.headline); Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.muted) }
                                    Spacer()
                                    if let url = store.projectPhotoURL(photo) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.padding(.trailing, 6) }
                                    Button(role: .destructive) { pendingDelete = photo } label: { Image(systemName: "trash") }.accessibilityLabel("Удалить фото")
                                }
                            }.padding(12).panelCard(20)
                        }
                    }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("Фото‑дневник").navigationBarTitleDisplayMode(.inline)
            .onChange(of: item) { _, selected in Task { await importPhoto(selected) } }
            .sheet(isPresented: $showCamera) { CameraCaptureView(image: $cameraImage).ignoresSafeArea() }
            .onChange(of: cameraImage) { _, image in
                guard let image else { return }
                save(image); cameraImage = nil
            }
            .confirmationDialog("Удалить фото из дневника?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let photo = pendingDelete, let index = store.projectPhotos.firstIndex(where: { $0.id == photo.id }) { store.deleteProjectPhotos(at: IndexSet(integer: index)) }
                    pendingDelete = nil
                }
            }
    }
    private func save(_ image: UIImage) {
        do { try store.addProjectPhoto(image, caption: caption); caption = ""; error = nil; Haptics.success() }
        catch { self.error = error.localizedDescription }
    }
    private func importPhoto(_ selected: PhotosPickerItem?) async {
        guard let selected else { return }
        do {
            guard let data = try await selected.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw ProjectPhotoError.encoding }
            save(image); item = nil
        } catch { self.error = error.localizedDescription }
    }
}
