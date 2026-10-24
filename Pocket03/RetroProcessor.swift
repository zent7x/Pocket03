import CoreImage
import UIKit

// Original treatments informed by artifact evidence, not recovered proprietary formulas.
enum Film: String, CaseIterable, Codable, Identifiable {
    case dreamy = "Dreamy (original)"
    case nokia2630 = "Nokia 2630 (2007)"
    case siemensCX70 = "Siemens CX70 (2004)"
    // Keep prior persisted identifiers readable; only cameraLooks appear in the selector.
    case daydream = "DAYDREAM", dusk = "AFTER HOURS", candy = "CANDY CCD", mono = "MONO 01"
    static let cameraLooks: [Film] = [.dreamy, .nokia2630, .siemensCX70]
    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .dreamy, .daydream: return "Soft highlights · warm color · 0.3 MP"
        case .nokia2630: return "Cool shadows · sensor grain · 2007"
        case .siemensCX70: return "Bold color · soft detail · 2004"
        case .dusk: return "Blue shadows. Last light."
        case .candy: return "Sun-faded, slightly electric."
        case .mono: return "Less color. More feeling."
        }
    }
    var treatment: Treatment {
        switch self {
        // Soft, hazy and warm. Highlights bloom out; detail is gentle rather than noisy.
        case .dreamy, .daydream:
            return Treatment(softness: 1.9, saturation: 0.82, contrast: 0.94, brightness: 0.055,
                             tint: CIVector(x: 0.055, y: 0.018, z: -0.035, w: 0),
                             bloom: 0.55, levels: 18, grain: 0.28, blackPoint: 0.03,
                             banding: 0.03, vignette: 0.45, highlightRoll: 0.35)
        // Cool green cast, crushed blacks and the coarse sensor noise these were known for.
        case .nokia2630, .dusk:
            return Treatment(softness: 1.5, saturation: 0.72, contrast: 1.38, brightness: -0.065,
                             tint: CIVector(x: -0.045, y: 0.022, z: 0.05, w: 0),
                             bloom: 0.08, levels: 11, grain: 0.80, blackPoint: 0.14,
                             banding: 0.10, vignette: 0.68, highlightRoll: 0.08)
        // The softest and most posterised: loud colour, very little real detail left.
        case .siemensCX70, .candy:
            return Treatment(softness: 2.7, saturation: 1.5, contrast: 1.16, brightness: 0.02,
                             tint: CIVector(x: 0.06, y: -0.025, z: 0.04, w: 0),
                             bloom: 0.18, levels: 8, grain: 0.52, blackPoint: 0.08,
                             banding: 0.08, vignette: 0.55, highlightRoll: 0.18)
        case .mono:
            return Treatment(softness: 1.8, saturation: 0, contrast: 1.25, brightness: 0.0,
                             tint: CIVector(x: 0.02, y: 0.02, z: 0.02, w: 0),
                             bloom: 0.12, levels: 14, grain: 0.6, blackPoint: 0.10,
                             banding: 0.06, vignette: 0.6, highlightRoll: 0.15)
        }
    }
}

struct Treatment {
    let softness: Double      // resolution thrown away before being scaled back up
    let saturation: Double
    let contrast: Double
    let brightness: Double
    let tint: CIVector
    let bloom: Double
    let levels: Double        // posterisation steps
    let grain: Double
    let blackPoint: Double    // where the shadows get crushed to pure black
    let banding: Double
    let vignette: Double
    let highlightRoll: Double // how readily highlights blow out
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo = "Photo", video = "Video", imported = "Import"
    var id: String { rawValue }
}

final class RetroProcessor {
    let context = CIContext(options: [.cacheIntermediates: false])
    let size = CGSize(width: 480, height: 640)

