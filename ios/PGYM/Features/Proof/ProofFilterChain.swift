import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import Foundation

/// The four photo filters as Core Image chains (pgym-proof-card-spec.md, "Filters"). Applied to the
/// photo only, at output size, so the grain is the same size on every card.
enum ProofFilterChain {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIColor {
        CIColor(red: r, green: g, blue: b, alpha: 1, colorSpace: sRGB)!
    }

    /// Ink and Plate for the Plate duotone.
    static let ink = color(0.043, 0.043, 0.047)
    static let plate = color(1.0, 0.302, 0.122)

    /// Applies `filter` to an image whose extent starts at the origin.
    /// - Parameter grain: Iron's grain; the D8 thumbnails skip it below 200 px wide.
    static func apply(_ filter: ProofFilter, to image: CIImage, grain: Bool = true) -> CIImage {
        let extent = image.extent
        switch filter {
        case .raw:
            return image
        case .iron:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = 0
            controls.contrast = 1.25
            controls.brightness = -0.02
            guard let mono = controls.outputImage else { return image }
            guard grain, extent.width >= 200 else { return mono.cropped(to: extent) }
            return addGrain(to: mono, extent: extent)
        case .chalk:
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            matrix.rVector = CIVector(x: 1.04, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: 0.94, w: 0)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            let controls = CIFilter.colorControls()
            controls.inputImage = matrix.outputImage
            controls.saturation = 0.92
            controls.contrast = 0.88
            controls.brightness = 0.02
            let curve = CIFilter.toneCurve()
            curve.inputImage = controls.outputImage
            curve.point0 = CGPoint(x: 0, y: 0.08)
            curve.point1 = CGPoint(x: 0.25, y: 0.28)
            curve.point2 = CGPoint(x: 0.5, y: 0.52)
            curve.point3 = CGPoint(x: 0.75, y: 0.76)
            curve.point4 = CGPoint(x: 1.0, y: 0.97)
            return (curve.outputImage ?? image).cropped(to: extent)
        case .plate:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = 0
            controls.contrast = 1.15
            controls.brightness = 0
            guard let mono = controls.outputImage else { return image }
            let falseColor = CIFilter.falseColor()
            falseColor.inputImage = mono
            falseColor.color0 = ink
            falseColor.color1 = plate
            guard let duo = falseColor.outputImage else { return mono }
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = mono
            dissolve.targetImage = duo
            dissolve.time = 0.85
            return (dissolve.outputImage ?? duo).cropped(to: extent)
        }
    }

    /// Grey noise between 0.44 and 0.56, soft-light blended: mid-grey leaves a pixel unchanged, so the
    /// grain does not shift the average brightness. `CIRandomGenerator` is deterministic, so every Iron
    /// card has the same grain and renders are reproducible.
    private static func addGrain(to image: CIImage, extent: CGRect) -> CIImage {
        let noise = CIFilter.randomGenerator().outputImage?.cropped(to: CGRect(origin: .zero, size: extent.size))
        let grey = CIFilter.colorMatrix()
        grey.inputImage = noise
        grey.rVector = CIVector(x: 0, y: 0.12, z: 0, w: 0)
        grey.gVector = CIVector(x: 0, y: 0.12, z: 0, w: 0)
        grey.bVector = CIVector(x: 0, y: 0.12, z: 0, w: 0)
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.biasVector = CIVector(x: 0.44, y: 0.44, z: 0.44, w: 1)
        guard let grain = grey.outputImage?.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY)) else {
            return image.cropped(to: extent)
        }
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = grain
        blend.backgroundImage = image
        return (blend.outputImage ?? image).cropped(to: extent)
    }
}
