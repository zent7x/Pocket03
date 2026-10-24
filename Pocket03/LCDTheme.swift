import SwiftUI

// Pocket03's own screen language: a warm amber dot-matrix panel rather than a Series 40 pastiche.
// Everything here is original -- palette, glyph set and panel treatment.
enum LCD {
    static let shell = Color(red: 0.055, green: 0.047, blue: 0.039)
    static let panel = Color(red: 0.094, green: 0.082, blue: 0.067)
    static let panelLift = Color(red: 0.133, green: 0.115, blue: 0.091)
    static let ink = Color(red: 1.0, green: 0.702, blue: 0.263)
    static let inkBright = Color(red: 1.0, green: 0.851, blue: 0.588)
    static let inkDim = Color(red: 1.0, green: 0.702, blue: 0.263).opacity(0.55)
    static let inkFaint = Color(red: 1.0, green: 0.702, blue: 0.263).opacity(0.26)
    static let alert = Color(red: 1.0, green: 0.38, blue: 0.29)
    static let live = Color(red: 0.54, green: 0.93, blue: 0.56)

    static func type(_ size: CGFloat) -> Font { .custom("VT323-Regular", size: size) }
}

// Horizontal raster lines. Kept subtle: it should read as a panel, not as a filter.
struct Scanlines: View {
    var spacing: CGFloat = 3
    var opacity: Double = 0.26
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(opacity)))
                y += spacing
            }
        }
        .allowsHitTesting(true == false)
        .accessibilityHidden(true)
    }
}

extension View {
    func scanlined(_ opacity: Double = 0.26) -> some View {
        overlay(Scanlines(opacity: opacity))
    }
}

// An original dot-matrix glyph set, authored as pixel rows so it stays crisp at any size and
// owes nothing to any handset maker's iconography.
enum PixelIcon {
    case camera, video, importTray, sliders, gear, grid, bolt, chevron, check, play, still, arrowLeft, arrowRight

    var rows: [String] {
        switch self {
        case .camera: return [
            "...XXX...",
            "XXXXXXXXX",
            "X.......X",
            "X..XXX..X",
            "X.XX.XX.X",
            "X..XXX..X",
            "XXXXXXXXX"]
        case .video: return [
            ".........",
            "XXXXXX...",
            "X....X.X.",
            "X....XXXX",
            "X....XXXX",
            "X....X.X.",
            "XXXXXX..."]
        case .importTray: return [
            "...XX....",
            "...XX....",
            "...XX....",
            "XXXXXXX..",
            ".XXXXX...",
            "..XXX....",
            "...X....."]
        case .sliders: return [
            "..X......",
            "XXXXXXXXX",
            "..X......",
            ".........",
            "......X..",
            "XXXXXXXXX",
            "......X.."]
        case .gear: return [
            "..X.X.X..",
            ".XXXXXXX.",
            "XXX...XXX",
            "XX.....XX",
            "XXX...XXX",
            ".XXXXXXX.",
            "..X.X.X.."]
        case .grid: return [
            "XXXX.XXXX",
            "XXXX.XXXX",
            "XXXX.XXXX",
            ".........",
            "XXXX.XXXX",
            "XXXX.XXXX",
            "XXXX.XXXX"]
        case .bolt: return [
            "....XXX..",
            "...XXX...",
            "..XXX....",
            ".XXXXXX..",
            "....XXX..",
            "...XXX...",
            "..XXX...."]
        case .chevron: return [
            ".XX......",
            "..XX.....",
            "...XX....",
            "....XX...",
            "...XX....",
            "..XX.....",
            ".XX......"]
        case .check: return [
            ".......XX",
            "......XX.",
            ".X...XX..",
            ".XX.XX...",
            "..XXX....",
            "...X.....",
            "........."]
        case .play: return [
            "XX.......",
            "XXXX.....",
            "XXXXXX...",
            "XXXXXXXX.",
            "XXXXXX...",
            "XXXX.....",
            "XX......."]
        case .still: return [
            "XXXXXXXXX",
            "X.......X",
            "X..XXX..X",
            "X.XXXXX.X",
            "X..XXX..X",
            "X.......X",
            "XXXXXXXXX"]
        case .arrowLeft: return [
            "....X....",
            "...XX....",
            "..XXXXXXX",
            ".XXXXXXXX",
            "..XXXXXXX",
            "...XX....",
            "....X...."]
        case .arrowRight: return [
            "....X....",
            "....XX...",
            "XXXXXXX..",
            "XXXXXXXX.",
            "XXXXXXX..",
            "....XX...",
            "....X...."]
        }
    }
}

struct PixelGlyph: View {
    let icon: PixelIcon
    var tint: Color = LCD.ink

    var body: some View {
        Canvas { context, size in
            let rows = icon.rows
            guard let columns = rows.first?.count, columns > 0, !rows.isEmpty else { return }
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows.count))
            let originX = (size.width - cell * CGFloat(columns)) / 2
            let originY = (size.height - cell * CGFloat(rows.count)) / 2
            for (r, row) in rows.enumerated() {
                for (c, value) in row.enumerated() where value == "X" {
                    let rect = CGRect(x: originX + CGFloat(c) * cell, y: originY + CGFloat(r) * cell,
                                      width: cell, height: cell)
                    context.fill(Path(rect.insetBy(dx: cell * 0.04, dy: cell * 0.04)), with: .color(tint))
                }
            }
        }
        .aspectRatio(CGFloat(icon.rows.first?.count ?? 9) / CGFloat(max(1, icon.rows.count)), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// Segmented battery and signal meters, drawn rather than borrowed.
struct LCDMeter: View {
    enum Kind { case battery, signal }
    let kind: Kind
    var level: Int = 4

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .signal:
                let bars = 4
                let gap = size.width * 0.12 / CGFloat(bars)
                let barWidth = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                for i in 0..<bars {
                    let fraction = CGFloat(i + 1) / CGFloat(bars)
                    let barHeight = size.height * (0.32 + 0.68 * fraction)
                    let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: size.height - barHeight,
                                      width: barWidth, height: barHeight)
                    context.fill(Path(rect), with: .color(i < level ? LCD.ink : LCD.inkFaint))
                }
            case .battery:
                let capWidth = size.width * 0.09
                let bodyRect = CGRect(x: 0, y: 0, width: size.width - capWidth - 1, height: size.height)
                context.stroke(Path(bodyRect), with: .color(LCD.ink), lineWidth: 1)
                context.fill(Path(CGRect(x: bodyRect.maxX + 1, y: size.height * 0.28,
                                         width: capWidth, height: size.height * 0.44)),
                             with: .color(LCD.ink))
                let cells = 4
                let pad = max(1.0, size.height * 0.16)
                let inner = bodyRect.insetBy(dx: pad, dy: pad)
                let cellGap = inner.width * 0.08 / CGFloat(cells)
                let cellWidth = (inner.width - cellGap * CGFloat(cells - 1)) / CGFloat(cells)
                for i in 0..<cells where i < level {
                    context.fill(Path(CGRect(x: inner.minX + CGFloat(i) * (cellWidth + cellGap),
                                             y: inner.minY, width: cellWidth, height: inner.height)),
                                 with: .color(LCD.ink))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