    func process(_ image: CIImage, film: Film, strength: Double) -> CGImage? {
        guard image.extent.width > 0, image.extent.height > 0 else { return nil }
        let amount = min(1, max(0, strength))
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = CGRect(x: scaled.extent.midX - size.width / 2,
                          y: scaled.extent.midY - size.height / 2, width: size.width, height: size.height)
        let base = scaled.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let rect = CGRect(origin: .zero, size: size)
        var output = base
        let treatment = film.treatment

        // 1. Throw resolution away, then scale back up. This is what actually reads as an old
        //    sensor: detail does not come back, and everything downstream works on the mush.
        if treatment.softness > 1 {
            let f = 1.0 / treatment.softness
            output = output.transformed(by: CGAffineTransform(scaleX: f, y: f))
                .transformed(by: CGAffineTransform(scaleX: treatment.softness, y: treatment.softness))
                .cropped(to: rect)
        }

        // 2. Colour grade.
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: treatment.saturation, kCIInputContrastKey: treatment.contrast,
            kCIInputBrightnessKey: treatment.brightness
        ])
        output = output.applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": treatment.tint])

        // 3. Crush the blacks and let the highlights go. Small sensors clipped at both ends
        //    and never recovered either.
        let knee = 1.0 - treatment.highlightRoll * 0.45
        let bp = treatment.blackPoint
        output = output.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: bp, y: 0),
            "inputPoint1": CIVector(x: bp + (0.25 * (1 - bp)), y: 0.21),
            "inputPoint2": CIVector(x: bp + (0.5 * (1 - bp)), y: 0.52),
            "inputPoint3": CIVector(x: knee, y: 0.94),
            "inputPoint4": CIVector(x: 1, y: 1)
        ])

        output = output.applyingFilter("CIBloom", parameters: [
            kCIInputRadiusKey: 6.5, kCIInputIntensityKey: treatment.bloom]).cropped(to: rect)
        output = output.applyingFilter("CIColorPosterize", parameters: ["inputLevels": treatment.levels])

        // 4. Noise, overlay blended. Mid grey is neutral under overlay, so grain adds texture
        //    without lifting the blacks into fog the way a straight dissolve does.
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let mono = random.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]).cropped(to: rect)
            let grained = mono.applyingFilter("CIOverlayBlendMode", parameters: [
                kCIInputBackgroundImageKey: output]).cropped(to: rect)
            output = output.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: grained, kCIInputTimeKey: treatment.grain
            ]).cropped(to: rect)
            let rows = mono.transformed(by: CGAffineTransform(scaleX: 520, y: 1)).cropped(to: rect)
            let banded = rows.applyingFilter("CIOverlayBlendMode", parameters: [
                kCIInputBackgroundImageKey: output]).cropped(to: rect)
            output = output.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: banded, kCIInputTimeKey: treatment.banding
            ]).cropped(to: rect)
        }

        output = output.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: treatment.vignette * 1.6, kCIInputRadiusKey: 150])
        output = output.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: base, kCIInputTimeKey: 1 - amount]).cropped(to: rect)
        return context.createCGImage(output, from: rect)
    }

    static func oriented(_ image: UIImage) -> CIImage? {
        guard let cg = image.cgImage else { return CIImage(image: image) }
        let orientations: [UIImage.Orientation: Int32] = [.up: 1, .down: 3, .left: 8, .right: 6,
            .upMirrored: 2, .downMirrored: 4, .leftMirrored: 5, .rightMirrored: 7]
        return CIImage(cgImage: cg).oriented(forExifOrientation: orientations[image.imageOrientation] ?? 1)
    }

    static func demoScene() -> CIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 640))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(red: 0.36, green: 0.59, blue: 0.65, alpha: 1).cgColor,
                          UIColor(red: 0.95, green: 0.70, blue: 0.49, alpha: 1).cgColor] as CFArray
            c.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!, start: .zero, end: CGPoint(x: 0, y: 510), options: [])
            c.setFillColor(UIColor(red: 1, green: 0.86, blue: 0.54, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: 315, y: 180, width: 72, height: 72))
            for i in 0..<4 {
                c.setFillColor(UIColor(red: 0.16 + Double(i) * 0.025, green: 0.32 + Double(i) * 0.025, blue: 0.30, alpha: 1).cgColor)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: -40, y: 400 + i * 38))
                path.addCurve(to: CGPoint(x: 520, y: 380 + i * 35), controlPoint1: CGPoint(x: 160, y: 180 + i * 45), controlPoint2: CGPoint(x: 330, y: 540 + i * 10))
                path.addLine(to: CGPoint(x: 520, y: 640)); path.addLine(to: CGPoint(x: -40, y: 640)); path.close(); path.fill()
            }
            c.setStrokeColor(UIColor(red: 0.83, green: 0.72, blue: 0.54, alpha: 1).cgColor)
            c.setLineWidth(11)
            c.move(to: CGPoint(x: 270, y: 640)); c.addCurve(to: CGPoint(x: 180, y: 390), control1: CGPoint(x: 430, y: 540), control2: CGPoint(x: 90, y: 470)); c.strokePath()
        }
        return CIImage(cgImage: image.cgImage!)
    }
}
