import Foundation

struct FieldSpec: Identifiable {
    let id: String
    let title: String
    let unit: String
    let initial: String
    var allowsZero = false
}

enum CalculationCategory: String, CaseIterable, Identifiable {
    case foundation, walls, roof, finishing, outdoor
    var id: String { rawValue }
    var title: String {
        switch self {
        case .foundation: return "Фундамент и бетон"
        case .walls: return "Стены и каркас"
        case .roof: return "Кровля и утепление"
        case .finishing: return "Отделка"
        case .outdoor: return "Участок"
        }
    }
}

enum CalculationKind: String, CaseIterable, Codable, Identifiable {
    case slab, strip, piles, concreteMix, rebar, masonry, drywall, roof, insulation, screed, plaster, paint, tiles, fence
    var id: String { rawValue }
    var category: CalculationCategory {
        switch self {
        case .slab, .strip, .piles, .concreteMix, .rebar: return .foundation
        case .masonry, .drywall: return .walls
        case .roof, .insulation: return .roof
        case .screed, .plaster, .paint, .tiles: return .finishing
        case .fence: return .outdoor
        }
    }
    var title: String {
        switch self {
        case .slab: return "Фундаментная плита"
        case .strip: return "Ленточный фундамент"
        case .piles: return "Бетонные сваи"
        case .masonry: return "Кладка блоков"
        case .screed: return "Стяжка пола"
        case .plaster: return "Штукатурка"
        case .paint: return "Покраска"
        case .tiles: return "Плитка"
        case .rebar: return "Арматура"
        case .roof: return "Двускатная кровля"
        case .concreteMix: return "Бетон своими руками"
        case .drywall: return "Гипсокартон"
        case .insulation: return "Утеплитель"
        case .fence: return "Забор из профнастила"
        }
    }
    var icon: String {
        switch self {
        case .slab, .strip: return "square.3.layers.3d"
        case .piles: return "cylinder.split.1x2"
        case .masonry: return "square.grid.3x3"
        case .screed: return "square.stack.3d.down.right"
        case .plaster: return "rectangle.fill"
        case .paint: return "paintbrush.pointed"
        case .tiles: return "square.grid.2x2"
        case .rebar: return "line.3.horizontal"
        case .roof: return "house"
        case .concreteMix: return "drop.halffull"
        case .drywall: return "rectangle.split.3x1"
        case .insulation: return "thermometer.snowflake"
        case .fence: return "rectangle.split.3x3"
        }
    }
    var summary: String {
        switch self {
        case .slab, .strip, .piles: return "Объём бетона · запас · стоимость"
        case .masonry: return "Проёмы · швы · количество блоков"
        case .screed, .plaster: return "Толщина · расход · мешки смеси"
        case .paint: return "Слои · расход · упаковки"
        case .tiles: return "Площадь · запас · упаковки"
        case .rebar: return "Длина · теоретическая масса"
        case .roof: return "Уклон · свесы · площадь покрытия"
        case .concreteMix: return "Цемент · песок · щебень · вода"
        case .drywall: return "Листы · слои · саморезы"
        case .insulation: return "Объём · толщина · упаковки"
        case .fence: return "Листы · столбы · лаги"
        }
    }
    var priceUnit: String {
        switch self {
        case .slab, .strip, .piles: return "₽/м³"
        case .masonry: return "₽/блок"
        case .screed, .plaster: return "₽/мешок"
        case .paint: return "₽/банка"
        case .tiles: return "₽/упаковка"
        case .rebar: return "₽/кг"
        case .roof: return "₽/м²"
        case .concreteMix: return "₽/мешок цемента"
        case .drywall, .fence: return "₽/лист"
        case .insulation: return "₽/упаковка"
        }
    }
    var note: String {
        switch self {
        case .slab: return "Прямоугольная плита постоянной толщины, без рёбер. Толщину и армирование задаёт проектировщик."
        case .strip: return "Суммарная длина лент измеряется по осевым линиям, пересечения не должны учитываться дважды. Сечение постоянное; без ступеней и уширений."
        case .piles: return "Цилиндрические сваи одинакового диаметра без уширений. Ростверк рассчитывается отдельно."
        case .masonry: return "Один слой прямоугольных блоков. Расчёт по лицевой площади с учётом швов; без перевязки углов, армопоясов и перемычек."
        case .screed, .plaster: return "Введите расход с упаковки вашей смеси на 1 м² при толщине 1 мм. Значение по умолчанию — пример, а не характеристика выбранного материала."
        case .paint: return "Введите расход краски на один слой с упаковки. Впитываемость основания может изменить фактический расход."
        case .tiles: return "Расчёт по площади, без раскладки. Для диагональной укладки и сложного рисунка увеличьте запас."
        case .rebar: return "Теоретическая масса круглого стержня по заданной плотности. Количество, диаметр и нахлёсты назначаются по проекту; подбор несущей арматуры не выполняется."
        case .roof: return "Симметричная двускатная крыша над прямоугольным планом. Свес вводится как горизонтальная проекция с каждой стороны. Без ендов, труб, окон и нахлёстов листов."
        case .concreteMix: return "Пропорции по умолчанию — ориентир для бетона М200 на цементе М400 (1 : 2,8 : 4,8 по массе). Для несущих конструкций используйте заводской бетон и рецептуру по проекту."
        case .drywall: return "Расчёт листов по площади обшивки с учётом слоёв. Каркас, подвесы и шпаклёвка считаются отдельно."
        case .insulation: return "Объём утеплителя по площади и толщине. Объём упаковки указан на этикетке (например, 0,288 м³ = 8 плит 1200 × 600 × 50 мм)."
        case .fence: return "Прямой забор без ворот и калиток. Длина столбов = высота забора + заглубление (обычно ещё 0,8–1,2 м)."
        }
    }
    var fields: [FieldSpec] {
        func f(_ id: String, _ title: String, _ unit: String, _ initial: String, _ zero: Bool = false) -> FieldSpec {
            FieldSpec(id: id, title: title, unit: unit, initial: initial, allowsZero: zero)
        }
        let reserve = f("reserve", "Запас материала", "%", "10", true)
        var result: [FieldSpec]
        switch self {
        case .slab: result = [f("length", "Длина", "м", "10"), f("width", "Ширина", "м", "8"), f("thickness", "Толщина", "мм", "250")]
        case .strip: result = [f("length", "Общая длина лент", "м", "40"), f("width", "Ширина ленты", "мм", "400"), f("height", "Полная высота ленты", "мм", "1200")]
        case .piles: result = [f("diameter", "Диаметр", "мм", "300"), f("height", "Длина сваи", "м", "3"), f("count", "Количество свай", "шт.", "12")]
        case .masonry: result = [f("length", "Общая длина стен", "м", "40"), f("height", "Высота стен", "м", "3"), f("openings", "Площадь проёмов", "м²", "18", true), f("blockLength", "Длина блока", "мм", "600"), f("blockHeight", "Высота блока", "мм", "200"), f("joint", "Толщина шва", "мм", "3", true)]
        case .screed: result = [f("area", "Площадь пола", "м²", "50"), f("thickness", "Толщина слоя", "мм", "50"), f("consumption", "Расход на 1 м² × 1 мм", "кг", "2"), f("package", "Масса мешка", "кг", "25")]
        case .plaster: result = [f("area", "Площадь стен", "м²", "100"), f("openings", "Площадь проёмов", "м²", "15", true), f("thickness", "Средняя толщина", "мм", "10"), f("consumption", "Расход на 1 м² × 1 мм", "кг", "0,85"), f("package", "Масса мешка", "кг", "30")]
        case .paint: result = [f("area", "Площадь поверхности", "м²", "100"), f("openings", "Площадь проёмов", "м²", "15", true), f("layers", "Количество слоёв", "шт.", "2"), f("consumption", "Расход на 1 м² на слой", "л", "0,15"), f("package", "Объём банки", "л", "10")]
        case .tiles: result = [f("area", "Площадь укладки", "м²", "25"), f("package", "Площадь в упаковке", "м²", "1,44")]
        case .rebar: result = [f("diameter", "Диаметр стержня", "мм", "12"), f("length", "Длина одного стержня", "м", "6"), f("count", "Количество стержней", "шт.", "20"), f("density", "Плотность стали", "кг/м³", "7850")]
        case .roof: result = [f("length", "Длина дома", "м", "12"), f("width", "Ширина дома", "м", "8"), f("overhang", "Свес с каждой стороны", "м", "0,5", true), f("angle", "Угол ската", "°", "30")]
        case .concreteMix: result = [f("volume", "Объём бетона", "м³", "5"), f("cement", "Цемент на 1 м³", "кг", "270"), f("sand", "Песок, частей на 1 часть цемента", "ч.", "2,8"), f("gravel", "Щебень, частей на 1 часть цемента", "ч.", "4,8"), f("water", "Водоцементное отношение", "В/Ц", "0,6"), f("package", "Масса мешка цемента", "кг", "50")]
        case .drywall: result = [f("area", "Площадь обшивки", "м²", "40"), f("openings", "Площадь проёмов", "м²", "4", true), f("layers", "Слоёв гипсокартона", "шт.", "1"), f("sheetLength", "Длина листа", "м", "2,5"), f("sheetWidth", "Ширина листа", "м", "1,2"), f("screws", "Саморезов на лист", "шт.", "30", true)]
        case .insulation: result = [f("area", "Площадь утепления", "м²", "100"), f("thickness", "Толщина слоя", "мм", "100"), f("package", "Объём упаковки", "м³", "0,288")]
        case .fence: result = [f("length", "Длина забора", "м", "30"), f("height", "Высота забора", "м", "2"), f("sheetWidth", "Полезная ширина листа", "м", "1,15"), f("postStep", "Шаг столбов", "м", "2,5"), f("rails", "Рядов лаг", "шт.", "2")]
        }
        result.append(reserve)
        result.append(f("price", "Цена материала (необязательно)", priceUnit, "", true))
        return result
    }
}

