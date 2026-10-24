import SwiftUI
import UIKit

// Original handset illustrations, drawn at runtime rather than bundled. They evoke the shape
// language of each era -- slim candybar, chunky squared shell -- without copying the original
// app's artwork or reproducing any manufacturer's logo or trademark.
struct PhoneGlyph: View {
    let film: Film
    var lit = true

    // A real photograph is used where one is available under a free licence; the remaining looks
    // fall back to the drawn handset below. See docs/credits.md.
    private static let photographed: [Film: String] = [.nokia2630: "nokia2630", .dusk: "nokia2630"]

    var body: some View {
        if let asset = PhoneGlyph.photographed[film], UIImage(named: asset) != nil {
            Image(asset).resizable().scaledToFit()
                .aspectRatio(0.52, contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            drawn
        }
    }

    private var drawn: some View {
        Canvas { context, size in
            let spec = PhoneGlyph.spec(for: film)
            let w = size.width, h = size.height
            let shellWidth = w * spec.width
            let shell = CGRect(x: (w - shellWidth) / 2, y: 0, width: shellWidth, height: h)
            let stroke = max(0.7, w * 0.05)

            let body = Path(roundedRect: shell, cornerRadius: w * spec.corner)
            context.fill(body, with: .color(spec.shell))
            context.stroke(body, with: .color(spec.edge), lineWidth: stroke)

            // Earpiece slit.
            let earWidth = shellWidth * 0.34
            context.fill(Path(roundedRect: CGRect(x: shell.midX - earWidth / 2, y: h * 0.045,
                                                  width: earWidth, height: max(1, h * 0.018)),
                              cornerRadius: h * 0.01), with: .color(spec.edge.opacity(0.75)))

            // Screen.
            let inset = shellWidth * 0.13
            let screen = CGRect(x: shell.minX + inset, y: h * spec.screenTop,
                                width: shellWidth - inset * 2, height: h * (spec.screenBottom - spec.screenTop))
            let screenPath = Path(roundedRect: screen, cornerRadius: w * 0.04)
            context.fill(screenPath, with: .color(lit ? spec.screen : spec.screen.opacity(0.45)))
            context.stroke(screenPath, with: .color(spec.edge.opacity(0.6)), lineWidth: stroke * 0.7)

            // Navigation cluster.
            let navHeight = h * 0.085
            let navWidth = shellWidth * 0.46
            let nav = CGRect(x: shell.midX - navWidth / 2, y: h * (spec.screenBottom + 0.045),
                             width: navWidth, height: navHeight)
            context.fill(Path(roundedRect: nav, cornerRadius: spec.navRounded ? navHeight / 2 : w * 0.03),
                         with: .color(spec.key))

            // Keypad: three columns per row.
            let padTop = nav.maxY + h * 0.045
            let padBottom = h * 0.945
            guard spec.keyRows > 0, padBottom > padTop else { return }
            let rowStride = (padBottom - padTop) / CGFloat(spec.keyRows)
            let keyHeight = min(rowStride * 0.62, h * 0.055)
            let keyWidth = shellWidth * 0.2
            let gap = (shellWidth - inset * 2 - keyWidth * 3) / 2
            for row in 0..<spec.keyRows {
                for column in 0..<3 {
                    let x = shell.minX + inset + CGFloat(column) * (keyWidth + gap)
                    let y = padTop + CGFloat(row) * rowStride
                    context.fill(Path(roundedRect: CGRect(x: x, y: y, width: keyWidth, height: keyHeight),
                                      cornerRadius: keyHeight / 2), with: .color(spec.key))
                }
            }
        }
        .aspectRatio(0.52, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private struct Spec {
        let width: CGFloat
        let corner: CGFloat
        let shell: Color
        let edge: Color
        let screen: Color
        let key: Color
        let screenTop: CGFloat
        let screenBottom: CGFloat
        let navRounded: Bool
        let keyRows: Int
    }

    private static func spec(for film: Film) -> Spec {
        switch film {
        case .nokia2630, .dusk:
            // Slim 2007 candybar: narrow shell, dark shade, tall screen, rounded navigation bar.
            return Spec(width: 0.74, corner: 0.17,
                        shell: Color(red: 0.18, green: 0.20, blue: 0.24),
                        edge: Color(red: 0.07, green: 0.09, blue: 0.12),
                        screen: Color(red: 0.62, green: 0.78, blue: 0.84),
                        key: Color(red: 0.60, green: 0.64, blue: 0.69),
                        screenTop: 0.11, screenBottom: 0.40, navRounded: true, keyRows: 4)
        case .siemensCX70, .candy:
            // Chunkier 2004 shell: squarer corners, lighter casing, squared navigation pad.
            return Spec(width: 0.92, corner: 0.11,
                        shell: Color(red: 0.70, green: 0.72, blue: 0.74),
                        edge: Color(red: 0.26, green: 0.28, blue: 0.31),
                        screen: Color(red: 0.69, green: 0.82, blue: 0.70),
                        key: Color(red: 0.36, green: 0.38, blue: 0.42),
                        screenTop: 0.13, screenBottom: 0.42, navRounded: false, keyRows: 4)
        default:
            // Pocket03's own handset: softer, rounder, warmer. Not a model that ever shipped.
            return Spec(width: 0.84, corner: 0.30,
                        shell: Color(red: 0.95, green: 0.91, blue: 0.84),
                        edge: Color(red: 0.42, green: 0.40, blue: 0.38),
                        screen: Color(red: 0.76, green: 0.86, blue: 0.83),
                        key: Color(red: 0.55, green: 0.56, blue: 0.58),
                        screenTop: 0.12, screenBottom: 0.44, navRounded: true, keyRows: 3)
        }
    }
}
