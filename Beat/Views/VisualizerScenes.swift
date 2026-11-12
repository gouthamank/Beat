import SwiftUI

/// Colours for the scene styles, which draw their own dark ground: the cover's colours where they show up on
/// it, lightened where they don't.
struct SceneColours: Equatable {
    /// Bars, ridges, grid lines.
    var accent: RGB
    /// The sun, highlights, the brightest sparks.
    var light: RGB
    /// The ground everything sits on: the cover's background, darkened.
    var deep: RGB

    init(palette: ArtworkPalette?) {
        guard let palette else {
            accent = RGB(r: 0.55, g: 0.6, b: 0.95)
            light = RGB(r: 0.9, g: 0.92, b: 1)
            deep = RGB(r: 0.06, g: 0.06, b: 0.09)
            return
        }
        let showing = [palette.primary, palette.secondary].filter { $0.contrast(with: .black) >= 3 }
        accent = showing.first ?? RGB.white.over(palette.primary, opacity: 0.6)
        light = showing.dropFirst().first ?? RGB.white.over(accent, opacity: 0.55)
        deep = RGB.black.over(palette.background, opacity: 0.7)
    }
}

/// The scene styles (Horizon, Terrain, Spectrum Rings, Starfield, Fountain, Constellation, and Bars as
/// a dot matrix). Each
/// keeps what it has seen (ridgelines, rows of terrain, particles) here, advanced once a frame by `step`;
/// `draw` only reads it. Movement is scaled by the frame time, so it keeps its speed if frames drop.
@MainActor
final class VisualizerScenes {
    private var lastDate: Date?
    /// Seconds of animation so far.
    private var time = 0.0
    /// `dt` in 60 fps frames, the unit the speeds below are tuned in.
    private var frames = 1.0
    private var lastKick = -1.0
    /// Reduce Motion: scenes that fly or roll towards you slow right down; levels still move in place.
    private var calm = false
    /// How far Horizon's grid has rolled, kept apart from `time` so calm can slow it alone.
    private var gridRoll = 0.0

    private var terrain: [[Float]] = []
    private var terrainClock = 0.0
    private var waves: [Double] = []
    private var stars: [Star] = []
    private var sparks: [Spark] = []
    private var nodes: [Node] = []

    private struct Star { var x, y, z, tint: Double }
    private struct Spark { var x, y, vx, vy: Double; var band: Int }
    private struct Node { var x, y, vx, vy: Double; var band: Int }

    private static let terrainColumns = 33, terrainRows = 28

    // MARK: Advancing