struct ResultLine: Codable, Identifiable {
    var id: String { label }
    let label: String
    let value: Double
    let unit: String
    var formatted: String { "\(CalculationEngine.format(value)) \(unit)" }
}
struct CalculationResult: Codable {
    let lines: [ResultLine]
    let formula: String
    let cost: Double?
}
struct CalculationFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum CalculationEngine {
    /// NumberFormatter is expensive to create; long estimates format hundreds of values per render.
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()
    /// Whole rubles for money values.
    static func money(_ value: Double) -> String {
        "\(formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))) ₽"
    }
    static func parse(_ text: String) -> Double? {
        let clean = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: "\u{202f}", with: "").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(clean), value.isFinite else { return nil }
        return value
    }
    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    static func calculate(_ kind: CalculationKind, values: [String: String]) throws -> CalculationResult {
        var numbers: [String: Double] = [:]
        for field in kind.fields {
            let raw = values[field.id] ?? ""
            if field.id == "price" && raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let value = parse(raw), value >= 0, (field.allowsZero || value > 0), value <= 1_000_000_000 else {
                throw CalculationFailure(message: "Проверьте поле «\(field.title)»: введите \(field.allowsZero ? "неотрицательное" : "положительное") число.")
            }
            if ["count", "layers", "rails"].contains(field.id) && value.rounded() != value {
                throw CalculationFailure(message: "«\(field.title)» должно быть целым числом.")
            }
            numbers[field.id] = value
        }
        func v(_ key: String) -> Double { numbers[key] ?? 0 }
        guard v("reserve") <= 100 else { throw CalculationFailure(message: "Запас должен быть от 0 до 100%.") }
        let factor = 1 + v("reserve") / 100
        var lines: [ResultLine] = []
        var quantity: Double = 0
        var formula = ""
        func add(_ label: String, _ value: Double, _ unit: String) { lines.append(ResultLine(label: label, value: value, unit: unit)) }
        switch kind {
        case .slab, .strip, .piles:
            let base: Double
            if kind == .slab { base = v("length") * v("width") * v("thickness") / 1000; formula = "V = длина × ширина × толщина" }
            else if kind == .strip { base = v("length") * v("width") / 1000 * v("height") / 1000; formula = "V = общая длина × ширина × высота" }
            else { base = Double.pi * pow(v("diameter") / 2000, 2) * v("height") * v("count"); formula = "V = π × (диаметр / 2)² × длина × количество" }
            quantity = base * factor
            add("Объём по геометрии", base, "м³"); add("Бетон с запасом", quantity, "м³")
        case .masonry:
            let area = v("length") * v("height") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше общей площади стен.") }
            let face = (v("blockLength") + v("joint")) * (v("blockHeight") + v("joint")) / 1_000_000
            quantity = ceil(area / face * factor)
            add("Площадь кладки", area, "м²"); add("Блоки с запасом", quantity, "шт.")
            formula = "N = площадь без проёмов / ((длина блока + шов) × (высота блока + шов)) × запас; округление вверх"
        case .screed, .plaster:
            let area = v("area") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше площади поверхности.") }
            let mass = area * v("thickness") * v("consumption") * factor
            quantity = ceil(mass / v("package"))
            add("Рабочая площадь", area, "м²"); add("Геометрический объём слоя", area * v("thickness") / 1000, "м³")
            add("Сухая смесь с запасом", mass, "кг"); add("Мешки к покупке", quantity, "шт.")
            formula = "Масса = площадь × толщина в мм × расход × запас. Мешки = масса / масса мешка, вверх"
        case .paint:
            let area = v("area") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше площади поверхности.") }
            let liters = area * v("layers") * v("consumption") * factor
            quantity = ceil(liters / v("package"))
            add("Рабочая площадь", area, "м²"); add("Краска с запасом", liters, "л"); add("Банки к покупке", quantity, "шт.")
            formula = "Литры = площадь × слои × расход × запас. Банки округляются вверх"
        case .tiles:
            let area = v("area") * factor
            quantity = ceil(area / v("package"))
            add("Площадь с запасом", area, "м²"); add("Упаковки к покупке", quantity, "шт."); add("Площадь в упаковках", quantity * v("package"), "м²")
            formula = "Упаковки = площадь × запас / площадь упаковки, вверх"
        case .rebar:
            let length = v("length") * v("count")
            let kgPerMeter = Double.pi * pow(v("diameter") / 2000, 2) * v("density")
            quantity = length * kgPerMeter * factor
            add("Общая длина без запаса", length, "м"); add("Масса одного метра", kgPerMeter, "кг/м"); add("Масса с запасом", quantity, "кг")
            formula = "Масса = π × (диаметр в метрах / 2)² × плотность × длина × количество × запас"
        case .roof:
            guard v("angle") > 0 && v("angle") < 75 else { throw CalculationFailure(message: "Для этого расчёта угол ската должен быть больше 0° и меньше 75°.") }
            let slope = (v("width") / 2 + v("overhang")) / cos(v("angle") * Double.pi / 180)
            let area = 2 * slope * (v("length") + 2 * v("overhang"))
            quantity = area * factor
            add("Длина ската со свесом", slope, "м"); add("Площадь двух скатов", area, "м²"); add("Покрытие с запасом", quantity, "м²")
            formula = "Площадь = (длина + 2 × свес) × (ширина + 2 × свес) / cos(угол)"
        case .concreteMix:
            let volume = v("volume") * factor
            let cement = volume * v("cement")
            quantity = ceil(cement / v("package"))
            add("Бетон с запасом", volume, "м³"); add("Цемент", cement, "кг"); add("Мешки цемента", quantity, "шт.")
            add("Песок", cement * v("sand"), "кг"); add("Песок, насыпной объём ≈", cement * v("sand") / 1500, "м³")
            add("Щебень", cement * v("gravel"), "кг"); add("Щебень, насыпной объём ≈", cement * v("gravel") / 1450, "м³")
            add("Вода", cement * v("water"), "л")
            formula = "Цемент = объём × расход × запас; песок и щебень = цемент × части; вода = цемент × В/Ц. Насыпная плотность: песок 1500, щебень 1450 кг/м³"
        case .drywall:
            let area = v("area") - v("openings")
            guard area > 0 else { throw CalculationFailure(message: "Проёмы должны занимать меньше площади обшивки.") }
            let sheetArea = v("sheetLength") * v("sheetWidth")
            quantity = ceil(area * v("layers") * factor / sheetArea)
            add("Площадь обшивки", area, "м²"); add("Листы с запасом", quantity, "шт."); add("Саморезы", quantity * v("screws"), "шт.")
            formula = "Листы = площадь без проёмов × слои × запас / площадь листа, вверх. Саморезы = листы × саморезы на лист"
        case .insulation:
            let volume = v("area") * v("thickness") / 1000 * factor
            quantity = ceil(volume / v("package"))
            add("Объём утеплителя с запасом", volume, "м³"); add("Упаковки к покупке", quantity, "шт.")
            formula = "Объём = площадь × толщина × запас. Упаковки = объём / объём упаковки, вверх"
        case .fence:
            quantity = ceil(v("length") / v("sheetWidth") * factor)
            let posts = ceil(v("length") / v("postStep")) + 1
            add("Площадь забора", v("length") * v("height"), "м²"); add("Листы профнастила", quantity, "шт.")
            add("Столбы", posts, "шт."); add("Лаги (профтруба)", v("length") * v("rails") * factor, "м")
            formula = "Листы = длина / полезная ширина × запас, вверх. Столбы = длина / шаг, вверх, + 1. Лаги = длина × ряды × запас"
        }
        let cost = numbers["price"].map { $0 * quantity }
        guard lines.allSatisfy({ $0.value.isFinite && $0.value < 1e15 }), cost == nil || (cost!.isFinite && cost! < 1e15) else {
            throw CalculationFailure(message: "Получились слишком большие значения. Проверьте размеры и единицы измерения.")
        }
        return CalculationResult(lines: lines, formula: formula, cost: cost)
    }
}

