import CoreImage
import UIKit

// Original treatments informed by artifact evidence, not recovered proprietary formulas.
enum Film: String, CaseIterable, Codable, Identifiable {
    case daydream = "DAYDREAM", dusk = "AFTER HOURS", candy = "CANDY CCD", mono = "MONO 01"
    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .daydream: return "Soft light. Small memories."
        case .dusk: return "Blue shadows. Last light."
        case .candy: return "Sun-faded, slightly electric."
        case .mono: return "Less color. More feeling."
        }
    }
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
        let saturation: Double = film == .mono ? 0 : (film == .candy ? 1.35 : 0.8)
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation, kCIInputContrastKey: film == .dusk ? 1.18 : 1.08,
            kCIInputBrightnessKey: film == .dusk ? -0.045 : 0.018
        ])
        let tint: CIVector
        switch film {
        case .daydream: tint = CIVector(x: 0.028, y: 0.012, z: -0.014, w: 0)
        case .dusk: tint = CIVector(x: -0.012, y: 0.005, z: 0.045, w: 0)
        case .candy: tint = CIVector(x: 0.035, y: -0.01, z: 0.025, w: 0)
        case .mono: tint = CIVector(x: 0.018, y: 0.023, z: 0.012, w: 0)
        }
        output = output.applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": tint])
        output = output.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.65]).cropped(to: rect)
        // The analyzed artifact names separate halation extraction, blur and merge controls.
        // CIBloom provides our own highlight spread treatment.
        output = output.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 5.5, kCIInputIntensityKey: film == .daydream ? 0.18 : 0.09]).cropped(to: rect)
        output = output.applyingFilter("CIColorPosterize", parameters: ["inputLevels": film == .mono ? 32 : 24])
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            // Force an opaque, bounded noise image before blending. CIRandomGenerator's
            // random alpha must not be unpremultiplied into highlight spikes.
            let monochrome = random.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            output = output.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: monochrome.cropped(to: rect), kCIInputTimeKey: 0.045
            ])
            let banding = monochrome.transformed(by: CGAffineTransform(scaleX: 480, y: 1)).cropped(to: rect)
            output = output.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: banding, kCIInputTimeKey: 0.018
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
