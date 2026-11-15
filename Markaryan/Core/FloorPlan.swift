import Foundation
import simd
#if canImport(RoomPlan)
import RoomPlan
#endif

// MARK: - 2D floor plan (metres, x → right, y → down, origin at the top-left of the plan)

struct PlanPoint: Codable, Hashable {
    var x: Double
    var y: Double
    static func + (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x - b.x, y: a.y - b.y) }
    func distance(to other: PlanPoint) -> Double { hypot(x - other.x, y - other.y) }
}

struct PlanSegment: Codable, Identifiable {
    enum Kind: String, Codable { case wall, door, window, opening }
    var id = UUID()
    var kind: Kind
    var start: PlanPoint
    var end: PlanPoint
    var height: Double
    var length: Double { start.distance(to: end) }
}

struct PlanObject: Codable, Identifiable {
    var id = UUID()
    var name: String
    var center: PlanPoint
    var width: Double
    var depth: Double
    /// Radians, clockwise in plan coordinates.
    var rotation: Double
}

/// Decodes an array element by element, skipping broken items (e.g. the last one of a cut-off AI answer).
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Number that may come as 1.2, "1.2" or "1,2" (AI answers are not always typed strictly).
func flexibleDouble<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return value }
    if let text = try? container.decode(String.self, forKey: key) {
        return Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: CharacterSet(charactersIn: " мm")))
    }
    return nil
}

struct DesignZone: Codable, Hashable {
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var depth: Double
}

extension DesignZone {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let x = flexibleDouble(c, .x), let y = flexibleDouble(c, .y) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "zone without position")
        }
        self.init(name: (try? c.decode(String.self, forKey: .name)) ?? "Зона", x: x, y: y,
                  width: max(0.2, flexibleDouble(c, .width) ?? 1), depth: max(0.2, flexibleDouble(c, .depth) ?? 1))
    }
}

struct DesignFurniture: Codable, Hashable {
    var name: String
    var kind: String
    var x: Double
    var y: Double
    var width: Double
    var depth: Double
    /// Degrees, clockwise.
    var rotation: Double
}

extension DesignFurniture {
    /// Lenient: a missing rotation or kind must not drop the item (an empty plan was the result before).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let x = flexibleDouble(c, .x), let y = flexibleDouble(c, .y) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: c, debugDescription: "item without position")
        }
        let name = (try? c.decode(String.self, forKey: .name)) ?? "Предмет"
        self.init(name: name, kind: (try? c.decode(String.self, forKey: .kind))?.lowercased() ?? "decor", x: x, y: y,
                  width: max(0.03, flexibleDouble(c, .width) ?? 0.6), depth: max(0.03, flexibleDouble(c, .depth) ?? 0.6),
                  rotation: flexibleDouble(c, .rotation) ?? 0)
    }

    /// Exact model to draw (toilet, sink, shower…) — the AI often gives a generic kind.
    var model: String { FixtureModel.resolve(kind: kind, name: name) }
    /// Mounted on a wall or the ceiling: does not block the floor.
    var isMounted: Bool { ["mirror", "towel", "boiler", "sconce", "pendant", "hiddenlight", "accessory"].contains(model) }
    /// Corners of the footprint in plan coordinates.
    var corners: [PlanPoint] {
        let angle = rotation * .pi / 180, c = cos(angle), s = sin(angle)
        return [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sx, sy in
            let lx = sx * width / 2, ly = sy * depth / 2
            return PlanPoint(x: x + lx * c - ly * s, y: y + lx * s + ly * c)
        }
    }
    /// Whether a point is inside the footprint enlarged by `margin`.
    func covers(_ point: PlanPoint, margin: Double) -> Bool {
        let angle = rotation * .pi / 180, c = cos(angle), s = sin(angle)
        let dx = point.x - x, dy = point.y - y
        let lx = dx * c + dy * s, ly = -dx * s + dy * c
        return abs(lx) <= width / 2 + margin && abs(ly) <= depth / 2 + margin
    }
}

