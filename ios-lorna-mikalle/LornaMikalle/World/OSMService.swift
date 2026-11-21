import CoreLocation
import Foundation

/// Real-world map data (OpenStreetMap via Overpass) — the geographic foundation of the 3D world.
nonisolated struct OSMData: Sendable {
    struct Building: Sendable {
        let id: Int
        let ring: [CLLocationCoordinate2D]
        let height: Double
        let levels: Int
        let roofShape: String?
        let colour: String?
    }
    struct Road: Sendable { let id: Int; let kind: RoadKind; let points: [CLLocationCoordinate2D] }
    struct Area: Sendable { let id: Int; let ring: [CLLocationCoordinate2D] }
    struct Point: Sendable { let id: Int; let coordinate: CLLocationCoordinate2D }
    struct POI: Sendable {
        let id: Int
        let name: String
        let category: POICategory
        let coordinate: CLLocationCoordinate2D
    }

    var buildings: [Building] = []
    var roads: [Road] = []
    var greens: [Area] = []
    var water: [Area] = []
    var plazas: [Area] = []
    var trees: [Point] = []
    var lamps: [Point] = []
    var benches: [Point] = []
    var fountains: [Point] = []
    var pois: [POI] = []
}

/// Interactive real-world places. Only named, mapped places become points of interest.
nonisolated enum POICategory: String, Codable, Sendable {
    case church, fountain, cafe, museum, monument, park, library, theatre, viewpoint, market, landmark

    var title: String {
        switch self {
        case .church: "Church"
        case .fountain: "Fountain"
        case .cafe: "Café"
        case .museum: "Museum"
        case .monument: "Monument"
        case .park: "Park"
        case .library: "Library"
        case .theatre: "Theatre"
        case .viewpoint: "Viewpoint"
        case .market: "Market"
        case .landmark: "Landmark"
        }
    }

    var symbol: String {
        switch self {
        case .church: "building.columns"
        case .fountain: "drop.fill"
        case .cafe: "cup.and.saucer.fill"
        case .museum: "building.columns.fill"
        case .monument: "star.circle.fill"
        case .park: "tree.fill"
        case .library: "books.vertical.fill"
        case .theatre: "theatermasks.fill"
        case .viewpoint: "binoculars.fill"
        case .market: "basket.fill"
        case .landmark: "mappin.and.ellipse"
        }
    }

    static func from(tags: [String: String]) -> POICategory? {
        switch tags["amenity"] {
        case "place_of_worship": return .church
        case "fountain": return .fountain
        case "cafe", "ice_cream": return .cafe
        case "library": return .library
        case "theatre", "arts_centre", "cinema": return .theatre
        case "marketplace": return .market
        case "townhall": return .landmark
        default: break
        }
        switch tags["tourism"] {
        case "museum", "gallery": return .museum
        case "artwork": return .monument
        case "viewpoint": return .viewpoint
        case "attraction": return .landmark
        default: break
        }
        if let historic = tags["historic"], historic != "no" { return .monument }
        if tags["leisure"] == "park" { return .park }
        return nil
    }
}

nonisolated enum RoadKind: Sendable {
    case major, street, service, path

    var width: Float {
        switch self {
        case .major: 10
        case .street: 7
        case .service: 4.5
        case .path: 2.2
        }
    }

    var hasSidewalk: Bool { self == .major || self == .street }

    static func from(highway: String) -> RoadKind? {
        switch highway {
        case "motorway", "trunk", "primary", "secondary", "motorway_link", "trunk_link", "primary_link", "secondary_link":
            return .major
        case "tertiary", "tertiary_link", "residential", "unclassified", "living_street", "road":
            return .street
        case "service", "pedestrian", "track":
            return .service
        case "footway", "path", "cycleway", "steps", "bridleway", "sidewalk":
            return .path
        default:
            return nil
        }
    }
}

/// A fixed map tile (Web-Mercator zoom 16, about 430 m wide in Italy). Fixed tiles make
/// caching exact: the same street is always fetched once and reused from disk.
nonisolated struct TileKey: Hashable, Sendable, CustomStringConvertible {
    static let zoom = 16
    let x: Int
    let y: Int

    init(x: Int, y: Int) { self.x = x; self.y = y }

    init(containing c: CLLocationCoordinate2D) {
        let n = Double(1 << Self.zoom)
        let latRad = c.latitude * .pi / 180
        x = Int(floor((c.longitude + 180) / 360 * n))
        y = Int(floor((1 - asinh(tan(latRad)) / .pi) / 2 * n))
    }

    var description: String { "z\(Self.zoom)_\(x)_\(y)" }

    /// south, west, north, east
    var bounds: (s: Double, w: Double, n: Double, e: Double) {
        let n = Double(1 << Self.zoom)
        func lon(_ x: Int) -> Double { Double(x) / n * 360 - 180 }
        func lat(_ y: Int) -> Double { atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180 / .pi }
        return (lat(y + 1), lon(x), lat(y), lon(x + 1))
    }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        let b = bounds
        return c.latitude >= b.s && c.latitude < b.n && c.longitude >= b.w && c.longitude < b.e
    }

    var center: CLLocationCoordinate2D {
        let b = bounds
        return CLLocationCoordinate2D(latitude: (b.s + b.n) / 2, longitude: (b.w + b.e) / 2)
    }
}