    func step(_ frame: SpectrumFrame, style: VisualizerStyle, date: Date, size: CGSize, calm: Bool) {
        self.calm = calm
        let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 0.05) } ?? 1 / 60
        lastDate = date
        time += dt
        frames = dt * 60
        let kicked = frame.bass > 0.55 && time - lastKick > 0.15
        if kicked { lastKick = time }

        switch style {
        case .horizon: gridRoll += dt * 2.9 * (calm ? 0.25 : 1)
        case .terrain: stepTerrain(frame, dt)
        case .rings:
            if kicked { waves.append(0) }
            waves = waves.map { $0 + 0.018 * frames }.filter { $0 < 1.3 }
        case .starfield: stepStars(frame)
        case .fountain: stepFountain(frame, size)
        case .constellation: stepNodes(frame)
        default: break
        }
    }

    private func stepTerrain(_ frame: SpectrumFrame, _ dt: Double) {
        terrainClock += dt
        guard terrainClock >= (calm ? 8 : 2) / 60 || terrain.isEmpty else { return }
        terrainClock = 0
        let half = Double(Self.terrainColumns / 2)
        // The spectrum mirrored about the middle, the bass in the centre and higher (and taller) towards the sides.
        terrain.append((0..<Self.terrainColumns).map { i in
            let off = abs(Double(i) - half) / half
            return frame.bands[Int(off * 44)] * Float(0.3 + off)
        })
        if terrain.count > Self.terrainRows { terrain.removeFirst() }
    }

    private func newStar(far: Bool) -> Star {
        Star(x: .random(in: -1...1), y: .random(in: -1...1), z: far ? 1 : .random(in: 0.05...1.05), tint: .random(in: 0...1))
    }

    private func stepStars(_ frame: SpectrumFrame) {
        if stars.isEmpty { stars = (0..<500).map { _ in newStar(far: false) } }
        let speed = starSpeed(frame) * frames
        for i in stars.indices {
            stars[i].z -= speed
            // Gone past, or out of view (projected from the centre, so off-screen once |x/z| passes about 1.25).
            if stars[i].z < 0.03 || abs(stars[i].x / stars[i].z) > 1.3 || abs(stars[i].y / stars[i].z) > 1.3 {
                stars[i] = newStar(far: true)
            }
        }
    }

    private func stepFountain(_ frame: SpectrumFrame, _ size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        // About ten tries a frame, each a random band that fires if it's loud enough.
        for _ in 0..<Int((10 * frames).rounded()) where sparks.count < 1500 {
            let band = Int.random(in: 0..<56)
            let value = Double(frame.bands[band])
            guard value >= 0.25 else { continue }
            sparks.append(Spark(x: w * (0.05 + Double(band) / 56 * 0.9), y: h, vx: Double.random(in: -0.4...0.4),
                                vy: -value.squareRoot() * h * 0.028 * Double.random(in: 0.8...1.1), band: band))
        }
        for i in sparks.indices {
            sparks[i].x += sparks[i].vx * frames
            sparks[i].y += sparks[i].vy * frames
            sparks[i].vy += h * 0.0006 * frames
        }
        sparks.removeAll { $0.y > h + 2 }
    }

    private func stepNodes(_ frame: SpectrumFrame) {
        if nodes.isEmpty {
            nodes = (0..<70).map { _ in
                Node(x: .random(in: 0...1), y: .random(in: 0...1),
                     vx: .random(in: -0.00075...0.00075), vy: .random(in: -0.00075...0.00075), band: .random(in: 0..<48))
            }
        }
        let pace = (1 + Double(energy(frame)) * 3) * frames
        for i in nodes.indices {
            nodes[i].x = (nodes[i].x + nodes[i].vx * pace + 1).truncatingRemainder(dividingBy: 1)
            nodes[i].y = (nodes[i].y + nodes[i].vy * pace + 1).truncatingRemainder(dividingBy: 1)
        }
    }

    /// How far the stars come towards you per frame: faster when louder, a quarter as fast under Reduce Motion.
    private func starSpeed(_ frame: SpectrumFrame) -> Double {
        (0.003 + Double(energy(frame)) * 0.02 + Double(frame.bass) * 0.02) * (calm ? 0.25 : 1)
    }

    private func energy(_ frame: SpectrumFrame) -> Float {
        frame.bands.isEmpty ? 0 : frame.bands.reduce(0, +) / Float(frame.bands.count)
    }

    // MARK: Drawing

    func draw(_ frame: SpectrumFrame, style: VisualizerStyle, colours: SceneColours, in context: inout GraphicsContext, size: CGSize) {
        switch style {
        case .horizon: drawHorizon(frame, colours, &context, size)
        case .terrain: drawTerrain(colours, &context, size)
        case .rings: drawRings(frame, colours, &context, size)
        case .starfield: drawStars(frame, colours, &context, size)
        case .fountain: drawFountain(colours, &context, size)
        case .constellation: drawConstellation(frame, colours, &context, size)
        case .bars: drawDotMatrix(frame, colours, &context, size)
        default: break
        }
    }

    private func fill(_ context: inout GraphicsContext, _ size: CGSize, _ color: Color) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
    }

    private func sky(_ context: inout GraphicsContext, top: Color, bottom: Color, to y: CGFloat, width: CGFloat) {
        context.fill(Path(CGRect(x: 0, y: 0, width: width, height: y)),
                     with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: y)))
    }

    private func disc(_ centre: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Spectrum bars as a skyline under a setting sun, on a grid rolling towards you.
    private func drawHorizon(_ frame: SpectrumFrame, _ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, horizon = h * 0.58
        fill(&context, size, .black)
        sky(&context, top: c.deep.color, bottom: .black, to: h * 0.6, width: w)
        var sun = Path()
        sun.addArc(center: CGPoint(x: w / 2, y: horizon), radius: h * 0.22, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        // A soft sun behind the skyline: drawn solid in the light colour it outshone the bars on dark covers.
        context.fill(sun, with: .linearGradient(Gradient(colors: [c.light.color.opacity(0.4), c.accent.color.opacity(0.15)]),
                                                startPoint: CGPoint(x: 0, y: horizon - h * 0.22), endPoint: CGPoint(x: 0, y: horizon)))
        let count = 48, barWidth = w / CGFloat(count)
        var bars = Path()
        for i in 0..<count {
            let v = CGFloat(frame.bands[Int(abs(Double(i - count / 2)) / Double(count / 2) * 50)])
            bars.addRect(CGRect(x: CGFloat(i) * barWidth + 1, y: horizon - v * h * 0.35, width: barWidth - 2, height: v * h * 0.35))
        }
        context.fill(bars, with: .color(c.accent.color.opacity(0.75)))
        context.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)), with: .color(.black))
        var grid = Path()
        for k in 0..<14 {
            let z = (Double(k) + gridRoll.truncatingRemainder(dividingBy: 1)) / 14
            let y = horizon + CGFloat(z * z) * (h - horizon)
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y))
        }
        for k in -12...12 {
            grid.move(to: CGPoint(x: w / 2 + CGFloat(k) * 8, y: horizon))
            grid.addLine(to: CGPoint(x: w / 2 + CGFloat(k) * w * 0.12, y: h))
        }
        context.stroke(grid, with: .color(c.accent.color.opacity(0.7)), lineWidth: 1)
    }

    /// The spectrum on a grid of round LEDs, the top lit dot of each column in the light colour, like hi-fi gear.
    private func drawDotMatrix(_ frame: SpectrumFrame, _ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        fill(&context, size, Color(white: 0.02))
        let columns = 32, rows = 16
        let cw = size.width / CGFloat(columns), ch = size.height / CGFloat(rows), radius = min(cw, ch) * 0.32
        // One path per row (lit dots fade towards the bottom), one for the unlit dots and one for the peaks.
        var lit = [Path](repeating: Path(), count: rows), unlit = Path(), peaks = Path()
        for column in 0..<columns {
            // The lower three quarters of the spectrum: the top bands rarely light anything.
            let level = Int((CGFloat(frame.bands[Int(Double(column) * 1.5)]) * CGFloat(rows)).rounded())
            for row in 0..<rows {
                let dot = disc(CGPoint(x: CGFloat(column) * cw + cw / 2, y: CGFloat(row) * ch + ch / 2), radius)
                let height = rows - row
                if height == level { peaks.addPath(dot) } else if height < level { lit[row].addPath(dot) } else { unlit.addPath(dot) }
            }
        }
        context.fill(unlit, with: .color(.white.opacity(0.05)))
        for (row, path) in lit.enumerated() {
            context.fill(path, with: .color(c.accent.color.opacity(0.55 + (1 - Double(row) / Double(rows)) * 0.45)))
        }
        context.fill(peaks, with: .color(c.light.color))
    }

    /// A wireframe landscape rolling towards you, each new row of hills the current spectrum.
    private func drawTerrain(_ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, horizon = h * 0.38
        let columns = Self.terrainColumns, depth = Self.terrainRows, half = CGFloat(columns / 2)
        fill(&context, size, .black)
        sky(&context, top: .black, bottom: c.deep.color, to: horizon, width: w)
        var sun = Path()
        sun.addArc(center: CGPoint(x: w / 2, y: horizon), radius: h * 0.16, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        context.fill(sun, with: .color(c.light.color.opacity(0.8)))
        func point(_ k: Int, _ i: Int, _ v: Float) -> CGPoint {
            let z = CGFloat(k + 1) / CGFloat(depth), spread = w * (0.12 + z * 1.1)
            return CGPoint(x: w / 2 + (CGFloat(i) - half) / half * spread / 2, y: horizon + z * z * (h - horizon) - CGFloat(v) * h * 0.25 * z)
        }
        let offset = depth - terrain.count
        for (k, row) in terrain.enumerated() {
            let kk = k + offset, alpha = 0.15 + Double(kk) / Double(depth) * 0.85
            var line = Path()
            for (i, v) in row.enumerated() {
                i == 0 ? line.move(to: point(kk, i, v)) : line.addLine(to: point(kk, i, v))
            }
            context.stroke(line, with: .color(c.accent.color.opacity(alpha)), lineWidth: 1)
            guard k > 0 else { continue }
            var ribs = Path()
            for i in stride(from: 0, to: columns, by: 2) {
                ribs.move(to: point(kk - 1, i, terrain[k - 1][i])); ribs.addLine(to: point(kk, i, row[i]))
            }
            context.stroke(ribs, with: .color(c.accent.color.opacity(alpha * 0.6)), lineWidth: 1)
        }
    }

    /// One ring per frequency, bass in the middle; each kick sends a wave out that bends them as it passes.
    private func drawRings(_ frame: SpectrumFrame, _ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        fill(&context, size, c.deep.color)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2), radius = min(size.width, size.height) * 0.47
        let count = 36
        for i in 0..<count {
            let v = Double(frame.bands[Int(Double(i) * 1.6)]), base = 0.06 + Double(i) / Double(count) * 0.94
            let push = waves.reduce(0) { $0 + (calm ? 0.025 : 0.05) * exp(-pow((base - $1) * 9, 2)) * (1.3 - $1) }
            let colour = i < count / 2 ? c.accent : c.light
            context.stroke(disc(centre, radius * CGFloat(base + push)), with: .color(colour.color.opacity(0.15 + v * 0.85)),
                           lineWidth: 0.6 + v * 4)
        }
    }

    /// Flying through stars; faster when louder, stretched into streaks on the kick.
    private func drawStars(_ frame: SpectrumFrame, _ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        fill(&context, size, Color(white: 0.01))
        let w = size.width, h = size.height, focal = w * 0.4
        let speed = starSpeed(frame)
        let trail = speed * (calm ? 2 : 2 + Double(frame.bass) * 10)
        // Batched by colour and distance (near stars brighter and thicker): six paths rather than 500 strokes.
        var paths = [[Path]](repeating: [Path(), Path(), Path()], count: 2)
        for star in stars {
            let near = star.z < 0.35 ? 0 : star.z < 0.7 ? 1 : 2
            let tail = min(1, star.z + trail)
            let head = CGPoint(x: w / 2 + star.x / star.z * focal, y: h / 2 + star.y / star.z * focal)
            paths[star.tint > 0.8 ? 1 : 0][near].move(to: CGPoint(x: w / 2 + star.x / tail * focal, y: h / 2 + star.y / tail * focal))
            paths[star.tint > 0.8 ? 1 : 0][near].addLine(to: head)
        }
        for (tint, colour) in [c.accent, c.light].enumerated() {
            for (near, (width, alpha)) in [(1.8, 1.0), (1.2, 0.75), (0.7, 0.4)].enumerated() {
                context.stroke(paths[tint][near], with: .color(colour.color.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    /// Each frequency a jet along the bottom, bass on the left: sparks rise as high as the band is loud.
    private func drawFountain(_ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        fill(&context, size, Color(white: 0.01))
        var groups = [Path(), Path(), Path()]
        for spark in sparks {
            let group = spark.band < 18 ? 0 : spark.band < 38 ? 1 : 2
            groups[group].move(to: CGPoint(x: spark.x - spark.vx * 2, y: spark.y - spark.vy * 2))
            groups[group].addLine(to: CGPoint(x: spark.x, y: spark.y))
        }
        for (path, colour) in zip(groups, [c.accent.color, c.light.color.opacity(0.8), c.light.color.opacity(0.5)]) {
            context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    /// Drifting stars joined when close; the bass widens their reach, so the web knits together on the kick.
    private func drawConstellation(_ frame: SpectrumFrame, _ c: SceneColours, _ context: inout GraphicsContext, _ size: CGSize) {
        fill(&context, size, Color(white: 0.01))
        let w = size.width, h = size.height, reach = w * (0.08 + CGFloat(frame.bass) * 0.14)
        // Lines batched into four strengths by how close the pair is.
        var links = [Path](repeating: Path(), count: 4)
        for a in nodes.indices {
            for b in nodes.indices where b > a {
                let p = CGPoint(x: nodes[a].x * w, y: nodes[a].y * h), q = CGPoint(x: nodes[b].x * w, y: nodes[b].y * h)
                let d = hypot(p.x - q.x, p.y - q.y)
                guard d < reach else { continue }
                let bucket = min(3, Int((1 - d / reach) * 4))
                links[bucket].move(to: p); links[bucket].addLine(to: q)
            }
        }
        for (bucket, path) in links.enumerated() {
            context.stroke(path, with: .color(c.accent.color.opacity(0.7 * (Double(bucket) + 0.5) / 4)), lineWidth: 1)
        }
        for node in nodes {
            let v = CGFloat(frame.bands[node.band])
            context.fill(disc(CGPoint(x: node.x * w, y: node.y * h), 1.5 + v * 3.5), with: .color(c.light.color.opacity(0.5 + Double(v) * 0.5)))
        }
    }
}