/// Recognises the real object behind an AI item by its name.
enum FixtureModel {
    static func resolve(kind: String, name: String) -> String {
        let n = name.lowercased()
        let words = Set(n.split { !$0.isLetter }.map(String.init))
        func has(_ parts: String...) -> Bool { parts.contains { n.contains($0) } }
        let direct = ["toilet", "sink", "shower", "bathtub", "washer", "mirror", "towel"]
        if direct.contains(kind) { return kind }
        if kind == "kitchen" { return "kitchen" } // «Кухня с мойкой и раковиной» is still a kitchen unit
        if has("зеркал", "mirror") { return "mirror" }
        if has("полотенцесуш", "towel") { return "towel" }
        if has("бойлер", "водонагрев", "boiler") { return "boiler" }
        if has("стиральн", "сушильн", "washing", "washer") { return "washer" }
        if has("унитаз", "инсталляц", "биде", "toilet") || words.contains("wc") { return "toilet" }
        if has("раковин", "умывальн", "washbasin", "vanity") { return "sink" }
        if has("гигиенич") { return "accessory" }
        if has("душ", "shower", "трап") && !has("подушк") { return "shower" }
        if has("ванна", "bathtub") && !has("шкаф", "пенал", "полк", "тумб", "ванной") { return "bathtub" }
        if kind == "light" || has("светильн", "люстр", "торшер", "лампа", "подсветк") || words.contains("бра") {
            if has("лента", "led", "подсветк", "трек", "спот", "точечн", "встраив", "профил", "настольн") { return "hiddenlight" }
            if has("подвес", "люстр", "pendant") { return "pendant" }
            if has("торшер", "напольн") { return "floorlamp" }
            return words.contains("бра") || has("настен", "над зеркал") ? "sconce" : "pendant"
        }
        if kind == "bath" { return "bathtub" }
        return kind
    }
}

/// Type of room: decides what may stand in it, the drawing titles, the camera shots and what the image AI may show.
enum RoomKind: String, CaseIterable {
    case bathroom, kitchen, bedroom, kids, hall, office, living

    /// Room type from words: «Санузел», «Ванная», «Кухня‑гостиная», plan name…
    static func keyword(_ text: String) -> RoomKind? {
        let t = text.lowercased()
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if ["сануз", "с/у", "ванн", "туалет", "уборн", "душев", "bathroom", "toilet"].contains(where: { t.contains($0) }) { return .bathroom }
        if t.contains("детск") { return .kids }
        if t.contains("спальн") { return .bedroom }
        if t.contains("кабинет") { return .office }
        if ["прихож", "коридор", "холл", "гардероб", "тамбур"].contains(where: { t.contains($0) }) { return .hall }
        if t.contains("кухн") && !t.contains("гостин") && !t.contains("студи") { return .kitchen }
        if ["гостин", "студи", "зал", "терраса", "living"].contains(where: { t.contains($0) }) { return .living }
        return nil
    }

    /// Room type from the LiDAR scan: plan name and the objects RoomPlan found (toilet, bathtub, stove, bed…).
    static func fromScan(_ plan: FloorPlan) -> RoomKind? {
        if let named = keyword(plan.name) { return named }
        let names = plan.objects.map { $0.name.lowercased() }
        func found(_ words: String...) -> Bool { names.contains { name in words.contains { name.contains($0) } } }
        if found("унитаз", "ванна") { return .bathroom }
        if found("плита", "духовка", "холодильник", "посудомойка") { return .kitchen }
        if found("раковина") && plan.area < 7 { return .bathroom }
        if found("кровать") { return .bedroom }
        if found("диван", "телевизор", "камин") { return .living }
        return nil
    }

