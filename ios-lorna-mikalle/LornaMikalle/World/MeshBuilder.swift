import RealityKit
import simd

/// Accumulates triangles so whole categories (all roads, all walls…) become one draw call.
nonisolated struct MeshBuilder: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                              normal: SIMD3<Float>, uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)? = nil) {
        let base = UInt32(positions.count)
        positions += [a, b, c]
        normals += [normal, normal, normal]
        if let uv { uvs += [uv.0, uv.1, uv.2] } else {
            uvs += [SIMD2(a.x, a.z) / 6, SIMD2(b.x, b.z) / 6, SIMD2(c.x, c.z) / 6]
        }
        indices += [base, base + 1, base + 2]
    }

    /// Quad a-b-c-d (in order around the perimeter).
    mutating func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                          normal: SIMD3<Float>, uv: [SIMD2<Float>]? = nil) {
        let base = UInt32(positions.count)
        positions += [a, b, c, d]
        normals += [normal, normal, normal, normal]
        if let uv { uvs += uv } else {
            uvs += [a, b, c, d].map { SIMD2($0.x, $0.z) / 6 }
        }
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// Flat horizontal polygon (planar east/north ring) at height y.
    mutating func addFlatPolygon(_ ring: [SIMD2<Float>], y: Float) {
        let tris = Triangulator.triangulate(ring)
        let up = SIMD3<Float>(0, 1, 0)
        for t in tris {
            addTriangle(world(ring[t.0], y), world(ring[t.1], y), world(ring[t.2], y), normal: up)
        }
    }

    /// A ribbon along a planar polyline (roads, sidewalks, paths).
    mutating func addRibbon(_ points: [SIMD2<Float>], width: Float, y: Float, roundJoins: Bool = true) {
        guard points.count >= 2 else { return }
        let half = width / 2
        let up = SIMD3<Float>(0, 1, 0)
        for i in 0..<(points.count - 1) {
            let p0 = points[i], p1 = points[i + 1]
            let d = p1 - p0
            let len = simd_length(d)
            guard len > 0.01 else { continue }
            let dir = d / len
            let n = SIMD2<Float>(-dir.y, dir.x) * half
            addQuad(world(p0 - n, y), world(p1 - n, y), world(p1 + n, y), world(p0 + n, y), normal: up)
        }
        if roundJoins {
            for p in points.dropFirst().dropLast() { addDisc(center: p, radius: half, y: y, segments: 8) }
            addDisc(center: points[0], radius: half, y: y, segments: 8)
            addDisc(center: points[points.count - 1], radius: half, y: y, segments: 8)
        }
    }

    mutating func addDisc(center: SIMD2<Float>, radius: Float, y: Float, segments: Int) {
        let up = SIMD3<Float>(0, 1, 0)
        let c = world(center, y)
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p0 = center + SIMD2(cos(a0), sin(a0)) * radius
            let p1 = center + SIMD2(cos(a1), sin(a1)) * radius
            addTriangle(c, world(p0, y), world(p1, y), normal: up)
        }
    }

    /// Vertical prism (tree trunks, lamp poles).
    mutating func addPrism(base: SIMD3<Float>, radius: Float, height: Float, sides: Int, topRadius: Float? = nil) {
        let top = topRadius ?? radius
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi
            let a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let mid = (a0 + a1) / 2
            let n = SIMD3<Float>(cos(mid), 0, sin(mid))
            let b0 = base + SIMD3(cos(a0) * radius, 0, sin(a0) * radius)
            let b1 = base + SIMD3(cos(a1) * radius, 0, sin(a1) * radius)
            let t0 = base + SIMD3(cos(a0) * top, height, sin(a0) * top)
            let t1 = base + SIMD3(cos(a1) * top, height, sin(a1) * top)
            addQuad(b0, b1, t1, t0, normal: n)
        }
    }

    /// Smooth-shaded UV sphere (tree crowns, lamp globes).
    mutating func addSphere(center: SIMD3<Float>, radius: SIMD3<Float>, rings: Int = 7, segments: Int = 10) {
        let base = UInt32(positions.count)
        for r in 0...rings {
            let v = Float(r) / Float(rings)
            let phi = v * .pi
            for s in 0...segments {
                let u = Float(s) / Float(segments)
                let theta = u * 2 * .pi
                let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                positions.append(center + n * radius)
                normals.append(simd_normalize(n / radius))
                // RealityKit custom-mesh UVs start bottom-left: v = 1 is the top of the image.
                uvs.append(SIMD2(u, 1 - v))
            }
        }
        let stride = UInt32(segments + 1)
        for r in 0..<UInt32(rings) {
            for s in 0..<UInt32(segments) {
                let a = base + r * stride + s
                let b = a + stride
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
    }

    /// Axis-aligned box rotated by `yaw` around its base centre (benches, kiosks, props).
    mutating func addBox(center base: SIMD3<Float>, size: SIMD3<Float>, yaw: Float = 0) {
        let h = size / 2
        let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { base + rot.act(SIMD3(x * h.x, y * size.y, z * h.z)) }
        func n(_ v: SIMD3<Float>) -> SIMD3<Float> { rot.act(v) }
        addQuad(p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1), normal: [0, 1, 0])
        addQuad(p(-1, 0, 1), p(1, 0, 1), p(1, 1, 1), p(-1, 1, 1), normal: n([0, 0, 1]))
        addQuad(p(1, 0, -1), p(-1, 0, -1), p(-1, 1, -1), p(1, 1, -1), normal: n([0, 0, -1]))
        addQuad(p(1, 0, 1), p(1, 0, -1), p(1, 1, -1), p(1, 1, 1), normal: n([1, 0, 0]))
        addQuad(p(-1, 0, -1), p(-1, 0, 1), p(-1, 1, 1), p(-1, 1, -1), normal: n([-1, 0, 0]))
    }

    /// Cone (cypress crowns, crystal tips).
    mutating func addCone(base: SIMD3<Float>, radius: Float, height: Float, sides: Int) {
        let apex = base + SIMD3(0, height, 0)
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi
            let a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let b0 = base + SIMD3(cos(a0) * radius, 0, sin(a0) * radius)
            let b1 = base + SIMD3(cos(a1) * radius, 0, sin(a1) * radius)
            let mid = (a0 + a1) / 2
            let slope = radius / height
            let normal = simd_normalize(SIMD3(cos(mid), slope, sin(mid)))
            addTriangle(b0, apex, b1, normal: normal)
        }
    }

    @MainActor
    func makeMesh(name: String) -> MeshResource? {
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    @inline(__always)
    func world(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3(p.x, y, -p.y) }
}

