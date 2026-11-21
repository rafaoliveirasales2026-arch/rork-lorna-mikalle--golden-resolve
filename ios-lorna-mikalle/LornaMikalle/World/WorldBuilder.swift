import CoreLocation
import RealityKit
import simd

/// A mapped place the player can discover, positioned in planar metres.
nonisolated struct PlacedPOI: Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let category: POICategory
    let position: SIMD2<Double>
}

/// Geometry for one map tile, built off the main thread.
nonisolated struct ChunkGeometry: Sendable {
    var meshes: [WorldSurface: MeshBuilder] = [:]
    /// Points along walkable streets (planar metres) used to place spirits.
    var roadSamples: [SIMD2<Double>] = []
    /// Building height per 4 m cell, used for camera collision and the occlusion marker.
    var occluders: [SIMD2<Int32>: Float] = [:]
    /// 4 m cells covered by parks and lawns (grass footsteps, nature ambience).
    var greenCells: Set<SIMD2<Int32>> = []
    var pois: [PlacedPOI] = []

    var hasContent: Bool { !meshes.isEmpty }
}

nonisolated enum WorldGrid {
    static let cellSize: Float = 4
    static func cell(_ p: SIMD2<Float>) -> SIMD2<Int32> {
        SIMD2(Int32((p.x / cellSize).rounded(.down)), Int32((p.y / cellSize).rounded(.down)))
    }
    static func cell(_ p: SIMD2<Double>) -> SIMD2<Int32> { cell(SIMD2(Float(p.x), Float(p.y))) }
}