    /// Why the scan suggests this type (shown to the user).
    static func scanReason(_ plan: FloorPlan) -> String? {
        let found = plan.objects.map(\.name).filter { ["Унитаз", "Ванна", "Раковина", "Плита", "Духовка", "Холодильник", "Посудомойка", "Кровать", "Диван", "Телевизор"].contains($0) }
        if !found.isEmpty { return "по скану найдено: " + Array(Set(found)).sorted().joined(separator: ", ").lowercased() }
        if keyword(plan.name) != nil { return "по названию «\(plan.name)»" }
        return nil
    }

    static func detect(plan: FloorPlan?, proposal: DesignProposal?) -> RoomKind {
        // 1) what the user chose, 2) the AI title, 3) the scan, 4) the items themselves
        if let chosen = keyword(proposal?.roomPurpose ?? "") ?? keyword(proposal?.title ?? "") { return chosen }
        if let plan, let scanned = fromScan(plan) { return scanned }
        let models = (proposal?.furniture ?? []).map(\.model)
        if models.filter({ ["toilet", "sink", "shower", "bathtub"].contains($0) }).count >= 2 { return .bathroom }
        if models.contains("kitchen") && !models.contains("sofa") { return .kitchen }
        if models.contains("bed") { return .bedroom }
        return .living
    }

    /// Chip title in the design sheet.
    var purposeTitle: String {
        switch self {
        case .bathroom: return "Санузел"
        case .kitchen: return "Кухня"
        case .bedroom: return "Спальня"
        case .kids: return "Детская"
        case .hall: return "Прихожая"
        case .office: return "Кабинет"
        case .living: return "Гостиная"
        }
    }
    var russianName: String {
        switch self {
        case .bathroom: return "санузел (ванная комната)"
        case .kitchen: return "кухня"
        case .bedroom: return "спальня"
        case .kids: return "детская"
        case .hall: return "прихожая"
        case .office: return "кабинет"
        case .living: return "гостиная / жилая комната"
        }
    }

    /// Models that must never appear in this room.
    var forbiddenModels: Set<String> {
        switch self {
        case .bathroom: return ["sofa", "bed", "table", "desk", "chair", "kitchen", "tv", "appliance", "floorlamp"]
        case .kitchen: return ["toilet", "shower", "bathtub", "bed", "sink"]
        case .hall: return ["toilet", "shower", "bathtub", "bed", "kitchen", "sink"]
        case .bedroom, .kids, .office: return ["toilet", "shower", "bathtub", "sink", "kitchen", "washer", "boiler", "towel"]
        case .living: return ["toilet", "shower", "bathtub", "sink", "towel", "boiler"]
        }
    }
    func allows(_ model: String) -> Bool { !forbiddenModels.contains(model) }

    /// What the client will get in this room (shown in the design sheet).
    var allowedShort: String {
        switch self {
        case .bathroom: return "Унитаз, раковина с тумбой, душ или ванна, стиральная машина, зеркало, полотенцесушитель, шкаф, точки воды, канализации и розеток. Без кухни, дивана, кровати."
        case .kitchen: return "Гарнитур с мойкой и плитой, техника, обеденная зона, точки подключения. Без сантехники санузла и кровати."
        case .hall: return "Шкафы, обувница, банкетка, зеркало. Без сантехники и кухни."
        case .bedroom: return "Кровать, тумбы, шкаф, рабочее место. Без сантехники и кухни."
        case .kids: return "Кровать, стол, хранение, игровая зона. Без сантехники и кухни."
        case .office: return "Стол, кресло, стеллажи, хранение. Без сантехники и кухни."
        case .living: return "Мягкая мебель, ТВ‑зона, хранение (в кухне‑гостиной и студии — кухня). Без сантехники санузла."
        }
    }

