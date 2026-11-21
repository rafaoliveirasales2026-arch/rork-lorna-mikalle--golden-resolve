import Metal
import RealityKit
import UIKit

/// Every surface category the world is built from. One merged mesh per category per tile.
nonisolated enum WorldSurface: String, CaseIterable, Sendable {
    case ground, grass, water, plaza, sidewalk, curb, path, road, laneMark
    case wallTerracotta, wallOchre, wallCream, wallRose, wallSienna
    /// Second façade style (tall French windows, iron balconies, wooden shutters) per colour.
    case wallTerracottaB, wallOchreB, wallCreamB, wallRoseB, wallSiennaB
    case plinth, cornice, roofFlat, roofTiles, contactShadow
    case bark, foliage, foliageDark, pineCrown, bush, flowers
    case lampPole, lampHead, bench, fountainStone, fountainWater, poiCrystal

    static let walls: [WorldSurface] = [.wallTerracotta, .wallOchre, .wallCream, .wallRose, .wallSienna,
                                        .wallTerracottaB, .wallOchreB, .wallCreamB, .wallRoseB, .wallSiennaB]

    var isBalconyStyle: Bool {
        switch self {
        case .wallTerracottaB, .wallOchreB, .wallCreamB, .wallRoseB, .wallSiennaB: true
        default: false
        }
    }

    /// The balcony variant of a classic wall colour.
    var balconyVariant: WorldSurface {
        switch self {
        case .wallTerracotta: .wallTerracottaB
        case .wallOchre: .wallOchreB
        case .wallCream: .wallCreamB
        case .wallRose: .wallRoseB
        case .wallSienna: .wallSiennaB
        default: self
        }
    }

    var baseColor: UInt32 {
        switch self {
        case .ground: 0xA49A80
        case .grass: 0x7FB052
        case .water: 0x3F8FB8
        case .plaza: 0xC8B79E
        case .sidewalk: 0xD4B596
        case .curb: 0xE4DCCB
        case .path: 0xC9A77E
        case .road: 0x4E4650
        case .laneMark: 0xF4EEDF
        case .wallTerracotta, .wallTerracottaB: 0xD9875C
        case .wallOchre, .wallOchreB: 0xE9B962
        case .wallCream, .wallCreamB: 0xF0DFC0
        case .wallRose, .wallRoseB: 0xE7A69A
        case .wallSienna, .wallSiennaB: 0xC56A45
        case .contactShadow: 0x1A1220
        case .plinth: 0xCFC2AE
        case .cornice: 0xF5ECDC
        case .roofFlat: 0x9C8E86
        case .roofTiles: 0xB8573A
        case .bark: 0x5B4030
        case .foliage: 0x5E9440
        case .foliageDark: 0x2F5A34
        case .pineCrown: 0x4C7A3A
        case .bush: 0x4F8A3C
        case .flowers: 0xF07A8E
        case .lampPole: 0x2A2428
        case .lampHead: 0xFFE2A6
        case .bench: 0x7A4E32
        case .fountainStone: 0xE6DCCB
        case .fountainWater: 0x6EC6E8
        case .poiCrystal: 0xF7D774
        }
    }

    var roughness: Float {
        switch self {
        case .road: 0.85
        case .laneMark: 0.6
        case .lampPole: 0.4
        case .lampHead, .poiCrystal: 0.2
        case .water, .fountainWater: 0.06
        case .cornice, .fountainStone: 0.7
        default: 0.95
        }
    }

    var isWall: Bool { Self.walls.contains(self) }
    /// Paved surfaces that turn glossy and darker in the rain.
    var getsWet: Bool {
        switch self {
        case .road, .sidewalk, .plaza, .path, .curb, .laneMark, .ground, .roofFlat, .roofTiles, .bench, .fountainStone: true
        default: false
        }
    }
    /// Flat ground layers and glowing bits don't cast shadows.
    var castsShadow: Bool {
        switch self {
        case .ground, .grass, .water, .plaza, .sidewalk, .curb, .path, .road, .laneMark, .lampHead, .fountainWater, .flowers, .poiCrystal, .contactShadow: false
        default: true
        }
    }

    /// Building wall colour from the OSM `building:colour` tag, else a stable pick by id.
    static func wall(colour: String?, id: Int) -> WorldSurface {
        let base = baseWall(colour: colour, id: id)
        // Roughly two in five buildings get the balcony façade (stable per building).
        return (abs(id) / 7) % 5 < 2 ? base.balconyVariant : base
    }

    private static func baseWall(colour: String?, id: Int) -> WorldSurface {
        if let c = colour?.lowercased() {
            if c.contains("yellow") || c.contains("ochre") || c.contains("gold") { return .wallOchre }
            if c.contains("pink") || c.contains("rose") || c.contains("salmon") { return .wallRose }
            if c.contains("orange") || c.contains("sienna") { return .wallSienna }
            if c.contains("red") || c.contains("brown") || c.contains("brick") || c.contains("terracotta") { return .wallTerracotta }
            if c.contains("white") || c.contains("beige") || c.contains("cream") || c.contains("grey") || c.contains("gray") { return .wallCream }
        }
        // Weighted toward the warm Italian palette.
        let picks: [WorldSurface] = [.wallOchre, .wallTerracotta, .wallCream, .wallOchre, .wallRose, .wallSienna, .wallCream, .wallTerracotta]
        return picks[abs(id) % picks.count]
    }
}