struct SavedCalculation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let object: String
    let kind: CalculationKind
    let values: [String: String]
    let result: CalculationResult
    var measurementNote: String? = nil
    var report: String {
        var parts = ["МАРКАРЯН А.В. · СТРОИТЕЛЬНЫЙ РАСЧЁТ", object, kind.title, date.formatted(date: .numeric, time: .shortened), "", "ИСХОДНЫЕ ДАННЫЕ"]
        parts += kind.fields.compactMap { field in
            guard let value = values[field.id], !value.isEmpty else { return nil }
            return "\(field.title): \(value) \(field.unit)"
        }
        if let measurementNote { parts += ["", measurementNote] }
        parts += ["", "РЕЗУЛЬТАТ"] + result.lines.map { "\($0.label): \($0.formatted)" }
        if let cost = result.cost { parts.append("Материалы: \(CalculationEngine.format(cost)) ₽") }
        parts += ["", "Стоимость только материалов по введённой цене, без работ и доставки.", kind.note, "Оценка количества материалов, не проектный расчёт несущих конструкций.", "", "—", "АртСтрой · ИП Маркарян А.В. · строим в Сочи с 2012 года", "+7 928 233-03-33 · WhatsApp: wa.me/79282330333 · sochi-art.com"]
        return parts.joined(separator: "\n")
    }
}