    /// Rules for the design AI, in Russian.
    var rulesRussian: String {
        switch self {
        case .bathroom:
            return "Это САНУЗЕЛ. Ставь только: унитаз (kind toilet; лучше подвесной на инсталляции у стены со стояком), раковину с тумбой (sink), душевую с трапом или ванну (shower / bathtub), стиральную машину (washer — не ближе 0,6 м от душа/ванны), зеркало (mirror), полотенцесушитель (towel), шкаф или пенал (storage), бра и подсветку (light). Запрещено: кухня, плита, холодильник, диван, кровать, стол, стулья, ТВ, ковры, торшеры. Перед унитазом и раковиной свободно не менее 0,6 м, дверь открывается свободно."
        case .kitchen:
            return "Это КУХНЯ. Ставь кухонный гарнитур (kitchen) с мойкой, варочной панелью и духовкой, технику (appliance), обеденный стол и стулья. Запрещено: унитаз, душ, ванна, раковина санузла, кровать. Мойку не ставь дальше 3 м от стояка, плиту — не вплотную к окну и мойке."
        case .hall:
            return "Это ПРИХОЖАЯ. Ставь шкафы и системы хранения, обувницу, банкетку, зеркало. Запрещено: сантехника, кровать, кухня."
        case .bedroom, .kids, .office:
            return "Это \(russianName.uppercased()). Запрещено: сантехника санузла (унитаз, душ, ванна, раковина), кухня, бойлер."
        case .living:
            return "Это ЖИЛАЯ КОМНАТА. Запрещено: сантехника санузла (унитаз, душ, ванна, раковина санузла), полотенцесушитель."
        }
    }

    var furniturePlanTitle: String {
        switch self {
        case .bathroom: return "План расстановки сантехники и оборудования"
        case .kitchen: return "План расстановки кухонной мебели и техники"
        default: return "План расстановки мебели и оборудования"
        }
    }
    var specificationTitle: String {
        switch self {
        case .bathroom: return "Сантехника и оборудование"
        case .kitchen: return "Кухонная мебель и техника"
        default: return "Мебель и оборудование"
        }
    }
    var english: String {
        switch self {
        case .bathroom: return "bathroom"
        case .kitchen: return "kitchen"
        case .bedroom: return "bedroom"
        case .kids: return "children's room"
        case .hall: return "entrance hall"
        case .office: return "home office"
        case .living: return "living room"
        }
    }
    /// What the image AI must never invent in this room.
    var rulesEnglish: String {
        switch self {
        case .bathroom: return "This room is a BATHROOM, not an apartment: show only bathroom fixtures and bathroom furniture that are in the render (toilet, washbasin with vanity, mirror, shower or bathtub, towel warmer, washing machine, bathroom cabinets) and ceramic tiles. Absolutely no kitchen, no cooktop, no oven, no fridge, no sofa, no bed, no dining table, no TV, no rug."
        case .kitchen: return "This room is a KITCHEN: no bed, no sofa unless it is in the render, no bathroom fixtures."
        case .bedroom, .kids: return "This room is a \(english.uppercased()): no kitchen units, no bathroom fixtures."
        case .hall: return "This room is an ENTRANCE HALL: no kitchen, no bed, no bathroom fixtures."
        case .office, .living: return "This room is a \(english.uppercased()): no bathroom fixtures (no toilet, shower or bathtub), no bed unless it is in the render."
        }
    }
}

struct DesignMaterial: Codable, Hashable {
    var name: String
    var `where`: String
    var amount: String
}

/// Finish of one surface (floor, walls or ceiling).
struct DesignFinish: Codable, Hashable {
    var material: String = ""
    var color: String = ""
    var details: String = ""
    var english: String = ""
    var isEmpty: Bool { material.isEmpty && details.isEmpty }
    private enum CodingKeys: String, CodingKey { case material, color, details, english }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        material = (try? c.decode(String.self, forKey: .material)) ?? ""
        color = (try? c.decode(String.self, forKey: .color)) ?? ""
        details = (try? c.decode(String.self, forKey: .details)) ?? ""
        english = (try? c.decode(String.self, forKey: .english)) ?? ""
    }
}

