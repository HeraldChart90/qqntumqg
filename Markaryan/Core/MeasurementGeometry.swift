import Foundation

enum MeasurementGeometry {
    static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
        let d = b - a
        return sqrt(Double(d.x*d.x + d.y*d.y + d.z*d.z))
    }
    static func floorArea(_ points: [SIMD3<Float>]) -> Double {
        guard points.count >= 3 else { return 0 }
        // Translate near the origin to reduce cancellation for world-space coordinates.
        let origin = points[0]
        var total: Double = 0
        for i in points.indices {
            let a = points[i] - origin, b = points[(i + 1) % points.count] - origin
            total += Double(a.x)*Double(b.z) - Double(b.x)*Double(a.z)
        }
        return abs(total)/2
    }
    static func selfIntersects(_ poly: [SIMD3<Float>]) -> Bool {
        guard poly.count >= 4 else { return false }
        func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float { (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x) }
        func onSegment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Bool {
            abs(cross(a,b,c)) < 0.00001 && c.x >= min(a.x,b.x) - 0.00001 && c.x <= max(a.x,b.x) + 0.00001 && c.z >= min(a.z,b.z) - 0.00001 && c.z <= max(a.z,b.z) + 0.00001
        }
        for i in poly.indices {
            let j = (i+1)%poly.count
            for k in (i+1)..<poly.count {
                let l = (k+1)%poly.count
                if i == k || i == l || j == k || j == l { continue }
                let a=poly[i], b=poly[j], c=poly[k], d=poly[l]
                if cross(a,b,c)*cross(a,b,d) < 0 && cross(c,d,a)*cross(c,d,b) < 0 { return true }
                if onSegment(a,b,c) || onSegment(a,b,d) || onSegment(c,d,a) || onSegment(c,d,b) { return true }
            }
        }
        return false
    }
}