/// Builds (and rebuilds per lighting preset and wetness) the shared world materials.
/// All textures are procedural, painted once with Core Graphics.
final class WorldMaterials {
    static let shared = WorldMaterials()

    private var cache: [String: RealityKit.Material] = [:]
    private var facades: [WorldSurface: MaterialParameters.Texture] = [:]
    private lazy var facadeGlow = Self.texture(Self.paintFacade(wall: nil, glow: true))
    private lazy var balconyGlow = Self.texture(Self.paintBalconyFacade(wall: nil, glow: true))
    private lazy var contactFade = Self.texture(Self.paintContactFade())
    private lazy var plinthTexture = Self.texture(Self.paintPlinth(glow: false))
    private lazy var plinthGlow = Self.texture(Self.paintPlinth(glow: true))
    private lazy var asphalt = Self.texture(Self.paintAsphalt())
    private lazy var slabs = Self.texture(Self.paintSlabs())
    private lazy var cobbles = Self.texture(Self.paintCobbles())
    private lazy var grassTexture = Self.texture(Self.paintGrass())
    private lazy var tiles = Self.texture(Self.paintRoofTiles())
    private lazy var gravel = Self.texture(Self.paintGravel())

    func material(_ surface: WorldSurface, preset: LightingPreset, wet: Bool = false) -> RealityKit.Material {
        let isWet = wet && surface.getsWet
        let key = "\(surface.rawValue)-\(preset.rawValue)-\(isWet)"
        if let m = cache[key] { return m }
        let m = make(surface, preset: preset, wet: isWet)
        cache[key] = m
        return m
    }

    private func make(_ surface: WorldSurface, preset: LightingPreset, wet: Bool) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        let brightness = preset.surfaceBrightness * (wet ? 0.74 : 1)
        let tint = Self.scaled(UIColor(hex: surface.baseColor), by: brightness)
        let grey = UIColor(white: brightness, alpha: 1)
        m.baseColor = .init(tint: tint)
        m.roughness = .init(floatLiteral: wet ? 0.18 : surface.roughness)
        m.metallic = .init(floatLiteral: surface == .lampPole ? 0.6 : 0)
        m.faceCulling = .none
        if wet {
            m.clearcoat = .init(floatLiteral: 1)
            m.clearcoatRoughness = .init(floatLiteral: 0.06)
        }