nonisolated enum OSMError: Error, Sendable {
    case offline, rateLimited, server(Int), badData

    var userMessage: String {
        switch self {
        case .offline: "No internet connection"
        case .rateLimited: "Map servers are busy"
        case .server: "Map server unavailable"
        case .badData: "Map data could not be read"
        }
    }
}

/// Shares one in-flight request per tile so a tile is never downloaded twice at once.
actor InFlightTiles {
    static let shared = InFlightTiles()
    private var tasks: [TileKey: Task<OSMService.Result, Error>] = [:]

    func run(_ tile: TileKey, _ work: @escaping @Sendable () async throws -> OSMService.Result) async throws -> OSMService.Result {
        if let existing = tasks[tile] { return try await existing.value }
        let task = Task { try await work() }
        tasks[tile] = task
        defer { tasks[tile] = nil }
        return try await task.value
    }
}

nonisolated enum OSMService {
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]
    /// Cached tiles are fresh for two weeks; older ones are still shown at once and refreshed
    /// quietly in the background (stale-while-revalidate).
    private static let freshness: TimeInterval = 14 * 24 * 3600
    /// Housekeeping limits for the on-device tile cache.
    private static let maxCacheAge: TimeInterval = 120 * 24 * 3600
    private static let maxCacheBytes = 250 * 1024 * 1024

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("osm-tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    struct Result: Sendable {
        let data: OSMData
        let fromCache: Bool
        /// Came from a cache older than `freshness`; the caller may refresh it in the background.
        var stale = false
    }

    /// Loads one tile: any saved copy first (instant, even when old), else the network (hedged
    /// mirrors). Concurrent callers for the same tile share one request.
    static func fetch(tile: TileKey) async throws -> Result {
        try await InFlightTiles.shared.run(tile) { try await fetchUncoalesced(tile: tile) }
    }

    /// Fresh cached data only (no network), for instant start.
    static func cachedIfFresh(tile: TileKey) -> Bool {
        let cacheURL = cacheDirectory.appendingPathComponent("\(tile).json")
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let age = (attributes?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        return age < freshness
    }

    /// A tiny, fast first look (only buildings and streets within ~150 m) so the player has a
    /// street in seconds while the first full tile streams in. Much lighter than a tile query.
    static func fetchPreview(around c: CLLocationCoordinate2D) async throws -> OSMData {
        let dLat = 150.0 / 111_320
        let dLon = 150.0 / (111_320 * max(0.2, cos(c.latitude * .pi / 180)))
        let bbox = String(format: "%.6f,%.6f,%.6f,%.6f", c.latitude - dLat, c.longitude - dLon, c.latitude + dLat, c.longitude + dLon)
        let query = """
        [out:json][timeout:8][bbox:\(bbox)];
        (
          way["building"];
          way["highway"];
        );
        out geom qt;
        """
        return try parse(try await hedgedPost(query: query, hedgeDelay: .milliseconds(2000)))
    }

    private static func cacheURL(_ tile: TileKey) -> URL {
        cacheDirectory.appendingPathComponent("\(tile).json")
    }

    private static func cacheAge(_ url: URL) -> TimeInterval {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
    }

    private static func fetchUncoalesced(tile: TileKey) async throws -> Result {
        let url = cacheURL(tile)
        let age = cacheAge(url)
        // Any saved copy is shown immediately; a stale one is refreshed later, off the critical path.
        if age.isFinite, let cached = try? Data(contentsOf: url), let parsed = try? parse(cached) {
            return Result(data: parsed, fromCache: true, stale: age >= freshness)
        }
        let raw = try await download(tile: tile)
        let parsed = try parse(raw)
        try? raw.write(to: url, options: .atomic)
        return Result(data: parsed, fromCache: false)
    }

    /// Downloads a tile to disk only (prefetch ahead of the player, or refresh of a stale copy).
    /// Never touches the scene. Skips tiles that already have a fresh copy.
    static func storeOnDisk(tile: TileKey) async throws {
        let url = cacheURL(tile)
        guard cacheAge(url) >= freshness else { return }
        let raw = try await download(tile: tile)
        _ = try parse(raw)
        try raw.write(to: url, options: .atomic)
    }

    /// Deletes cached tiles older than four months and trims the cache to its size cap,
    /// oldest first. Runs off the main thread.
    static func housekeeping() async {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = []
        for url in files where url.pathExtension == "json" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(date) > maxCacheAge {
                try? fm.removeItem(at: url)
                continue
            }
            entries.append((url, date, values?.fileSize ?? 0))
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxCacheBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > maxCacheBytes {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    static func hasCache(for tile: TileKey) -> Bool {
        FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent("\(tile).json").path)
    }

    nonisolated(unsafe) private static var preferredEndpoint = 0

    private static func download(tile: TileKey) async throws -> Data {
        let b = tile.bounds
        let bbox = String(format: "%.6f,%.6f,%.6f,%.6f", b.s, b.w, b.n, b.e)
        let query = """
        [out:json][timeout:30][bbox:\(bbox)];
        (
          way["building"];
          relation["building"]["type"="multipolygon"];
          way["highway"];
          way["leisure"~"^(park|garden|pitch|playground)$"];
          relation["leisure"~"^(park|garden)$"]["type"="multipolygon"];
          way["landuse"~"^(grass|meadow|recreation_ground|village_green|forest)$"];
          way["natural"~"^(water|wood|scrub)$"];
          way["place"="square"];
          node["natural"="tree"];
          node["highway"="street_lamp"];
          node["amenity"~"^(bench|fountain|place_of_worship|cafe|ice_cream|library|theatre|arts_centre|marketplace|townhall)$"];
          way["amenity"~"^(fountain|place_of_worship|library|theatre|townhall|marketplace)$"];
          node["tourism"~"^(museum|artwork|viewpoint|attraction|gallery)$"];
          way["tourism"~"^(museum|attraction)$"];
          node["historic"]["name"];
        );
        out geom qt;
        """
        return try await hedgedPost(query: query, hedgeDelay: .milliseconds(3500))
    }

    /// Asks the preferred mirror first; if it hasn't answered after `hedgeDelay` (or fails), the next
    /// mirror starts in parallel. The first good answer wins and the rest are cancelled.
    private static func hedgedPost(query: String, hedgeDelay: Duration) async throws -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)
        let start = preferredEndpoint
        let order = (0..<endpoints.count).map { (start + $0) % endpoints.count }

        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var lastError: OSMError = .server(0)
            var next = 0
            func launch(delay: Duration) {
                guard next < order.count else { return }
                let index = order[next]
                next += 1
                group.addTask {
                    if delay > .zero { try await Task.sleep(for: delay) }
                    return (index, try await post(body: body, endpoint: index))
                }
            }
            launch(delay: .zero)
            launch(delay: hedgeDelay)
            while true {
                do {
                    guard let (index, data) = try await group.next() else { break }
                    preferredEndpoint = index
                    group.cancelAll()
                    return data
                } catch OSMError.offline {
                    group.cancelAll()
                    throw OSMError.offline
                } catch let error as OSMError {
                    lastError = error
                    launch(delay: .zero)
                } catch {
                    lastError = .server(-1)
                    launch(delay: .zero)
                }
            }
            throw lastError
        }
    }

    private static func post(body: Data, endpoint index: Int) async throws -> Data {
        guard let url = URL(string: endpoints[index]) else { throw OSMError.server(0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("LornaMikalle/1.2 (iOS game; contact via App Store)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                // Overpass can answer 200 with a runtime error and no elements.
                if data.count < 200, String(decoding: data, as: UTF8.self).contains("remark") { throw OSMError.server(200) }
                return data
            case 429: throw OSMError.rateLimited
            default: throw OSMError.server(status)
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                throw OSMError.offline
            case .cancelled:
                throw CancellationError()
            default:
                throw OSMError.server(error.errorCode)
            }
        }
    }

    // MARK: - Parsing

    private struct Response: Decodable { let elements: [Element] }
    private struct Element: Decodable {
        let type: String
        let id: Int
        let lat: Double?
        let lon: Double?
        let tags: [String: String]?
        let geometry: [LatLon?]?
        let members: [Member]?
    }
    private struct Member: Decodable {
        let type: String
        let role: String?
        let geometry: [LatLon?]?
    }
    private struct LatLon: Decodable { let lat: Double; let lon: Double }

    static func parse(_ data: Data) throws -> OSMData {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw OSMError.badData }
        var out = OSMData()

        func coords(_ geometry: [LatLon?]?) -> [CLLocationCoordinate2D] {
            (geometry ?? []).compactMap { $0.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } }
        }
        func centroid(_ ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
            let lat = ring.map(\.latitude).reduce(0, +) / Double(ring.count)
            let lon = ring.map(\.longitude).reduce(0, +) / Double(ring.count)
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        func addPOI(id: Int, tags: [String: String], at c: CLLocationCoordinate2D) {
            guard let name = tags["name"], !name.isEmpty, let category = POICategory.from(tags: tags) else { return }
            out.pois.append(.init(id: id, name: name, category: category, coordinate: c))
        }
        func isClosed(_ ring: [CLLocationCoordinate2D]) -> Bool {
            guard let f = ring.first, let l = ring.last, ring.count >= 4 else { return false }
            return abs(f.latitude - l.latitude) < 1e-7 && abs(f.longitude - l.longitude) < 1e-7
        }

        for element in response.elements {
            let tags = element.tags ?? [:]

            if element.type == "node", let lat = element.lat, let lon = element.lon {
                let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                let point = OSMData.Point(id: element.id, coordinate: c)
                if tags["natural"] == "tree" { out.trees.append(point) }
                else if tags["highway"] == "street_lamp" { out.lamps.append(point) }
                else if tags["amenity"] == "bench" { out.benches.append(point) }
                else {
                    if tags["amenity"] == "fountain" { out.fountains.append(point) }
                    addPOI(id: element.id, tags: tags, at: c)
                }
                continue
            }

            if element.type == "relation" {
                // Multipolygon buildings and parks: use each closed outer ring.
                let outers = (element.members ?? []).filter { $0.type == "way" && ($0.role ?? "outer") == "outer" }
                for (i, member) in outers.enumerated() {
                    let ring = coords(member.geometry)
                    guard isClosed(ring) else { continue }
                    let id = -(element.id * 16 + i)
                    if tags["building"] != nil {
                        out.buildings.append(building(id: id, ring: ring, tags: tags))
                    } else {
                        out.greens.append(.init(id: id, ring: ring))
                    }
                    if i == 0 { addPOI(id: -element.id, tags: tags, at: centroid(ring)) }
                }
                continue
            }

            guard element.type == "way" else { continue }
            let ring = coords(element.geometry)
            guard ring.count >= 2 else { continue }

            if tags["building"] != nil, tags["building"] != "no" {
                guard ring.count >= 4 else { continue }
                out.buildings.append(building(id: element.id, ring: ring, tags: tags))
                addPOI(id: element.id, tags: tags, at: centroid(ring))
            } else if let highway = tags["highway"] {
                if tags["tunnel"] == "yes" || tags["indoor"] == "yes" { continue }
                if tags["area"] == "yes" {
                    if highway == "pedestrian" || highway == "footway", ring.count >= 4 {
                        out.plazas.append(.init(id: element.id, ring: ring))
                    }
                    continue
                }
                if let kind = RoadKind.from(highway: highway) {
                    out.roads.append(.init(id: element.id, kind: kind, points: ring))
                }
            } else if tags["place"] == "square" {
                if ring.count >= 4 { out.plazas.append(.init(id: element.id, ring: ring)) }
                addPOI(id: element.id, tags: ["historic": "square", "name": tags["name"] ?? ""], at: centroid(ring))
            } else if tags["natural"] == "water" {
                if ring.count >= 4 { out.water.append(.init(id: element.id, ring: ring)) }
            } else if tags["amenity"] != nil || tags["tourism"] != nil {
                if tags["amenity"] == "fountain", ring.count >= 3 {
                    out.fountains.append(.init(id: element.id, coordinate: centroid(ring)))
                }
                addPOI(id: element.id, tags: tags, at: centroid(ring))
            } else if ring.count >= 4 {
                out.greens.append(.init(id: element.id, ring: ring))
                if tags["leisure"] == "park" { addPOI(id: element.id, tags: tags, at: centroid(ring)) }
            }
        }
        return out
    }

    private static func building(id: Int, ring: [CLLocationCoordinate2D], tags: [String: String]) -> OSMData.Building {
        let levels = tags["building:levels"].flatMap { Double($0) }.map { Int($0) }
        let height = buildingHeight(tags: tags, id: id, levels: levels)
        return .init(
            id: id,
            ring: ring,
            height: height,
            levels: levels ?? max(1, Int((height - 1) / 3.2)),
            roofShape: tags["roof:shape"],
            colour: tags["building:colour"]
        )
    }

    private static func buildingHeight(tags: [String: String], id: Int, levels: Int?) -> Double {
        if let h = tags["height"].flatMap({ Double($0.replacingOccurrences(of: " m", with: "").replacingOccurrences(of: ",", with: ".")) }), h > 2 {
            return min(h, 120)
        }
        if let levels, levels > 0 {
            return min(Double(levels) * 3.2 + 1, 120)
        }
        switch tags["building"] {
        case "garage", "garages", "shed", "roof", "kiosk", "carport", "hut": return 3.5
        case "house", "detached", "semidetached_house", "bungalow", "terrace": return 7.4
        case "church", "cathedral", "chapel": return 18
        default: return 10.6 + Double(abs(id) % 4) * 3.2
        }
    }
}