/// AI design concept for one plan (returned by Claude as strict JSON).
struct DesignProposal: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var title: String
    var style: String
    var summary: String
    var roomPurpose: String
    var zones: [DesignZone]
    var furniture: [DesignFurniture]
    var palette: [String]
    var materials: [DesignMaterial]
    var lighting: String
    var tips: [String]
    var budgetMin: Double
    var budgetMax: Double
    var renderPrompt: String
    var renderPromptEnglish: String
    var floor: DesignFinish
    var walls: DesignFinish
    var ceiling: DesignFinish

    /// One English sentence about all surfaces — added to every image prompt so they come out precise.
    var finishesEnglish: String {
        var parts: [String] = []
        if !floor.english.isEmpty { parts.append("Floor: \(floor.english)") }
        if !walls.english.isEmpty { parts.append("Walls: \(walls.english)") }
        if !ceiling.english.isEmpty { parts.append("Ceiling: \(ceiling.english)") }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: ". ") + ". Floor, walls and ceiling finishes clearly visible and precisely executed: straight even lines, clean corners and junctions, neat skirting boards and ceiling cornices, flush built-in lighting."
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, title, style, summary, roomPurpose, zones, furniture, palette, materials, lighting, tips, budgetMin, budgetMax, renderPrompt, renderPromptEnglish, floor, walls, ceiling
    }

    init(from decoder: Decoder) throws {
        // Lenient decoding: the AI may omit optional parts; the plan still renders.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        title = (try? c.decode(String.self, forKey: .title)) ?? "Концепция"
        style = (try? c.decode(String.self, forKey: .style)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        roomPurpose = (try? c.decode(String.self, forKey: .roomPurpose)) ?? ""
        zones = (try? c.decode([Lossy<DesignZone>].self, forKey: .zones))?.compactMap(\.value) ?? []
        furniture = (try? c.decode([Lossy<DesignFurniture>].self, forKey: .furniture))?.compactMap(\.value) ?? []
        palette = (try? c.decode([String].self, forKey: .palette)) ?? []
        materials = (try? c.decode([Lossy<DesignMaterial>].self, forKey: .materials))?.compactMap(\.value) ?? []
        lighting = (try? c.decode(String.self, forKey: .lighting)) ?? ""
        tips = (try? c.decode([String].self, forKey: .tips)) ?? []
        budgetMin = (try? c.decode(Double.self, forKey: .budgetMin)) ?? 0
        budgetMax = (try? c.decode(Double.self, forKey: .budgetMax)) ?? 0
        renderPrompt = (try? c.decode(String.self, forKey: .renderPrompt)) ?? ""
        renderPromptEnglish = (try? c.decode(String.self, forKey: .renderPromptEnglish)) ?? ""
        floor = (try? c.decode(DesignFinish.self, forKey: .floor)) ?? DesignFinish()
        walls = (try? c.decode(DesignFinish.self, forKey: .walls)) ?? DesignFinish()
        ceiling = (try? c.decode(DesignFinish.self, forKey: .ceiling)) ?? DesignFinish()
    }
}

struct FloorPlan: Codable, Identifiable {
    enum Source: String, Codable { case lidar, contour }
    var id = UUID()
    var name: String
    var createdAt = Date()
    var source: Source
    var segments: [PlanSegment]
    var objects: [PlanObject]
    var floorPolygon: [PlanPoint]
    var ceilingHeight: Double
    var modelFilename: String?
    var proposals: [DesignProposal] = []