        switch surface {
        case _ where surface.isWall:
            // The wall colour is baked into its façade so shutters keep their own green.
            if let facade = facade(for: surface) { m.baseColor = .init(tint: grey, texture: facade) }
            if preset.windowGlow > 0, let glow = surface.isBalconyStyle ? balconyGlow : facadeGlow {
                m.emissiveColor = .init(color: UIColor(hex: 0xFFC872), texture: glow)
                m.emissiveIntensity = preset.windowGlow
            }
        case .contactShadow:
            // Fake ambient occlusion: a soft dark fade where walls meet the street.
            m.baseColor = .init(tint: .black)
            m.roughness = .init(floatLiteral: 1)
            if let contactFade {
                m.blending = .transparent(opacity: .init(scale: preset.isDark ? 0.32 : 0.42, texture: contactFade))
            }
        case .plinth:
            if let plinthTexture { m.baseColor = .init(tint: grey, texture: plinthTexture) }
            if preset.windowGlow > 0, let plinthGlow {
                m.emissiveColor = .init(color: UIColor(hex: 0xFFD08A), texture: plinthGlow)
                m.emissiveIntensity = preset.windowGlow * 1.2
            }
        case .road:
            if let asphalt { m.baseColor = .init(tint: tint, texture: asphalt) }
        case .sidewalk, .curb:
            if let slabs { m.baseColor = .init(tint: tint, texture: slabs) }
        case .plaza:
            if let cobbles { m.baseColor = .init(tint: tint, texture: cobbles) }
        case .grass:
            if let grassTexture { m.baseColor = .init(tint: tint, texture: grassTexture) }
        case .path, .ground:
            if let gravel { m.baseColor = .init(tint: tint, texture: gravel) }
        case .roofTiles:
            if let tiles { m.baseColor = .init(tint: tint, texture: tiles) }
        case .lampHead:
            m.emissiveColor = .init(color: UIColor(hex: 0xFFC872))
            m.emissiveIntensity = preset.lampGlow
        case .laneMark where preset.isDark:
            m.baseColor = .init(tint: UIColor(hex: 0x8C8778))
        case .water, .fountainWater:
            m.clearcoat = .init(floatLiteral: 1)
            m.clearcoatRoughness = .init(floatLiteral: 0.03)
            m.blending = .transparent(opacity: .init(floatLiteral: surface == .water ? 0.92 : 0.78))
            if preset.isDark {
                m.emissiveColor = .init(color: UIColor(hex: 0x3B7BD4))
                m.emissiveIntensity = 0.25
            }
        case .poiCrystal:
            m.emissiveColor = .init(color: UIColor(hex: 0xE8B02E))
            m.emissiveIntensity = preset.isDark ? 2.2 : 0.9
            m.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        case .flowers:
            m.emissiveColor = .init(color: UIColor(hex: 0xF07A8E))
            m.emissiveIntensity = 0.12
        default:
            break
        }
        return m
    }

    private func facade(for wall: WorldSurface) -> MaterialParameters.Texture? {
        if let t = facades[wall] { return t }
        let image = wall.isBalconyStyle ? Self.paintBalconyFacade(wall: wall, glow: false) : Self.paintFacade(wall: wall, glow: false)
        guard let t = Self.texture(image) else { return nil }
        facades[wall] = t
        return t
    }

    static func scaled(_ color: UIColor, by factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }

    // MARK: - Texture plumbing

    private static func texture(_ image: CGImage?) -> MaterialParameters.Texture? {
        guard let image, let resource = try? TextureResource(image: image, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        else { return nil }
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        return MaterialParameters.Texture(resource, sampler: .init(descriptor))
    }

    private static func paint(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        // Painted at 2× (512 px for a 256-pt canvas): crisper façades and streets up close.
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            draw(ctx.cgContext)
        }.cgImage
    }

    /// Deterministic noise so textures are identical every launch.
    private struct RNG {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) % 100_000) / 100_000
        }
    }

    private static func gray(_ v: CGFloat) -> CGColor { UIColor(white: v, alpha: 1).cgColor }

    // MARK: - Painters

    /// 2 bays × 2 floors (7.2 m × 6.4 m). Arched windows, green shutters, stone sills, string course.
    private static func paintFacade(wall: WorldSurface?, glow: Bool) -> CGImage? {
        paint(256, 256) { cg in
            let wallColor = wall.map { UIColor(hex: $0.baseColor) } ?? .black
            cg.setFillColor(glow ? UIColor.black.cgColor : wallColor.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))

            var rng = RNG(state: UInt64(wall?.baseColor ?? 7))
            if !glow {
                // Plaster mottling.
                for _ in 0..<420 {
                    let x = rng.next() * 256, y = rng.next() * 256, r = 3 + rng.next() * 12
                    let lighten = rng.next() > 0.5
                    cg.setFillColor((lighten ? UIColor.white : UIColor.black).withAlphaComponent(0.035).cgColor)
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
                // String course + cornice line per floor.
                cg.setFillColor(UIColor(hex: 0xF7EEDD).withAlphaComponent(0.85).cgColor)
                cg.fill(CGRect(x: 0, y: 122, width: 256, height: 6))
                cg.fill(CGRect(x: 0, y: 250, width: 256, height: 6))
                cg.setFillColor(UIColor.black.withAlphaComponent(0.12).cgColor)
                cg.fill(CGRect(x: 0, y: 128, width: 256, height: 2))
            }
            let lit = [true, false, true, true]
            for bay in 0..<4 {
                let col = bay % 2, row = bay / 2
                let w: CGFloat = 40, h: CGFloat = 70
                let x = CGFloat(col) * 128 + (128 - w) / 2
                let y = CGFloat(row) * 128 + 28
                let window = CGMutablePath()
                window.addRect(CGRect(x: x, y: y + w / 2, width: w, height: h - w / 2))
                window.addEllipse(in: CGRect(x: x, y: y, width: w, height: w))
                if glow {
                    cg.setFillColor((lit[bay] ? UIColor.white : UIColor.black).cgColor)
                    cg.addPath(window)
                    cg.fillPath()
                    continue
                }
                // Stone surround
                cg.setFillColor(UIColor(hex: 0xF4ECDD).cgColor)
                let frame = CGMutablePath()
                frame.addRect(CGRect(x: x - 6, y: y + w / 2, width: w + 12, height: h - w / 2 + 4))
                frame.addEllipse(in: CGRect(x: x - 6, y: y - 6, width: w + 12, height: w + 12))
                cg.addPath(frame)
                cg.fillPath()
                // Glass with sky reflection
                let glass = [UIColor(hex: 0x6F8FB8).cgColor, UIColor(hex: 0x2E3550).cgColor] as CFArray
                cg.saveGState()
                cg.addPath(window)
                cg.clip()
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glass, locations: [0, 1]) {
                    cg.drawLinearGradient(g, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h), options: [])
                }
                cg.setFillColor(UIColor(hex: 0xF4ECDD).cgColor)
                cg.fill(CGRect(x: x + w / 2 - 1.5, y: y, width: 3, height: h))
                cg.fill(CGRect(x: x, y: y + h * 0.55, width: w, height: 3))
                cg.restoreGState()
                // Persiane: green louvred shutters, some half-closed.
                let shutter = UIColor(hex: 0x4F7A5A)
                let open = (bay + Int(wall?.baseColor ?? 0)) % 3 != 0
                let sw: CGFloat = open ? 15 : w / 2
                for side in [0, 1] {
                    let sx = open ? (side == 0 ? x - 6 - sw : x + w + 6) : (side == 0 ? x : x + w / 2)
                    let rect = CGRect(x: sx, y: y + 6, width: sw, height: h - 6)
                    cg.setFillColor(shutter.cgColor)
                    cg.fill(rect)
                    cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
                    var ly = rect.minY + 4
                    while ly < rect.maxY - 2 { cg.fill(CGRect(x: rect.minX + 2, y: ly, width: rect.width - 4, height: 1.5)); ly += 5 }
                }
                // Sill + flower box on some windows.
                cg.setFillColor(UIColor(hex: 0xF7F0E2).cgColor)
                cg.fill(CGRect(x: x - 10, y: y + h + 2, width: w + 20, height: 6))
                if (bay + col) % 2 == 0 {
                    cg.setFillColor(UIColor(hex: 0x3E6B3A).cgColor)
                    cg.fill(CGRect(x: x - 2, y: y + h - 6, width: w + 4, height: 8))
                    for i in 0..<6 {
                        cg.setFillColor(UIColor(hex: i % 2 == 0 ? 0xE5484D : 0xF2A541).cgColor)
                        cg.fillEllipse(in: CGRect(x: x + CGFloat(i) * 7, y: y + h - 10, width: 6, height: 6))
                    }
                }
            }
        }
    }

    /// Balcony style, same 7.2 m × 6.4 m tile: tall rectangular French windows with stone frames and
    /// pediments, wrought-iron balconies on the upper floor, warm wooden shutters below.
    private static func paintBalconyFacade(wall: WorldSurface?, glow: Bool) -> CGImage? {
        paint(256, 256) { cg in
            let wallColor = wall.map { UIColor(hex: $0.baseColor) } ?? .black
            cg.setFillColor(glow ? UIColor.black.cgColor : wallColor.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: UInt64(wall?.baseColor ?? 9) &+ 77)
            if !glow {
                for _ in 0..<380 {
                    let x = rng.next() * 256, y = rng.next() * 256, r = 4 + rng.next() * 14
                    cg.setFillColor((rng.next() > 0.5 ? UIColor.white : UIColor.black).withAlphaComponent(0.03).cgColor)
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
                // Thin pilasters at the tile edges and a floor band.
                cg.setFillColor(UIColor.white.withAlphaComponent(0.16).cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: 7, height: 256))
                cg.fill(CGRect(x: 249, y: 0, width: 7, height: 256))
                cg.setFillColor(UIColor(hex: 0xF7EEDD).withAlphaComponent(0.8).cgColor)
                cg.fill(CGRect(x: 0, y: 124, width: 256, height: 4))
                cg.setFillColor(UIColor.black.withAlphaComponent(0.1).cgColor)
                cg.fill(CGRect(x: 0, y: 128, width: 256, height: 2))
            }
            let lit = [false, true, true, false]
            for bay in 0..<4 {
                let col = bay % 2, row = bay / 2
                let upper = row == 0 // y grows downward in the image; the top row is the upper floor
                let w: CGFloat = 38, h: CGFloat = upper ? 84 : 72
                let x = CGFloat(col) * 128 + (128 - w) / 2
                let y = CGFloat(row) * 128 + (upper ? 22 : 30)
                let window = CGRect(x: x, y: y, width: w, height: h)
                if glow {
                    cg.setFillColor((lit[bay] ? UIColor.white : UIColor.black).cgColor)
                    cg.fill(window)
                    continue
                }
                // Stone frame + small pediment.
                cg.setFillColor(UIColor(hex: 0xF4ECDD).cgColor)
                cg.fill(window.insetBy(dx: -5, dy: -5))
                cg.fill(CGRect(x: x - 9, y: y - 12, width: w + 18, height: 6))
                cg.setFillColor(UIColor.black.withAlphaComponent(0.12).cgColor)
                cg.fill(CGRect(x: x - 9, y: y - 6, width: w + 18, height: 1.5))
                // Glass with sky gradient + mullions.
                let glass = [UIColor(hex: 0x7C9CC2).cgColor, UIColor(hex: 0x2B3352).cgColor] as CFArray
                cg.saveGState()
                cg.clip(to: window)
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glass, locations: [0, 1]) {
                    cg.drawLinearGradient(g, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h), options: [])
                }
                cg.setFillColor(UIColor(hex: 0xF4ECDD).cgColor)
                cg.fill(CGRect(x: x + w / 2 - 1.5, y: y, width: 3, height: h))
                var my = y + h * 0.3
                while my < y + h - 4 { cg.fill(CGRect(x: x, y: my, width: w, height: 2)); my += h * 0.3 }
                cg.restoreGState()
                // Folded wooden shutters (warm brown on some, green on others).
                let shutter = UIColor(hex: (bay + Int(wall?.baseColor ?? 0)) % 2 == 0 ? 0x8A5A3A : 0x4F7A5A)
                for side in [0, 1] {
                    let rect = CGRect(x: side == 0 ? x - 5 - 13 : x + w + 5, y: y, width: 13, height: h)
                    cg.setFillColor(shutter.cgColor)
                    cg.fill(rect)
                    cg.setFillColor(UIColor.black.withAlphaComponent(0.2).cgColor)
                    var ly = rect.minY + 4
                    while ly < rect.maxY - 2 { cg.fill(CGRect(x: rect.minX + 2, y: ly, width: rect.width - 4, height: 1.5)); ly += 5 }
                }
                if upper {
                    // Wrought-iron balcony on a stone slab.
                    let slab = CGRect(x: x - 16, y: y + h - 2, width: w + 32, height: 6)
                    cg.setFillColor(UIColor(hex: 0xEDE3D2).cgColor)
                    cg.fill(slab)
                    cg.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
                    cg.fill(CGRect(x: slab.minX + 2, y: slab.maxY, width: slab.width - 4, height: 3))
                    let iron = UIColor(hex: 0x2A2428).cgColor
                    cg.setFillColor(iron)
                    let railTop = slab.minY - 22
                    cg.fill(CGRect(x: slab.minX, y: railTop, width: slab.width, height: 2.5))
                    cg.fill(CGRect(x: slab.minX, y: slab.minY - 4, width: slab.width, height: 2))
                    var bx = slab.minX
                    while bx <= slab.maxX - 1.5 { cg.fill(CGRect(x: bx, y: railTop, width: 1.5, height: 22)); bx += 5 }
                    cg.setStrokeColor(iron); cg.setLineWidth(1.2)
                    for i in 0..<3 {
                        let cx = slab.minX + slab.width * (CGFloat(i) + 0.5) / 3
                        cg.strokeEllipse(in: CGRect(x: cx - 5, y: railTop + 6, width: 10, height: 10))
                    }
                    // Potted geraniums.
                    for i in 0..<4 where (i + bay) % 2 == 0 {
                        let px = slab.minX + 6 + CGFloat(i) * (slab.width - 12) / 3
                        cg.setFillColor(UIColor(hex: 0xB8573A).cgColor)
                        cg.fill(CGRect(x: px - 3, y: slab.minY - 8, width: 7, height: 6))
                        cg.setFillColor(UIColor(hex: 0x3E6B3A).cgColor)
                        cg.fillEllipse(in: CGRect(x: px - 5, y: slab.minY - 15, width: 11, height: 8))
                        cg.setFillColor(UIColor(hex: 0xE5484D).cgColor)
                        cg.fillEllipse(in: CGRect(x: px - 2, y: slab.minY - 16, width: 5, height: 5))
                    }
                } else {
                    cg.setFillColor(UIColor(hex: 0xF7F0E2).cgColor)
                    cg.fill(CGRect(x: x - 9, y: y + h + 4, width: w + 18, height: 5))
                }
            }
        }
    }

    /// Horizontal fade (opaque at the wall, clear 1.4 m out) for the contact-shadow ribbon.
    private static func paintContactFade() -> CGImage? {
        paint(64, 8) { cg in
            let colors = [gray(1), gray(0.35), gray(0)] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.35, 1]) {
                cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 64, y: 0), options: [.drawsAfterEndLocation])
            }
        }
    }

    /// Rusticated ground floor (7.2 m × 3.6 m): bugnato stone bands, an arched door and a shopfront with an awning.
    private static func paintPlinth(glow: Bool) -> CGImage? {
        paint(256, 128) { cg in
            cg.setFillColor(glow ? UIColor.black.cgColor : UIColor(hex: 0xE9DFCD).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
            if !glow {
                cg.setFillColor(UIColor.black.withAlphaComponent(0.16).cgColor)
                var y: CGFloat = 14
                while y < 128 { cg.fill(CGRect(x: 0, y: y, width: 256, height: 2)); y += 16 }
                var row = 0
                y = 0
                while y < 128 {
                    var x: CGFloat = row % 2 == 0 ? 0 : 24
                    while x < 256 { cg.fill(CGRect(x: x, y: y, width: 2, height: 14)); x += 48 }
                    y += 16; row += 1
                }
            }
            // Arched wooden door (bay 1).
            let door = CGMutablePath()
            door.addRect(CGRect(x: 36, y: 46, width: 56, height: 82))
            door.addEllipse(in: CGRect(x: 36, y: 18, width: 56, height: 56))
            if glow {
                cg.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
                cg.addPath(door); cg.fillPath()
            } else {
                cg.setFillColor(UIColor(hex: 0xF4ECDD).cgColor)
                cg.fill(CGRect(x: 30, y: 40, width: 68, height: 88))
                cg.fillEllipse(in: CGRect(x: 30, y: 12, width: 68, height: 68))
                cg.setFillColor(UIColor(hex: 0x5A3624).cgColor)
                cg.addPath(door); cg.fillPath()
                cg.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
                cg.fill(CGRect(x: 63, y: 46, width: 2, height: 82))
                cg.setFillColor(UIColor(hex: 0xE8B02E).cgColor)
                cg.fillEllipse(in: CGRect(x: 56, y: 86, width: 5, height: 5))
                cg.fillEllipse(in: CGRect(x: 68, y: 86, width: 5, height: 5))
            }
            // Shopfront (bay 2) with striped awning.
            let shop = CGRect(x: 152, y: 52, width: 84, height: 76)
            if glow {
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(shop)
            } else {
                cg.setFillColor(UIColor(hex: 0x2B2A3A).cgColor)
                cg.fill(shop.insetBy(dx: -4, dy: 0))
                let glass = [UIColor(hex: 0x8FB0C9).cgColor, UIColor(hex: 0x3A4560).cgColor] as CFArray
                cg.saveGState()
                cg.clip(to: shop.insetBy(dx: 4, dy: 4))
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glass, locations: [0, 1]) {
                    cg.drawLinearGradient(g, start: CGPoint(x: shop.minX, y: shop.minY), end: CGPoint(x: shop.maxX, y: shop.maxY), options: [])
                }
                cg.restoreGState()
                for i in 0..<7 {
                    cg.setFillColor(UIColor(hex: i % 2 == 0 ? 0x2E6B4F : 0xF4ECDD).cgColor)
                    cg.fill(CGRect(x: 146 + CGFloat(i) * 14, y: 30, width: 14, height: 20))
                }
                cg.setFillColor(UIColor.black.withAlphaComponent(0.2).cgColor)
                cg.fill(CGRect(x: 146, y: 50, width: 98, height: 3))
            }
        }
    }

    private static func paintAsphalt() -> CGImage? {
        paint(256, 256) { cg in
            cg.setFillColor(gray(0.86)); cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: 11)
            for _ in 0..<5000 {
                let v = 0.68 + rng.next() * 0.34
                cg.setFillColor(gray(v))
                cg.fill(CGRect(x: rng.next() * 256, y: rng.next() * 256, width: 1.5, height: 1.5))
            }
            // Patches and hairline cracks.
            for _ in 0..<6 {
                cg.setFillColor(gray(0.78 + rng.next() * 0.06))
                cg.fill(CGRect(x: rng.next() * 220, y: rng.next() * 220, width: 20 + rng.next() * 40, height: 14 + rng.next() * 30))
            }
            cg.setStrokeColor(gray(0.62)); cg.setLineWidth(1)
            for _ in 0..<8 {
                var p = CGPoint(x: rng.next() * 256, y: rng.next() * 256)
                cg.move(to: p)
                for _ in 0..<6 { p.x += (rng.next() - 0.5) * 24; p.y += (rng.next() - 0.5) * 24; cg.addLine(to: p) }
                cg.strokePath()
            }
        }
    }

    /// Sidewalk slabs (4 × 4 per 6 m).
    private static func paintSlabs() -> CGImage? {
        paint(256, 256) { cg in
            cg.setFillColor(gray(0.95)); cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: 21)
            for i in 0..<4 { for j in 0..<4 {
                cg.setFillColor(gray(0.86 + rng.next() * 0.12))
                cg.fill(CGRect(x: CGFloat(i) * 64 + 2, y: CGFloat(j) * 64 + 2, width: 60, height: 60))
            } }
            for _ in 0..<1600 {
                cg.setFillColor(gray(0.8 + rng.next() * 0.2))
                cg.fill(CGRect(x: rng.next() * 256, y: rng.next() * 256, width: 1, height: 1))
            }
        }
    }

    /// Sampietrini: small square cobbles in fan-ish offset rows.
    private static func paintCobbles() -> CGImage? {
        paint(256, 256) { cg in
            cg.setFillColor(gray(0.58)); cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: 31)
            let s: CGFloat = 16
            for row in 0..<16 {
                let offset = row % 2 == 0 ? 0 : s / 2
                for col in -1..<17 {
                    let x = CGFloat(col) * s + offset, y = CGFloat(row) * s
                    cg.setFillColor(gray(0.78 + rng.next() * 0.22))
                    let r = CGRect(x: x + 1.5, y: y + 1.5, width: s - 3, height: s - 3)
                    cg.addPath(CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil))
                    cg.fillPath()
                    cg.setFillColor(UIColor.white.withAlphaComponent(0.14).cgColor)
                    cg.fill(CGRect(x: r.minX + 2, y: r.minY + 2, width: r.width - 6, height: 2))
                }
            }
        }
    }

    private static func paintGrass() -> CGImage? {
        paint(256, 256) { cg in
            cg.setFillColor(gray(0.9)); cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: 41)
            for _ in 0..<260 {
                let r = 8 + rng.next() * 30
                cg.setFillColor(gray(0.8 + rng.next() * 0.25).copy(alpha: 0.5) ?? gray(0.9))
                cg.fillEllipse(in: CGRect(x: rng.next() * 256 - r / 2, y: rng.next() * 256 - r / 2, width: r, height: r))
            }
            for _ in 0..<2600 {
                cg.setFillColor(gray(0.7 + rng.next() * 0.35))
                let x = rng.next() * 256, y = rng.next() * 256
                cg.fill(CGRect(x: x, y: y, width: 1, height: 3))
            }
        }
    }

    private static func paintGravel() -> CGImage? {
        paint(256, 256) { cg in
            cg.setFillColor(gray(0.9)); cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: 51)
            for _ in 0..<3200 {
                let r = 1 + rng.next() * 3
                cg.setFillColor(gray(0.72 + rng.next() * 0.3))
                cg.fillEllipse(in: CGRect(x: rng.next() * 256, y: rng.next() * 256, width: r, height: r))
            }
        }
    }

    /// Coppi: rows of half-round terracotta tiles.
    private static func paintRoofTiles() -> CGImage? {
        paint(256, 256) { cg in
            cg.setFillColor(gray(0.7)); cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = RNG(state: 61)
            let w: CGFloat = 16, h: CGFloat = 32
            for row in 0..<8 {
                for col in 0..<16 {
                    let x = CGFloat(col) * w, y = CGFloat(row) * h
                    let v = 0.86 + rng.next() * 0.14
                    let colors = [gray(v), gray(v * 0.72)] as CFArray
                    cg.saveGState()
                    cg.clip(to: CGRect(x: x + 1, y: y, width: w - 2, height: h - 2))
                    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
                        cg.drawLinearGradient(g, start: CGPoint(x: x + w / 2, y: y), end: CGPoint(x: x + w, y: y), options: [.drawsBeforeStartLocation])
                    }
                    cg.restoreGState()
                    cg.setFillColor(gray(0.55))
                    cg.fill(CGRect(x: x, y: y + h - 3, width: w, height: 3))
                }
            }
        }
    }
}
