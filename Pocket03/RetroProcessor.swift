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
        case .dreamy, .daydream: return Treatment(saturation: 0.8, contrast: 1.08, brightness: 0.018, tint: CIVector(x: 0.028, y: 0.012, z: -0.014, w: 0), blur: 0.65, bloom: 0.18, levels: 24, grain: 0.045, banding: 0.018, pixelScale: 1)
        case .nokia2630: return Treatment(saturation: 0.96, contrast: 1.19, brightness: -0.015, tint: CIVector(x: -0.012, y: 0.008, z: 0.028, w: 0), blur: 0.48, bloom: 0.07, levels: 20, grain: 0.085, banding: 0.03, pixelScale: 1)
        case .siemensCX70: return Treatment(saturation: 1.3, contrast: 1.14, brightness: 0.01, tint: CIVector(x: 0.025, y: 0.018, z: -0.025, w: 0), blur: 0.9, bloom: 0.1, levels: 16, grain: 0.055, banding: 0.024, pixelScale: 1.8)
        case .dusk: return Treatment(saturation: 0.8, contrast: 1.18, brightness: -0.045, tint: CIVector(x: -0.012, y: 0.005, z: 0.045, w: 0), blur: 0.65, bloom: 0.09, levels: 24, grain: 0.045, banding: 0.018, pixelScale: 1)
        case .candy: return Treatment(saturation: 1.35, contrast: 1.08, brightness: 0.018, tint: CIVector(x: 0.035, y: -0.01, z: 0.025, w: 0), blur: 0.65, bloom: 0.09, levels: 24, grain: 0.045, banding: 0.018, pixelScale: 1)
        case .mono: return Treatment(saturation: 0, contrast: 1.08, brightness: 0.018, tint: CIVector(x: 0.018, y: 0.023, z: 0.012, w: 0), blur: 0.65, bloom: 0.09, levels: 32, grain: 0.045, banding: 0.018, pixelScale: 1)
        }
    }
}

struct Treatment {
    let saturation: Double
    let contrast: Double
    let brightness: Double
    let tint: CIVector
    let blur: Double
    let bloom: Double
    let levels: Double
    let grain: Double
    let banding: Double
    let pixelScale: Double
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
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: treatment.saturation, kCIInputContrastKey: treatment.contrast,
            kCIInputBrightnessKey: treatment.brightness
        ])
        output = output.applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": treatment.tint])
        output = output.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: treatment.blur]).cropped(to: rect)
        // Original coefficients, informed by the artifact's halation pass names.
        output = output.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 5.5, kCIInputIntensityKey: treatment.bloom]).cropped(to: rect)
        if treatment.pixelScale > 1 {
            output = output.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: treatment.pixelScale, kCIInputCenterKey: CIVector(x: 240, y: 320)])
        }
        output = output.applyingFilter("CIColorPosterize", parameters: ["inputLevels": treatment.levels])
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            // Force an opaque, bounded noise image before blending. CIRandomGenerator's
            // random alpha must not be unpremultiplied into highlight spikes.
            let monochrome = random.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            output = output.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: monochrome.cropped(to: rect), kCIInputTimeKey: treatment.grain
            ])
            let banding = monochrome.transformed(by: CGAffineTransform(scaleX: 480, y: 1)).cropped(to: rect)
            output = output.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: banding, kCIInputTimeKey: treatment.banding
            ])
        }
        output = output.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.4, kCIInputRadiusKey: 180])
        output = output.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: base, kCIInputTimeKey: 1 - amount]).cropped(to: rect)
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