nonisolated enum WorldBuilder {
    private static let maxTrees = 240, maxLamps = 130, maxProps = 260

    /// Converts the OSM data of one tile into merged per-surface meshes. Each feature is built only by
    /// the tile that contains its centroid (roads: each segment's midpoint), so neighbours never overlap.
    static func build(_ data: OSMData, tile: TileKey, projection: GeoProjection) -> ChunkGeometry {
        var geo = ChunkGeometry()
        var mesh: [WorldSurface: MeshBuilder] = [:]
        func with(_ s: WorldSurface, _ body: (inout MeshBuilder) -> Void) {
            var b = mesh[s] ?? MeshBuilder()
            body(&b)
            mesh[s] = b
        }

        func planar(_ c: CLLocationCoordinate2D) -> SIMD2<Float> {
            let v = projection.planar(c)
            return SIMD2(Float(v.x), Float(v.y))
        }
        func planarRing(_ coords: [CLLocationCoordinate2D]) -> [SIMD2<Float>] {
            var ring = coords.map(planar)
            if ring.count > 2, simd_distance(ring.first!, ring.last!) < 0.05 { ring.removeLast() }
            return ring
        }
        func owns(_ ring: [CLLocationCoordinate2D]) -> Bool {
            guard !ring.isEmpty else { return false }
            let lat = ring.map(\.latitude).reduce(0, +) / Double(ring.count)
            let lon = ring.map(\.longitude).reduce(0, +) / Double(ring.count)
            return tile.contains(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(tile.x &* 73_856_093 ^ tile.y &* 19_349_663)))

        // MARK: Ground layers

        for area in data.water where owns(area.ring) {
            let ring = planarRing(area.ring)
            guard ring.count >= 3 else { continue }
            with(.water) { $0.addFlatPolygon(ring, y: 0.05) }
        }

        var trees = 0, lamps = 0, props = 0
        for area in data.greens where owns(area.ring) {
            let ring = planarRing(area.ring)
            guard ring.count >= 3 else { continue }
            with(.grass) { $0.addFlatPolygon(ring, y: 0.015) }
            rasterize(ring, maxCells: 4000) { geo.greenCells.insert($0) }

            // Parks get bushes, flower beds and trees scattered inside.
            let area = abs(Triangulator.signedArea(ring))
            guard area > 80 else { continue }
            let (minP, maxP) = bounds(ring)
            let count = min(Int(area / 140), 40)
            var placed = 0, attempts = 0
            while placed < count, attempts < count * 4, props < maxProps {
                attempts += 1
                let p = SIMD2(Float.random(in: minP.x...maxP.x, using: &rng), Float.random(in: minP.y...maxP.y, using: &rng))
                guard contains(ring, p) else { continue }
                placed += 1
                props += 1
                let roll = Float.random(in: 0...1, using: &rng)
                if roll < 0.35, trees < maxTrees {
                    addTree(at: p, kind: Int.random(in: 0...2, using: &rng), seed: attempts, mesh: &mesh)
                    trees += 1
                } else if roll < 0.75 {
                    addBush(at: p, seed: attempts, mesh: &mesh)
                } else {
                    addFlowerBed(at: p, rng: &rng, mesh: &mesh)
                }
            }
        }

        for area in data.plazas where owns(area.ring) {
            let ring = planarRing(area.ring)
            guard ring.count >= 3 else { continue }
            with(.plaza) { $0.addFlatPolygon(ring, y: 0.045) }
        }

        // MARK: Buildings

        for building in data.buildings where owns(building.ring) {
            var ring = planarRing(building.ring)
            guard ring.count >= 3 else { continue }
            let area = Triangulator.signedArea(ring)
            guard abs(area) > 6, abs(area) < 60_000 else { continue }
            if area < 0 { ring.reverse() }
            let h = Float(building.height)
            let wallKind = WorldSurface.wall(colour: building.colour, id: building.id)
            let plinthHeight: Float = h >= 7 ? min(3.6, h * 0.35) : 0
            let convex = isConvex(ring)
            let tiled: Bool = {
                switch building.roofShape {
                case "gabled", "hipped", "pyramidal", "half-hipped": return convex
                case "flat": return false
                default: return convex && abs(area) < 700 && h < 26 && ring.count <= 8
                }
            }()

            var u: Float = 0
            for i in 0..<ring.count {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let d = b - a
                let len = simd_length(d)
                guard len > 0.05 else { continue }
                let n2 = SIMD2<Float>(d.y, -d.x) / len
                let normal = SIMD3<Float>(n2.x, 0, -n2.y)
                let u0 = u / 7.2, u1 = (u + len) / 7.2
                // Upper façade
                let vBottom: Float = 0, vTop = (h - plinthHeight) / 6.4
                with(wallKind) {
                    $0.addQuad(
                        SIMD3(a.x, plinthHeight, -a.y), SIMD3(b.x, plinthHeight, -b.y), SIMD3(b.x, h, -b.y), SIMD3(a.x, h, -a.y),
                        normal: normal, uv: [SIMD2(u0, vBottom), SIMD2(u1, vBottom), SIMD2(u1, vTop), SIMD2(u0, vTop)]
                    )
                }
                // Rusticated ground floor, slightly proud of the wall.
                if plinthHeight > 0 {
                    let o = n2 * 0.06
                    let pa = a + o, pb = b + o
                    let vt = plinthHeight / 3.6
                    with(.plinth) {
                        $0.addQuad(
                            SIMD3(pa.x, 0, -pa.y), SIMD3(pb.x, 0, -pb.y), SIMD3(pb.x, plinthHeight, -pb.y), SIMD3(pa.x, plinthHeight, -pa.y),
                            normal: normal, uv: [SIMD2(u0, 0), SIMD2(u1, 0), SIMD2(u1, vt), SIMD2(u0, vt)]
                        )
                    }
                }
                // Cornice: a pale overhanging band under the roofline.
                if h > 5 {
                    let o = n2 * 0.32
                    let ca = a + o, cb = b + o
                    let y0 = h - 0.5, y1 = h + 0.05
                    with(.cornice) {
                        $0.addQuad(SIMD3(ca.x, y0, -ca.y), SIMD3(cb.x, y0, -cb.y), SIMD3(cb.x, y1, -cb.y), SIMD3(ca.x, y1, -ca.y), normal: normal)
                        $0.addQuad(SIMD3(a.x, y1, -a.y), SIMD3(b.x, y1, -b.y), SIMD3(cb.x, y1, -cb.y), SIMD3(ca.x, y1, -ca.y), normal: [0, 1, 0])
                        $0.addQuad(SIMD3(a.x, y0, -a.y), SIMD3(ca.x, y0, -ca.y), SIMD3(cb.x, y0, -cb.y), SIMD3(b.x, y0, -b.y), normal: [0, -1, 0])
                        // Flat roofs get a low parapet (terrazza look) instead of a bare edge.
                        if !tiled {
                            let inner = n2 * -0.22
                            let ia = a + inner, ib = b + inner
                            let top = h + 0.75
                            $0.addQuad(SIMD3(a.x, y1, -a.y), SIMD3(b.x, y1, -b.y), SIMD3(b.x, top, -b.y), SIMD3(a.x, top, -a.y), normal: normal)
                            $0.addQuad(SIMD3(ib.x, h, -ib.y), SIMD3(ia.x, h, -ia.y), SIMD3(ia.x, top, -ia.y), SIMD3(ib.x, top, -ib.y), normal: -normal)
                            $0.addQuad(SIMD3(a.x, top, -a.y), SIMD3(b.x, top, -b.y), SIMD3(ib.x, top, -ib.y), SIMD3(ia.x, top, -ia.y), normal: [0, 1, 0])
                        }
                    }
                }
                // Contact shadow: soft darkening on the street along the wall's foot (fake AO).
                if len > 0.6 {
                    let o = n2 * 1.4
                    let y: Float = 0.118
                    with(.contactShadow) {
                        $0.addQuad(
                            SIMD3(a.x, y, -a.y), SIMD3(a.x + o.x, y, -(a.y + o.y)), SIMD3(b.x + o.x, y, -(b.y + o.y)), SIMD3(b.x, y, -b.y),
                            normal: [0, 1, 0], uv: [SIMD2(0.01, 0), SIMD2(0.99, 0), SIMD2(0.99, 1), SIMD2(0.01, 1)]
                        )
                    }
                }
                u += len
            }

            if tiled {
                // Pyramid of terracotta coppi over the eaves.
                let centroid = ring.reduce(SIMD2<Float>.zero, +) / Float(ring.count)
                let rise = min(4, max(1.6, sqrt(abs(area)) * 0.16))
                let apex = SIMD3(centroid.x, h + rise, -centroid.y)
                for i in 0..<ring.count {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    let ea = a + simd_normalize(a - centroid) * 0.45
                    let eb = b + simd_normalize(b - centroid) * 0.45
                    let pa = SIMD3(ea.x, h + 0.05, -ea.y), pb = SIMD3(eb.x, h + 0.05, -eb.y)
                    var n = simd_cross(pb - pa, apex - pa)
                    if simd_length(n) < 1e-5 { continue }
                    n = simd_normalize(n)
                    if n.y < 0 { n = -n }
                    with(.roofTiles) { $0.addTriangle(pa, pb, apex, normal: n) }
                }
            } else {
                with(.roofFlat) { $0.addFlatPolygon(ring, y: h + 0.06) }
            }

            rasterize(ring, maxCells: 3000) { cell in
                geo.occluders[cell] = max(geo.occluders[cell] ?? 0, h)
            }
        }

        func blocked(_ p: SIMD2<Float>) -> Bool { geo.occluders[WorldGrid.cell(p)] != nil }

        // MARK: Roads

        for way in data.roads {
            let all = way.points
            guard all.count >= 2 else { continue }
            // Split into runs of consecutive segments whose midpoint lies in this tile.
            var runs: [[SIMD2<Float>]] = []
            var current: [SIMD2<Float>] = []
            for i in 0..<(all.count - 1) {
                let a = all[i], b = all[i + 1]
                let mid = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
                if tile.contains(mid) {
                    if current.isEmpty { current.append(planar(a)) }
                    current.append(planar(b))
                } else if !current.isEmpty {
                    runs.append(current)
                    current = []
                }
            }
            if !current.isEmpty { runs.append(current) }

            for pts in runs where pts.count >= 2 {
                let w = way.kind.width
                switch way.kind {
                case .path:
                    with(.path) { $0.addRibbon(pts, width: w, y: 0.03) }
                case .service:
                    with(.road) { $0.addRibbon(pts, width: w, y: 0.04) }
                case .major, .street:
                    with(.road) { $0.addRibbon(pts, width: w, y: 0.04) }
                    with(.sidewalk) { $0.addRibbon(pts, width: w + 3.8, y: 0.025) }
                    for side: Float in [-1, 1] {
                        let edge = offset(pts, by: side * (w / 2 + 0.12))
                        with(.curb) { $0.addRibbon(edge, width: 0.24, y: 0.11, roundJoins: false) }
                    }
                }

                // Walk the polyline at fixed spacing for dashes, samples, trees and lamps.
                var carry: Float = 0
                var step = 0
                for i in 0..<(pts.count - 1) {
                    let a = pts[i], b = pts[i + 1]
                    let len = simd_distance(a, b)
                    guard len > 0.1 else { continue }
                    let dir = (b - a) / len
                    let side = SIMD2<Float>(-dir.y, dir.x)
                    var t = carry
                    while t < len {
                        let p = a + dir * t
                        step += 1
                        if way.kind != .path, step % 2 == 0 {
                            geo.roadSamples.append(SIMD2(Double(p.x), Double(p.y)))
                        }
                        if way.kind == .major || way.kind == .street {
                            if t + 3 < len {
                                with(.laneMark) { $0.addRibbon([p, p + dir * 3], width: 0.16, y: 0.06, roundJoins: false) }
                            }
                            let treeOffset = w / 2 + 2.4
                            if step % 2 == 0, trees < maxTrees {
                                let tp = p + side * (step % 4 == 0 ? treeOffset : -treeOffset)
                                if !blocked(tp) {
                                    let kind = way.kind == .major ? 1 : (abs(way.id) % 5 == 0 ? 2 : 0)
                                    addTree(at: tp, kind: kind, seed: way.id &+ step, mesh: &mesh)
                                    trees += 1
                                }
                            }
                            if step % 4 == 1, lamps < maxLamps {
                                let lp = p + side * (step % 8 == 1 ? 1 : -1) * (w / 2 + 0.7)
                                if !blocked(lp) { addLamp(at: lp, mesh: &mesh); lamps += 1 }
                            }
                        } else if way.kind == .path, step % 3 == 0, lamps < maxLamps {
                            let lp = p + side * (w / 2 + 0.5)
                            if !blocked(lp) { addLamp(at: lp, mesh: &mesh); lamps += 1 }
                        }
                        t += 7
                    }
                    carry = t - len
                }
            }
        }

        // MARK: Mapped points

        for tree in data.trees where tile.contains(tree.coordinate) && trees < maxTrees + 140 {
            let p = planar(tree.coordinate)
            addTree(at: p, kind: abs(tree.id) % 6 == 0 ? 2 : (abs(tree.id) % 4 == 0 ? 1 : 0), seed: tree.id, mesh: &mesh)
            trees += 1
        }
        for lamp in data.lamps where tile.contains(lamp.coordinate) && lamps < maxLamps + 80 {
            addLamp(at: planar(lamp.coordinate), mesh: &mesh)
            lamps += 1
        }
        for bench in data.benches.prefix(80) where tile.contains(bench.coordinate) {
            let p = planar(bench.coordinate)
            let yaw = Float(abs(bench.id) % 360) * .pi / 180
            let base = SIMD3(p.x, 0, -p.y)
            with(.bench) {
                $0.addBox(center: base, size: [1.6, 0.45, 0.5], yaw: yaw)
                let back = base + simd_quatf(angle: yaw, axis: [0, 1, 0]).act([0, 0.45, -0.22])
                $0.addBox(center: back, size: [1.6, 0.42, 0.08], yaw: yaw)
            }
        }
        for fountain in data.fountains.prefix(20) where tile.contains(fountain.coordinate) {
            addFountain(at: planar(fountain.coordinate), mesh: &mesh)
        }
        for poi in data.pois where tile.contains(poi.coordinate) {
            let p = projection.planar(poi.coordinate)
            if !geo.pois.contains(where: { $0.name == poi.name && simd_distance($0.position, p) < 60 }) {
                geo.pois.append(PlacedPOI(id: poi.id, name: poi.name, category: poi.category, position: p))
            }
        }

        geo.meshes = mesh
        return geo
    }

    // MARK: - Props

    /// kind 0: round plane tree, 1: Mediterranean stone pine, 2: cypress.
    private static func addTree(at p: SIMD2<Float>, kind: Int, seed: Int, mesh: inout [WorldSurface: MeshBuilder]) {
        let s: Float = 0.85 + Float(abs(seed) % 5) * 0.08
        let base = SIMD3<Float>(p.x, 0, -p.y)
        var bark = mesh[.bark] ?? MeshBuilder()
        switch kind {
        case 1:
            bark.addPrism(base: base, radius: 0.2 * s, height: 5.6 * s, sides: 6, topRadius: 0.12 * s)
            var crown = mesh[.pineCrown] ?? MeshBuilder()
            crown.addSphere(center: base + SIMD3(0, 6.2 * s, 0), radius: SIMD3(3.0, 1.0, 3.0) * s, rings: 5, segments: 10)
            crown.addSphere(center: base + SIMD3(0.9 * s, 6.7 * s, 0.4 * s), radius: SIMD3(1.8, 0.7, 1.8) * s, rings: 4, segments: 8)
            mesh[.pineCrown] = crown
        case 2:
            bark.addPrism(base: base, radius: 0.12 * s, height: 0.8 * s, sides: 5)
            var crown = mesh[.foliageDark] ?? MeshBuilder()
            crown.addSphere(center: base + SIMD3(0, 3.2 * s, 0), radius: SIMD3(0.8, 2.8, 0.8) * s, rings: 6, segments: 8)
            crown.addCone(base: base + SIMD3(0, 5.2 * s, 0), radius: 0.5 * s, height: 1.6 * s, sides: 8)
            mesh[.foliageDark] = crown
        default:
            bark.addPrism(base: base, radius: 0.16 * s, height: 2.4 * s, sides: 6, topRadius: 0.1 * s)
            var crown = mesh[.foliage] ?? MeshBuilder()
            crown.addSphere(center: base + SIMD3(0, 3.1 * s, 0), radius: SIMD3(1.5, 1.3, 1.5) * s, rings: 5, segments: 8)
            crown.addSphere(center: base + SIMD3(0.5 * s, 3.8 * s, 0.3 * s), radius: SIMD3(1.0, 0.9, 1.0) * s, rings: 4, segments: 7)
            mesh[.foliage] = crown
        }
        mesh[.bark] = bark
    }

    private static func addBush(at p: SIMD2<Float>, seed: Int, mesh: inout [WorldSurface: MeshBuilder]) {
        let s: Float = 0.7 + Float(abs(seed) % 4) * 0.15
        var bush = mesh[.bush] ?? MeshBuilder()
        bush.addSphere(center: SIMD3(p.x, 0.45 * s, -p.y), radius: SIMD3(0.9, 0.6, 0.8) * s, rings: 4, segments: 7)
        mesh[.bush] = bush
    }

    private static func addFlowerBed(at p: SIMD2<Float>, rng: inout SeededRNG, mesh: inout [WorldSurface: MeshBuilder]) {
        var bush = mesh[.bush] ?? MeshBuilder()
        var flowers = mesh[.flowers] ?? MeshBuilder()
        bush.addSphere(center: SIMD3(p.x, 0.15, -p.y), radius: SIMD3(1.2, 0.25, 1.2), rings: 3, segments: 8)
        for _ in 0..<7 {
            let o = SIMD2(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng))
            flowers.addSphere(center: SIMD3(p.x + o.x, 0.36, -(p.y + o.y)), radius: SIMD3(repeating: 0.13), rings: 3, segments: 5)
        }
        mesh[.bush] = bush
        mesh[.flowers] = flowers
    }

    private static func addLamp(at p: SIMD2<Float>, mesh: inout [WorldSurface: MeshBuilder]) {
        let base = SIMD3<Float>(p.x, 0, -p.y)
        var pole = mesh[.lampPole] ?? MeshBuilder()
        var head = mesh[.lampHead] ?? MeshBuilder()
        pole.addPrism(base: base, radius: 0.09, height: 0.5, sides: 6, topRadius: 0.06)
        pole.addPrism(base: base + SIMD3(0, 0.5, 0), radius: 0.06, height: 3.1, sides: 6, topRadius: 0.045)
        pole.addPrism(base: base + SIMD3(0, 3.6, 0), radius: 0.16, height: 0.08, sides: 6, topRadius: 0.2)
        head.addSphere(center: base + SIMD3(0, 3.95, 0), radius: SIMD3(0.2, 0.28, 0.2), rings: 5, segments: 8)
        pole.addCone(base: base + SIMD3(0, 4.2, 0), radius: 0.26, height: 0.22, sides: 6)
        mesh[.lampPole] = pole
        mesh[.lampHead] = head
    }

    private static func addFountain(at p: SIMD2<Float>, mesh: inout [WorldSurface: MeshBuilder]) {
        let base = SIMD3<Float>(p.x, 0, -p.y)
        var stone = mesh[.fountainStone] ?? MeshBuilder()
        var water = mesh[.fountainWater] ?? MeshBuilder()
        stone.addPrism(base: base, radius: 2.4, height: 0.6, sides: 12)
        stone.addPrism(base: base + SIMD3(0, 0.6, 0), radius: 2.5, height: 0.1, sides: 12)
        water.addDisc(center: p, radius: 2.3, y: 0.52, segments: 16)
        stone.addPrism(base: base, radius: 0.35, height: 1.5, sides: 8, topRadius: 0.25)
        stone.addPrism(base: base + SIMD3(0, 1.5, 0), radius: 0.9, height: 0.25, sides: 10, topRadius: 1.0)
        water.addDisc(center: p, radius: 0.85, y: 1.72, segments: 10)
        water.addSphere(center: base + SIMD3(0, 2.0, 0), radius: SIMD3(0.18, 0.4, 0.18), rings: 4, segments: 6)
        mesh[.fountainStone] = stone
        mesh[.fountainWater] = water
    }

    // MARK: - Geometry helpers

    private static func bounds(_ ring: [SIMD2<Float>]) -> (SIMD2<Float>, SIMD2<Float>) {
        let minP = ring.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
        let maxP = ring.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        return (minP, maxP)
    }

    static func contains(_ ring: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func isConvex(_ ring: [SIMD2<Float>]) -> Bool {
        guard ring.count >= 3 else { return false }
        for i in 0..<ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count], c = ring[(i + 2) % ring.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross < -0.05 { return false }
        }
        return true
    }

    /// Visits every 4 m grid cell whose centre lies inside the ring.
    private static func rasterize(_ ring: [SIMD2<Float>], maxCells: Int, _ visit: (SIMD2<Int32>) -> Void) {
        let (minP, maxP) = bounds(ring)
        let c0 = WorldGrid.cell(minP), c1 = WorldGrid.cell(maxP)
        guard c0.x <= c1.x, c0.y <= c1.y, Int(c1.x - c0.x + 1) * Int(c1.y - c0.y + 1) <= maxCells else { return }
        let size = WorldGrid.cellSize
        for x in c0.x...c1.x {
            for y in c0.y...c1.y {
                let center = SIMD2(Float(x) * size + size / 2, Float(y) * size + size / 2)
                if contains(ring, center) { visit(SIMD2(x, y)) }
            }
        }
    }

    /// Parallel polyline at a signed distance (left of travel is positive).
    private static func offset(_ pts: [SIMD2<Float>], by d: Float) -> [SIMD2<Float>] {
        guard pts.count >= 2 else { return pts }
        var out: [SIMD2<Float>] = []
        for i in 0..<pts.count {
            let prev = i > 0 ? simd_normalize(pts[i] - pts[i - 1]) : nil
            let next = i < pts.count - 1 ? simd_normalize(pts[i + 1] - pts[i]) : nil
            let dir = simd_normalize((prev ?? next!) + (next ?? prev!) + SIMD2(1e-6, 0))
            var n = SIMD2(-dir.y, dir.x)
            if let prev {
                let edgeN = SIMD2(-prev.y, prev.x)
                let cosA = max(simd_dot(n, edgeN), 0.5)
                n /= cosA
            }
            out.append(pts[i] + n * d)
        }
        return out.filter { $0.x.isFinite && $0.y.isFinite }
    }
}