/// Ear-clipping triangulation for simple polygons (building footprints, parks).
nonisolated enum Triangulator {
    static func signedArea(_ ring: [SIMD2<Float>]) -> Float {
        var area: Float = 0
        for i in 0..<ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }

    static func triangulate(_ ring: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        let n = ring.count
        guard n >= 3 else { return [] }
        var idx = Array(0..<n)
        if signedArea(ring) < 0 { idx.reverse() }
        var result: [(Int, Int, Int)] = []
        if n > 160 {
            for i in 1..<(n - 1) { result.append((idx[0], idx[i], idx[i + 1])) }
            return result
        }
        var guardCount = 0
        while idx.count > 3 && guardCount < n * n {
            guardCount += 1
            var clipped = false
            for i in 0..<idx.count {
                let i0 = idx[(i + idx.count - 1) % idx.count], i1 = idx[i], i2 = idx[(i + 1) % idx.count]
                let a = ring[i0], b = ring[i1], c = ring[i2]
                let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                if cross <= 1e-6 { continue }
                var containsPoint = false
                for j in idx where j != i0 && j != i1 && j != i2 {
                    if pointInTriangle(ring[j], a, b, c) { containsPoint = true; break }
                }
                if containsPoint { continue }
                result.append((i0, i1, i2))
                idx.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break }
        }
        if idx.count == 3 { result.append((idx[0], idx[1], idx[2])) }
        return result
    }

    private static func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        func sign(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>) -> Float {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }
}
