import Foundation

/// Built‑in designer: works on the iPhone without any AI or internet.
/// Places real‑size furniture / fixtures against the walls of the scanned room by rules
/// (door swing and passages kept free, items never cross walls or each other),
/// and picks finishes, palette, materials and budget from the chosen style.
enum OfflineDesigner {
    // MARK: Templates

    private struct Template {
        let name: String
        let kind: String
        let width: Double
        let depth: Double
        /// Free space needed in front of the item.
        var clearance: Double = 0.6
        /// Prefer a room corner (shower, wardrobe…).
        var corner = false
        /// +1 far from the door, −1 near the door, 0 indifferent.
        var door: Double = 0
        /// Optional: the item is skipped if it does not fit.
        var optional = false
        /// Mounted on the wall: no floor clearance needed.
        var mounted = false
    }

    private static func templates(_ room: RoomKind, plan: FloorPlan, wishes: String, purpose: String) -> [Template] {
        let w = wishes.lowercased(), p = purpose.lowercased()
        let area = plan.area
        switch room {
        case .bathroom:
            var list: [Template] = []
            let wantsBath = w.contains("ванн") && !w.contains("без ванн")
            if wantsBath { list.append(Template(name: "Ванна акриловая 1700×750", kind: "bathtub", width: 1.7, depth: 0.75, clearance: 0.6, corner: true, door: 1)) }
            if !wantsBath { list.append(Template(name: "Душевая зона с трапом и стеклянной перегородкой", kind: "shower", width: 0.9, depth: 0.9, clearance: 0.6, corner: true, door: 1)) }
            list.append(Template(name: "Унитаз подвесной на инсталляции", kind: "toilet", width: 0.4, depth: 0.55, clearance: 0.6, door: 0.5))
            list.append(Template(name: "Тумба с раковиной 600 и зеркало", kind: "sink", width: 0.6, depth: 0.47, clearance: 0.7, door: -0.6))
            if area >= 3.8 && !w.contains("без стирал") { list.append(Template(name: "Стиральная машина", kind: "washer", width: 0.6, depth: 0.6, clearance: 0.6, optional: true)) }
            list.append(Template(name: "Полотенцесушитель водяной", kind: "towel", width: 0.5, depth: 0.1, clearance: 0, optional: true, mounted: true))
            if area >= 4.5 { list.append(Template(name: "Шкаф‑пенал", kind: "storage", width: 0.4, depth: 0.35, clearance: 0.5, optional: true)) }
            return list
        case .kitchen:
            return [
                Template(name: "Кухонный гарнитур с мойкой и варочной панелью", kind: "kitchen", width: min(3.0, max(1.8, sqrt(area) * 0.9)), depth: 0.6, clearance: 0.9, corner: true, door: 0.6),
                Template(name: "Холодильник", kind: "appliance", width: 0.6, depth: 0.65, clearance: 0.9, optional: true),
                Template(name: "Обеденный стол", kind: "table", width: area > 10 ? 1.2 : 0.9, depth: 0.8, clearance: 0.7, door: 0.3, optional: true),
                Template(name: "Растение в кашпо", kind: "plant", width: 0.4, depth: 0.4, clearance: 0.2, corner: true, optional: true)
            ]
        case .bedroom:
            return [
                Template(name: area > 11 ? "Кровать 1600×2000" : "Кровать 1400×2000", kind: "bed", width: area > 11 ? 1.6 : 1.4, depth: 2.05, clearance: 0.7, door: 0.8),
                Template(name: "Шкаф для одежды", kind: "storage", width: area > 12 ? 1.8 : 1.2, depth: 0.6, clearance: 0.8, corner: true, optional: true),
                Template(name: "Прикроватная тумба", kind: "storage", width: 0.45, depth: 0.4, clearance: 0.3, optional: true),
                Template(name: "Рабочий стол", kind: "desk", width: 1.2, depth: 0.6, clearance: 0.8, optional: true),
                Template(name: "Растение в кашпо", kind: "plant", width: 0.4, depth: 0.4, clearance: 0.2, corner: true, optional: true)
            ]
        case .kids:
            return [
                Template(name: "Кровать 900×2000", kind: "bed", width: 0.9, depth: 2.05, clearance: 0.7, corner: true, door: 0.8),
                Template(name: "Письменный стол", kind: "desk", width: 1.2, depth: 0.6, clearance: 0.8),
                Template(name: "Шкаф", kind: "storage", width: 1.2, depth: 0.6, clearance: 0.8, corner: true, optional: true),
                Template(name: "Стеллаж для игрушек", kind: "storage", width: 0.8, depth: 0.35, clearance: 0.6, optional: true),
                Template(name: "Игровой коврик", kind: "decor", width: 1.4, depth: 1.0, clearance: 0, optional: true, mounted: true)
            ]
        case .office:
            return [
                Template(name: "Рабочий стол", kind: "desk", width: 1.4, depth: 0.7, clearance: 0.9, door: 0.5),
                Template(name: "Стеллаж", kind: "storage", width: 1.2, depth: 0.4, clearance: 0.7, corner: true, optional: true),
                Template(name: "Кресло для отдыха", kind: "chair", width: 0.8, depth: 0.8, clearance: 0.5, optional: true),
                Template(name: "Растение в кашпо", kind: "plant", width: 0.4, depth: 0.4, clearance: 0.2, corner: true, optional: true)
            ]
        case .hall:
            return [
                Template(name: "Шкаф‑купе", kind: "storage", width: min(1.8, max(1.0, sqrt(area))), depth: 0.6, clearance: 0.8, corner: true),
                Template(name: "Обувница", kind: "storage", width: 0.8, depth: 0.35, clearance: 0.6, optional: true),
                Template(name: "Банкетка", kind: "chair", width: 0.8, depth: 0.4, clearance: 0.6, optional: true),
                Template(name: "Зеркало в полный рост", kind: "mirror", width: 0.6, depth: 0.03, clearance: 0, optional: true, mounted: true)
            ]
        case .living:
            var list: [Template] = []
            if p.contains("кухн") || p.contains("студи") {
                list.append(Template(name: "Кухонный гарнитур с мойкой и варочной панелью", kind: "kitchen", width: min(3.0, max(1.8, sqrt(area) * 0.6)), depth: 0.6, clearance: 0.9, corner: true, door: 0.4))
                list.append(Template(name: "Обеденный стол", kind: "table", width: 1.2, depth: 0.8, clearance: 0.7, optional: true))
            }
            list += [
                Template(name: area > 18 ? "Диван 2400" : "Диван 2000", kind: "sofa", width: area > 18 ? 2.4 : 2.0, depth: 0.95, clearance: 0.9, door: 0.6),
                Template(name: "ТВ‑зона с тумбой", kind: "tv", width: 1.6, depth: 0.45, clearance: 1.6, optional: true),
                Template(name: "Стеллаж для хранения", kind: "storage", width: 1.2, depth: 0.4, clearance: 0.7, corner: true, optional: true),
                Template(name: "Растение в кашпо", kind: "plant", width: 0.45, depth: 0.45, clearance: 0.2, corner: true, optional: true)
            ]
            if area < 9 { list.removeAll { $0.kind == "table" } }
            return list
        }
    }