/// Small deterministic generator so a tile always grows the same park.
nonisolated struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// A built tile in the scene. Meshes are created one surface per frame to avoid hitches.
final class WorldChunk {
    let tile: TileKey
    let entity = Entity()
    let geometry: ChunkGeometry
    private var surfaces: [(ModelEntity, WorldSurface)] = []
    private(set) var appliedPreset: LightingPreset
    private(set) var appliedWet: Bool

    private init(tile: TileKey, geometry: ChunkGeometry, preset: LightingPreset, wet: Bool) {
        self.tile = tile
        self.geometry = geometry
        self.appliedPreset = preset
        self.appliedWet = wet
        entity.name = "tile-\(tile)"
    }

    static func make(tile: TileKey, geometry: ChunkGeometry, preset: LightingPreset, wet: Bool) async -> WorldChunk {
        let chunk = WorldChunk(tile: tile, geometry: geometry, preset: preset, wet: wet)
        // Ground layers first so streets appear before buildings.
        let order = WorldSurface.allCases
        for surface in order {
            guard let builder = geometry.meshes[surface], !builder.isEmpty,
                  let mesh = builder.makeMesh(name: surface.rawValue) else { continue }
            let model = ModelEntity(mesh: mesh, materials: [WorldMaterials.shared.material(surface, preset: chunk.appliedPreset, wet: chunk.appliedWet)])
            model.name = surface.rawValue
            if !surface.castsShadow {
                model.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
            chunk.entity.addChild(model)
            chunk.surfaces.append((model, surface))
            await Task.yield()
        }
        return chunk
    }

    func apply(_ preset: LightingPreset, wet: Bool) {
        guard preset != appliedPreset || wet != appliedWet else { return }
        appliedPreset = preset
        appliedWet = wet
        for (model, surface) in surfaces {
            model.model?.materials = [WorldMaterials.shared.material(surface, preset: preset, wet: wet)]
        }
    }
}