    var walls: [PlanSegment] { segments.filter { $0.kind == .wall } }
    var doors: [PlanSegment] { segments.filter { $0.kind == .door || $0.kind == .opening } }
    var windows: [PlanSegment] { segments.filter { $0.kind == .window } }

    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let points = segments.flatMap { [$0.start, $0.end] } + floorPolygon
        guard let first = points.first else { return (0, 0, 1, 1) }
        return points.reduce((first.x, first.y, first.x, first.y)) { (min($0.0, $1.x), min($0.1, $1.y), max($0.2, $1.x), max($0.3, $1.y)) }
    }
    var width: Double { bounds.maxX - bounds.minX }

    /// Floor outline (scanned polygon or the bounding rectangle).
    var outline: [PlanPoint] {
        if floorPolygon.count >= 3 { return floorPolygon }
        let b = bounds
        return [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
    }
    func contains(_ point: PlanPoint) -> Bool {
        let polygon = outline
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
    /// Door leaf opened 90° INTO the room (hinge at the start of the opening) — the same on the plan, the drawings and in 3D.
    func doorSwing(_ door: PlanSegment) -> (hinge: PlanPoint, leaf: PlanPoint) {
        let dx = door.end.x - door.start.x, dy = door.end.y - door.start.y
        let length = max(0.001, hypot(dx, dy))
        var nx = -dy / length, ny = dx / length
        let mid = PlanPoint(x: (door.start.x + door.end.x) / 2, y: (door.start.y + door.end.y) / 2)
        if !contains(PlanPoint(x: mid.x + nx * 0.3, y: mid.y + ny * 0.3)) { nx = -nx; ny = -ny }
        return (door.start, PlanPoint(x: door.start.x + nx * length, y: door.start.y + ny * length))
    }
    var depth: Double { bounds.maxY - bounds.minY }

    /// Floor area: from the floor polygon if available, otherwise the bounding rectangle.
    var area: Double {
        if floorPolygon.count >= 3 {
            var total = 0.0
            for index in floorPolygon.indices {
                let a = floorPolygon[index], b = floorPolygon[(index + 1) % floorPolygon.count]
                total += a.x * b.y - b.x * a.y
            }
            return abs(total) / 2
        }
        return width * depth
    }
    var perimeter: Double { walls.reduce(0) { $0 + $1.length } }
    var openingsArea: Double { (doors + windows).reduce(0) { $0 + $1.length * $1.height } }
    /// Net wall area for paint/plaster: perimeter × height minus doors and windows.
    var netWallArea: Double { max(0, perimeter * ceilingHeight - openingsArea) }
    var volume: Double { area * ceilingHeight }

    /// Compact description for the AI (rounded to centimetres).
    var aiDescription: String {
        func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        func seg(_ s: PlanSegment) -> [String: Any] { ["from": [r(s.start.x), r(s.start.y)], "to": [r(s.end.x), r(s.end.y)], "length": r(s.length), "height": r(s.height)] }
        let payload: [String: Any] = [
            "units": "meters; x right, y down; origin top-left",
            "size": ["width": r(width), "depth": r(depth)],
            "floorArea": r(area),
            "ceilingHeight": r(ceilingHeight),
            "floorPolygon": floorPolygon.map { [r($0.x), r($0.y)] },
            "walls": walls.map(seg),
            "doors": doors.map(seg),
            "windows": windows.map(seg),
            "existingObjects": objects.map { ["name": $0.name, "center": [r($0.center.x), r($0.center.y)], "width": r($0.width), "depth": r($0.depth)] as [String: Any] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

// MARK: - Fitting the AI layout into the scanned room

extension DesignProposal {
    /// Guarantees that every item is inside the real room: fixes centimetre/millimetre answers,
    /// limits sizes and moves items that cross a wall back inside the floor outline.
    func fitted(to plan: FloorPlan) -> DesignProposal {
        var copy = self
        let b = plan.bounds
        let roomW = max(0.5, b.maxX - b.minX), roomD = max(0.5, b.maxY - b.minY)
        let maxSide = max(roomW, roomD)
        let biggest = (furniture.flatMap { [$0.x, $0.y] } + zones.flatMap { [$0.x, $0.y] }).map(abs).max() ?? 0
        let factor: Double = biggest > maxSide * 200 ? 1000 : (biggest > maxSide * 8 ? 100 : 1)
        let center = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        // Half of the drawn wall thickness: items stand against the inner face of the wall, not inside it.
        let inset = 0.075

        /// Which axes the item still has to move along to get off the walls.
        func needs(_ item: DesignFurniture) -> (x: Bool, y: Bool) {
            var needX = false, needY = false
            for corner in item.corners {
                let inside = plan.contains(corner)
                let outX = PlanPoint(x: corner.x + (corner.x >= item.x ? inset : -inset), y: corner.y)
                let outY = PlanPoint(x: corner.x, y: corner.y + (corner.y >= item.y ? inset : -inset))
                if !inside || !plan.contains(outX) { needX = true }
                if !inside || !plan.contains(outY) { needY = true }
            }
            return (needX, needY)
        }
        func fits(_ item: DesignFurniture) -> Bool { let n = needs(item); return !n.x && !n.y }

        // What does not belong in this type of room is removed (no sofa in a bathroom, no toilet in a bedroom).
        let room = RoomKind.detect(plan: plan, proposal: self)
        copy.furniture = furniture.compactMap { (original: DesignFurniture) -> DesignFurniture? in
            var item = original
            // A «раковина» in a kitchen or a kitchen‑living room is the kitchen sink unit.
            if item.model == "sink" && (room == .kitchen || room == .living) { item.kind = "kitchen" }
            guard room.allows(item.model) else { return nil }
            if factor > 1 { item.x /= factor; item.y /= factor; item.width /= factor; item.depth /= factor }
            guard item.x.isFinite, item.y.isFinite else { return nil }
            item.width = min(max(0.03, item.width), maxSide - 0.1)
            item.depth = min(max(0.03, item.depth), maxSide - 0.1)
            if item.model == "hiddenlight" { return item }
            // Far outside: jump towards the centre first, then push off the walls centimetre by centimetre, axis by axis.
            var jumps = 0
            while !plan.contains(PlanPoint(x: item.x, y: item.y)) && jumps < 60 {
                item.x += (center.x - item.x) * 0.12
                item.y += (center.y - item.y) * 0.12
                jumps += 1
            }
            var step = 0
            while step < 300 {
                let need = needs(item)
                if !need.x && !need.y { break }
                if need.x { item.x += center.x > item.x ? 0.01 : -0.01 }
                if need.y { item.y += center.y > item.y ? 0.01 : -0.01 }
                step += 1
            }
            if !fits(item) { item.x = center.x; item.y = center.y }
            return item
        }
        copy.zones = zones.map { (original: DesignZone) -> DesignZone in
            var zone = original
            if factor > 1 { zone.x /= factor; zone.y /= factor; zone.width /= factor; zone.depth /= factor }
            zone.width = min(zone.width, roomW); zone.depth = min(zone.depth, roomD)
            zone.x = min(max(zone.x, b.minX + zone.width / 2), b.maxX - zone.width / 2)
            zone.y = min(max(zone.y, b.minY + zone.depth / 2), b.maxY - zone.depth / 2)
            return zone
        }
        return copy
    }
}

// MARK: - Building plans

enum FloorPlanBuilder {
    /// Normalises raw points: rotates so the longest wall is horizontal, then moves the plan to the origin with a small margin.
    static func normalize(_ plan: FloorPlan) -> FloorPlan {
        var plan = plan
        if let longest = plan.walls.max(by: { $0.length < $1.length }) {
            let angle = -atan2(longest.end.y - longest.start.y, longest.end.x - longest.start.x)
            let cosA = cos(angle), sinA = sin(angle)
            func rotate(_ p: PlanPoint) -> PlanPoint { PlanPoint(x: p.x * cosA - p.y * sinA, y: p.x * sinA + p.y * cosA) }
            plan.segments = plan.segments.map { var s = $0; s.start = rotate(s.start); s.end = rotate(s.end); return s }
            plan.floorPolygon = plan.floorPolygon.map(rotate)
            plan.objects = plan.objects.map { var o = $0; o.center = rotate(o.center); o.rotation += angle; return o }
        }
        let b = plan.bounds
        let shift = PlanPoint(x: -b.minX, y: -b.minY)
        plan.segments = plan.segments.map { var s = $0; s.start = s.start + shift; s.end = s.end + shift; return s }
        plan.floorPolygon = plan.floorPolygon.map { $0 + shift }
        plan.objects = plan.objects.map { var o = $0; o.center = o.center + shift; return o }
        return plan
    }

    /// Plan from an AR floor contour (works on any iPhone with ARKit).
    static func fromContour(_ points: [SIMD3<Float>], name: String, ceilingHeight: Double = 2.7) -> FloorPlan? {
        guard points.count >= 3 else { return nil }
        let polygon = points.map { PlanPoint(x: Double($0.x), y: Double($0.z)) }
        var segments: [PlanSegment] = []
        for index in polygon.indices {
            segments.append(PlanSegment(kind: .wall, start: polygon[index], end: polygon[(index + 1) % polygon.count], height: ceilingHeight))
        }
        return normalize(FloorPlan(name: name, source: .contour, segments: segments, objects: [], floorPolygon: polygon, ceilingHeight: ceilingHeight, modelFilename: nil))
    }

    #if canImport(RoomPlan)
    /// Plan from an Apple RoomPlan LiDAR scan: walls, doors, windows, openings, floor outline and furniture.
    @available(iOS 17.0, *)
    static func fromRoom(_ room: CapturedRoom, name: String, modelFilename: String?) -> FloorPlan {
        func flat(_ v: simd_float4) -> PlanPoint { PlanPoint(x: Double(v.x), y: Double(v.z)) }
        func segment(_ surface: CapturedRoom.Surface, kind: PlanSegment.Kind) -> PlanSegment {
            let center = surface.transform.columns.3
            let axis = simd_normalize(simd_float3(surface.transform.columns.0.x, 0, surface.transform.columns.0.z))
            let half = surface.dimensions.x / 2
            let start = simd_float4(center.x - axis.x * half, 0, center.z - axis.z * half, 1)
            let end = simd_float4(center.x + axis.x * half, 0, center.z + axis.z * half, 1)
            return PlanSegment(kind: kind, start: flat(start), end: flat(end), height: Double(surface.dimensions.y))
        }
        var segments: [PlanSegment] = room.walls.map { segment($0, kind: .wall) }
        segments += room.doors.map { segment($0, kind: .door) }
        segments += room.windows.map { segment($0, kind: .window) }
        segments += room.openings.map { segment($0, kind: .opening) }

        var polygon: [PlanPoint] = []
        if let floor = room.floors.first, floor.polygonCorners.count >= 3 {
            polygon = floor.polygonCorners.map { corner in flat(floor.transform * simd_float4(corner.x, corner.y, corner.z, 1)) }
        }
        let objects = room.objects.map { object -> PlanObject in
            let c = object.transform.columns.3
            let axis = object.transform.columns.0
            return PlanObject(name: objectName(object.category), center: flat(c), width: Double(object.dimensions.x), depth: Double(object.dimensions.z), rotation: atan2(Double(axis.z), Double(axis.x)))
        }
        let heights = room.walls.map { Double($0.dimensions.y) }
        let height = heights.isEmpty ? 2.7 : heights.reduce(0, +) / Double(heights.count)
        return normalize(FloorPlan(name: name, source: .lidar, segments: segments, objects: objects, floorPolygon: polygon, ceilingHeight: height, modelFilename: modelFilename))
    }

    @available(iOS 17.0, *)
    private static func objectName(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .bed: return "Кровать"
        case .sofa: return "Диван"
        case .table: return "Стол"
        case .chair: return "Стул"
        case .storage: return "Шкаф"
        case .refrigerator: return "Холодильник"
        case .stove: return "Плита"
        case .oven: return "Духовка"
        case .dishwasher: return "Посудомойка"
        case .washerDryer: return "Стиральная машина"
        case .sink: return "Раковина"
        case .bathtub: return "Ванна"
        case .toilet: return "Унитаз"
        case .fireplace: return "Камин"
        case .television: return "Телевизор"
        case .stairs: return "Лестница"
        @unknown default: return "Предмет"
        }
    }
    #endif
}