    // MARK: Geometry

    private struct WallSide {
        let start: PlanPoint
        let direction: PlanPoint   // unit vector along the wall
        let normal: PlanPoint      // unit vector into the room
        let length: Double
    }

    private static func sides(_ plan: FloorPlan) -> [WallSide] {
        plan.walls.compactMap { wall in
            let dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y
            let length = hypot(dx, dy)
            guard length > 0.5 else { return nil }
            let u = PlanPoint(x: dx / length, y: dy / length)
            var n = PlanPoint(x: -u.y, y: u.x)
            let mid = PlanPoint(x: (wall.start.x + wall.end.x) / 2, y: (wall.start.y + wall.end.y) / 2)
            if !plan.contains(PlanPoint(x: mid.x + n.x * 0.3, y: mid.y + n.y * 0.3)) { n = PlanPoint(x: -n.x, y: -n.y) }
            guard plan.contains(PlanPoint(x: mid.x + n.x * 0.3, y: mid.y + n.y * 0.3)) else { return nil }
            return WallSide(start: wall.start, direction: u, normal: n, length: length)
        }
    }

    /// Points of a footprint (corners, edge middles, centre) used for overlap tests.
    private static func samples(_ item: DesignFurniture) -> [PlanPoint] {
        let c = item.corners
        var points = c + [PlanPoint(x: item.x, y: item.y)]
        for i in 0..<4 { let a = c[i], b = c[(i + 1) % 4]; points.append(PlanPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)) }
        return points
    }

    private static func overlaps(_ a: DesignFurniture, _ b: DesignFurniture, margin: Double) -> Bool {
        samples(a).contains { b.covers($0, margin: margin) } || samples(b).contains { a.covers($0, margin: margin) }
    }

    // MARK: Placement

    private static func place(_ templates: [Template], plan: FloorPlan) -> [DesignFurniture] {
        let walls = sides(plan)
        let doors = plan.doors
        let swings = doors.map { door -> (center: PlanPoint, radius: Double) in
            let mid = PlanPoint(x: (door.start.x + door.end.x) / 2, y: (door.start.y + door.end.y) / 2)
            return (mid, max(0.7, door.length) + 0.25)
        }
        let doorMid = swings.first?.center
        let b = plan.bounds
        let span = max(1, hypot(b.maxX - b.minX, b.maxY - b.minY))
        var placed: [DesignFurniture] = []
        var fronts: [DesignFurniture] = [] // clearance zones in front of placed items

        for template in templates {
            var best: (item: DesignFurniture, front: DesignFurniture?, score: Double)?
            for wall in walls where wall.length >= template.width + 0.05 {
                var t = template.width / 2 + 0.02
                while t <= wall.length - template.width / 2 - 0.02 {
                    let offset = template.depth / 2 + 0.08
                    let center = PlanPoint(x: wall.start.x + wall.direction.x * t + wall.normal.x * offset,
                                           y: wall.start.y + wall.direction.y * t + wall.normal.y * offset)
                    let rotation = atan2(-wall.normal.x, wall.normal.y) * 180 / .pi
                    let item = DesignFurniture(name: template.name, kind: template.kind, x: center.x, y: center.y, width: template.width, depth: template.depth, rotation: rotation)
                    defer { t += 0.05 }
                    // inside the room (with a small margin from the walls)
                    guard item.corners.allSatisfy({ corner in
                        plan.contains(PlanPoint(x: corner.x + (center.x - corner.x) * 0.02, y: corner.y + (center.y - corner.y) * 0.02))
                    }) else { continue }
                    // not in a door swing
                    if !template.mounted || template.kind == "towel" {
                        if samples(item).contains(where: { point in swings.contains { point.distance(to: $0.center) < $0.radius } }) { continue }
                    }
                    // no overlap with items and their passages
                    if placed.contains(where: { overlaps(item, $0, margin: 0.02) }) { continue }
                    if !template.mounted && fronts.contains(where: { overlaps(item, $0, margin: 0) }) { continue }
                    // own passage in front must be inside the room and free
                    var front: DesignFurniture?
                    if template.clearance > 0 {
                        let zone = DesignFurniture(name: "", kind: "zone", x: center.x + wall.normal.x * (template.depth / 2 + template.clearance / 2),
                                                   y: center.y + wall.normal.y * (template.depth / 2 + template.clearance / 2),
                                                   width: max(0.5, template.width * 0.8), depth: template.clearance, rotation: rotation)
                        if !plan.contains(PlanPoint(x: zone.x, y: zone.y)) { continue }
                        if placed.contains(where: { overlaps(zone, $0, margin: 0) }) { continue }
                        front = zone
                    }
                    // score: corner preference, door preference, long walls
                    var score = 0.0
                    if template.corner { score -= min(t - template.width / 2, wall.length - t - template.width / 2) * 2 }
                    if let doorMid, template.door != 0 { score += template.door * center.distance(to: doorMid) / span * 3 }
                    score += wall.length * 0.05
                    // keep the washer away from a shower / bath (electrical zone 2)
                    if template.kind == "washer", placed.contains(where: { ["shower", "bathtub"].contains($0.kind) && $0.covers(center, margin: 0.6 + template.width / 2) }) { score -= 5 }
                    if score > (best?.score ?? -.infinity) { best = (item, front, score) }
                }
            }
            if let best {
                placed.append(best.item)
                if let front = best.front { fronts.append(front) }
            }
        }
        // Bedside tables next to the bed, coffee table in front of the sofa, chairs at the table.
        return companions(placed, plan: plan)
    }

    private static func companions(_ items: [DesignFurniture], plan: FloorPlan) -> [DesignFurniture] {
        var result = items
        func free(_ item: DesignFurniture) -> Bool {
            item.corners.allSatisfy { plan.contains($0) } && !result.contains { overlaps(item, $0, margin: 0.02) }
        }
        func offset(_ base: DesignFurniture, along: Double, out: Double) -> PlanPoint {
            let a = base.rotation * .pi / 180
            return PlanPoint(x: base.x + along * cos(a) - out * sin(a), y: base.y + along * sin(a) + out * cos(a))
        }
        if let sofa = items.first(where: { $0.kind == "sofa" }) {
            let p = offset(sofa, along: 0, out: sofa.depth / 2 + 0.55)
            let table = DesignFurniture(name: "Журнальный столик", kind: "table", x: p.x, y: p.y, width: 1.0, depth: 0.55, rotation: sofa.rotation)
            if free(table) { result.append(table) }
        }
        if let bed = items.first(where: { $0.kind == "bed" }), bed.width >= 1.3, !result.contains(where: { $0.name == "Прикроватная тумба" }) {
            for side in [-1.0, 1.0] {
                let p = offset(bed, along: side * (bed.width / 2 + 0.27), out: -bed.depth / 2 + 0.22)
                let stand = DesignFurniture(name: "Прикроватная тумба", kind: "storage", x: p.x, y: p.y, width: 0.45, depth: 0.4, rotation: bed.rotation)
                if free(stand) { result.append(stand) }
            }
        }
        for table in items where table.kind == "table" {
            for side in [-1.0, 1.0] {
                let p = offset(table, along: 0, out: side * (table.depth / 2 + 0.3))
                let chair = DesignFurniture(name: "Стул", kind: "chair", x: p.x, y: p.y, width: 0.45, depth: 0.5, rotation: table.rotation + (side > 0 ? 180 : 0))
                if free(chair) { result.append(chair) }
            }
        }
        if let desk = items.first(where: { $0.kind == "desk" }) {
            let p = offset(desk, along: 0, out: desk.depth / 2 + 0.3)
            let chair = DesignFurniture(name: "Рабочее кресло", kind: "chair", x: p.x, y: p.y, width: 0.55, depth: 0.55, rotation: desk.rotation + 180)
            if free(chair) { result.append(chair) }
        }
        return result
    }

    // MARK: Style

    private struct Style {
        let palette: [String]
        let floor: (String, String, String, String)   // material, color, details, english
        let walls: (String, String, String, String)
        let ceiling: (String, String, String, String)
        let english: String
        let rate: (Double, Double)                     // ₽ per m² (finish + furniture), living rooms
    }

    private static func style(_ name: String, room: RoomKind) -> Style {
        let n = name.lowercased()
        var s: Style
        if n.contains("лофт") {
            s = Style(palette: ["#8A8A86", "#5B4636", "#2E2E2E", "#C2703D", "#E7E2DA"],
                      floor: ("Инженерная доска дуб, тёмный тон", "#5B4636", "Укладка вдоль длинной стены, чёрный теневой плинтус 60 мм", "dark oak engineered wood floor"),
                      walls: ("Декоративная штукатурка под бетон", "#8A8A86", "Акцентная стена под кирпич, чёрные металлические детали", "concrete-look decorative plaster walls with one brick accent wall"),
                      ceiling: ("Натяжной матовый потолок, тёмно‑серый", "#3A3A3A", "Чёрные трековые светильники, теневой профиль", "dark grey matte ceiling with black track lights"),
                      english: "industrial loft interior, concrete, black metal, warm wood", rate: (22_000, 45_000))
        } else if n.contains("скандин") {
            s = Style(palette: ["#F2EFEA", "#D9C7A7", "#A7B5A0", "#3F4A52", "#FFFFFF"],
                      floor: ("Ламинат 33 класса, светлый дуб", "#D9C7A7", "Укладка вдоль света из окна, белый плинтус 80 мм", "light oak laminate floor"),
                      walls: ("Моющаяся краска, тёплый белый", "#F2EFEA", "Без молдингов, акцент шалфейного цвета за мебелью", "warm white painted walls with a sage green accent"),
                      ceiling: ("Натяжной матовый белый", "#FFFFFF", "Встроенные споты и подвес над главной зоной", "white matte ceiling with recessed spots"),
                      english: "scandinavian interior, light wood, white, sage green, textiles", rate: (15_000, 32_000))
        } else if n.contains("минимал") {
            s = Style(palette: ["#F5F5F3", "#CFCAC2", "#9A958D", "#1F1F1F", "#E8E4DD"],
                      floor: ("Керамогранит 1200×600, светло‑серый", "#CFCAC2", "Раскладка от центра, скрытый плинтус", "large light grey porcelain tiles"),
                      walls: ("Краска матовая, светло‑серая", "#F5F5F3", "Скрытые двери в цвет стен, без декора", "smooth light grey matte walls"),
                      ceiling: ("Гипсокартон с теневым примыканием", "#FFFFFF", "Линейные светодиодные светильники", "white ceiling with shadow gap and linear LED lights"),
                      english: "minimalist interior, clean lines, neutral colours, hidden storage", rate: (18_000, 40_000))
        } else if n.contains("японди") {
            s = Style(palette: ["#EDE6DA", "#B89F80", "#6E5B48", "#2F2B27", "#8C8F7A"],
                      floor: ("Паркетная доска ясень, натуральный", "#B89F80", "Широкая доска, плинтус в цвет пола", "natural ash wide-plank floor"),
                      walls: ("Минеральная штукатурка, песочная", "#EDE6DA", "Деревянные рейки на акцентной стене", "sand colour mineral plaster with wooden slats"),
                      ceiling: ("Натяжной матовый, тёплый белый", "#F7F3EC", "Рассеянный свет, бумажные подвесы", "warm white ceiling with paper pendant lights"),
                      english: "japandi interior, natural wood, linen, calm earthy tones", rate: (20_000, 42_000))
        } else if n.contains("неоклас") {
            s = Style(palette: ["#EFE8DD", "#C9B79C", "#8D7B68", "#2E3A46", "#C8A96A"],
                      floor: ("Паркет ёлочкой, дуб натуральный", "#C9B79C", "Высокий плинтус 120 мм под покраску", "oak herringbone parquet floor"),
                      walls: ("Краска + молдинги", "#EFE8DD", "Классические молдинги, латунные детали", "light beige walls with classic mouldings"),
                      ceiling: ("Гипсокартон с карнизом", "#FFFFFF", "Потолочный карниз, люстра в центре", "white ceiling with cornice and chandelier"),
                      english: "neoclassical interior, mouldings, herringbone parquet, brass accents", rate: (28_000, 60_000))
        } else if n.contains("средизем") {
            s = Style(palette: ["#F4EEE4", "#D8C3A5", "#3E6E8E", "#B8653F", "#FFFFFF"],
                      floor: ("Керамогранит под терракоту", "#C98A63", "Раскладка вразбежку, плинтус керамический", "terracotta-look porcelain tiles"),
                      walls: ("Фактурная штукатурка, белая", "#F4EEE4", "Синие акценты, дерево, лён", "textured white plaster walls"),
                      ceiling: ("Натяжной матовый, белый", "#FFFFFF", "Декоративные балки, тёплый свет", "white ceiling with wooden beams"),
                      english: "mediterranean interior, white plaster, terracotta, blue accents", rate: (18_000, 38_000))
        } else if n.contains("эко") {
            s = Style(palette: ["#EFEBE3", "#A9876A", "#6B7B5C", "#3D3A35", "#D9CFC0"],
                      floor: ("Массивная доска дуб, масло", "#A9876A", "Натуральное масло, деревянный плинтус", "oiled solid oak floor"),
                      walls: ("Глиняная штукатурка", "#EFEBE3", "Фитостена или живые растения", "natural clay plaster walls with plants"),
                      ceiling: ("Натяжной матовый, тёплый белый", "#F7F3EC", "Тёплый свет 2700 K", "warm white ceiling, warm light"),
                      english: "eco interior, natural wood, clay plaster, plants, linen", rate: (20_000, 40_000))
        } else {
            s = Style(palette: ["#EEEBE6", "#BFA78A", "#6F7B85", "#2B2D30", "#D6CBBE"],
                      floor: ("Кварцвинил, дуб натуральный", "#BFA78A", "Замковое соединение, плинтус МДФ 80 мм в цвет стен", "natural oak luxury vinyl floor"),
                      walls: ("Моющаяся краска, светло‑серый тёплый", "#EEEBE6", "Акцентная стена графитового цвета", "warm light grey painted walls with a graphite accent wall"),
                      ceiling: ("Натяжной матовый белый", "#FFFFFF", "Теневой профиль, встроенные споты", "white matte ceiling with shadow gap and spots"),
                      english: "modern contemporary interior, warm neutrals, graphite accents", rate: (16_000, 35_000))
        }
        // Wet and kitchen rooms get water‑proof finishes in the same colours.
        if room == .bathroom {
            s = Style(palette: s.palette,
                      floor: ("Керамогранит 600×600, противоскользящий", s.floor.1, "Уклон 1–2 % к трапу, гидроизоляция с заведением на стены 200 мм", "anti-slip porcelain floor tiles 600x600"),
                      walls: ("Керамическая плитка / керамогранит 1200×600", s.walls.1, "Мокрая зона до потолка, остальное — влагостойкая краска; гидроизоляция в душе на 2 м", "large format porcelain wall tiles in the wet zone"),
                      ceiling: ("Натяжной влагостойкий потолок", s.ceiling.1, "Светильники IP44, вытяжной вентилятор с обратным клапаном", "moisture resistant white ceiling with IP44 spotlights"),
                      english: s.english + ", bathroom", rate: (35_000, 75_000))
        } else if room == .kitchen {
            s = Style(palette: s.palette, floor: ("Керамогранит 600×600", s.floor.1, "Под гарнитуром — тоже плитка", "porcelain floor tiles"),
                      walls: s.walls, ceiling: s.ceiling, english: s.english + ", kitchen", rate: (25_000, 55_000))
        }
        return s
    }

    // MARK: Proposal

    static func propose(plan: FloorPlan, style styleName: String, purpose: String, wishes: String) -> DesignProposal? {
        let room = RoomKind.keyword(purpose) ?? RoomKind.fromScan(plan) ?? .living
        let s = style(styleName, room: room)
        let items = place(templates(room, plan: plan, wishes: wishes, purpose: purpose), plan: plan)
        let area = plan.area
        let wallArea = plan.netWallArea
        func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        let budgetMin = (area * s.rate.0 / 10_000).rounded() * 10_000
        let budgetMax = (area * s.rate.1 / 10_000).rounded() * 10_000

        var materials: [[String: Any]] = [
            ["name": s.floor.0, "where": "Пол", "amount": "\(CalculationEngine.format(r(area * 1.08))) м² (с запасом 8 %)"],
            ["name": s.walls.0, "where": "Стены", "amount": "\(CalculationEngine.format(r(wallArea * 1.1))) м² (с запасом 10 %)"],
            ["name": s.ceiling.0, "where": "Потолок", "amount": "\(CalculationEngine.format(r(area))) м²"]
        ]
        if room == .bathroom {
            materials.append(["name": "Обмазочная гидроизоляция + лента", "where": "Пол и мокрая зона", "amount": "\(CalculationEngine.format(r(area + plan.perimeter * 0.2 + 2.5))) м²"])
            materials.append(["name": "Плиточный клей С2", "where": "Пол и стены", "amount": "≈ \(Int((area + wallArea * 0.6) * 5 / 25 + 1)) меш. по 25 кг"])
        }
        materials.append(["name": "Грунтовка глубокого проникновения", "where": "Все поверхности", "amount": "\(Int(((area * 2 + wallArea) * 0.15 / 10).rounded(.up))) канистр по 10 л"])

        let lighting: String = room == .bathroom
            ? "Встроенные споты IP44 по сетке, подсветка зеркала, выключатель снаружи у двери."
            : "Споты по сетке 1,2 м для общего света, подвесной светильник над главной зоной, тёплый свет 3000 K."
        let tips: [String] = room == .bathroom
            ? ["Проверьте расстояние до стояка: унитаз ставьте у стены со стояком.", "Розетку стиральной машины — с УЗО, не ближе 0,6 м от душа.", "Трап и уклон пола делайте до укладки плитки.", "Вентиляцию с обратным клапаном ставьте над душем или унитазом."]
            : ["Проходы оставлены не уже 0,7 м, зона открывания двери свободна.", "Розетки планируйте по расстановке мебели до чистовой отделки.", "Размеры проверьте рулеткой перед заказом мебели."]
        let names = items.map(\.name).joined(separator: ", ")
        let body: [String: Any] = [
            "title": "\(styleName): \(room.purposeTitle.lowercased())",
            "style": styleName,
            "summary": "Концепция собрана встроенным дизайнером АртСтроя по скану: \(names.isEmpty ? "расстановка без мебели" : names.lowercased()). Все предметы стоят вдоль стен, дверь открывается свободно, проходы не уже 0,6–0,9 м. Отделка — в стиле «\(styleName)».",
            "roomPurpose": purpose.isEmpty ? room.purposeTitle : purpose,
            "zones": [],
            "furniture": items.map { ["name": $0.name, "kind": $0.kind, "x": $0.x, "y": $0.y, "width": $0.width, "depth": $0.depth, "rotation": $0.rotation] as [String: Any] },
            "palette": s.palette,
            "materials": materials,
            "lighting": lighting,
            "tips": tips,
            "budgetMin": budgetMin,
            "budgetMax": max(budgetMax, budgetMin + 10_000),
            "renderPrompt": "\(styleName), \(room.russianName)",
            "renderPromptEnglish": s.english,
            "floor": ["material": s.floor.0, "color": s.floor.1, "details": s.floor.2, "english": s.floor.3],
            "walls": ["material": s.walls.0, "color": s.walls.1, "details": s.walls.2, "english": s.walls.3],
            "ceiling": ["material": s.ceiling.0, "color": s.ceiling.1, "details": s.ceiling.2, "english": s.ceiling.3]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return try? JSONDecoder().decode(DesignProposal.self, from: data)
    }

    /// English names for photo prompts when no AI translator is available.
    static func englishNames(_ items: [DesignFurniture]) -> String {
        let map: [String: String] = [
            "toilet": "wall-hung toilet", "sink": "vanity with washbasin and mirror", "shower": "walk-in shower with glass screen",
            "bathtub": "bathtub", "washer": "washing machine", "towel": "towel warmer", "mirror": "mirror", "boiler": "water heater",
            "sofa": "sofa", "bed": "bed", "table": "table", "desk": "desk", "chair": "chair", "storage": "cabinet",
            "kitchen": "kitchen units with sink and cooktop", "appliance": "fridge", "tv": "TV unit", "plant": "plant in a pot"
        ]
        return Array(Set(items.compactMap { map[$0.model] })).sorted().joined(separator: ", ")
    }
}
