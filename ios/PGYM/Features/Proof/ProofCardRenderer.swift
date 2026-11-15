import CoreGraphics
import CoreImage
import CoreText
import DesignSystem
import Foundation

/// Renders the proof card: a pure function from (photo, session summary, options) to an image, so it
/// can be snapshot-tested with a bundled photo (pgym-proof-card-spec.md, "Render pipeline").
///
/// The photo goes through Core Image (aspect fill, filter, sRGB); the overlays are drawn with Core
/// Graphics and Core Text at exact pixel coordinates and baselines. One layout builds both sizes:
/// every overlay is placed at its 4:5 coordinate plus `size.yOffset`. Thread-safe; call it off the
/// main thread.
enum ProofCardRenderer {
    enum RenderError: Error, Equatable {
        case photo
        case context
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let ciContext = CIContext(options: [
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .cacheIntermediates: false,
    ])

    /// - Parameter photo: an upright photo (the camera's orientation already applied).
    static func render(photo: CGImage, summary: ProofCardSummary, options: ProofCardOptions) throws -> CGImage {
        let size = options.size.pixelSize
        let filtered = try filteredPhoto(photo, filter: options.filter, size: size)
        let width = Int(size.width)
        let height = Int(size.height)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw RenderError.context }
        ctx.interpolationQuality = .high

        // 1. Photo, drawn before the flip so it stays upright.
        ctx.draw(filtered, in: CGRect(origin: .zero, size: size))

        // From here on: origin top left, y down, like the spec and the SVG templates.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity

        let layout = Layout(size: options.size)
        drawScrim(ctx, layout: layout)
        drawWordmark(ctx, layout: layout)
        drawStamp(ctx, layout: layout, stamp: summary.stamp)
        drawLowerBlock(ctx, layout: layout, summary: summary, stats: options.stats.row)

        guard let image = ctx.makeImage() else { throw RenderError.context }
        return image
    }

    /// Steps 1 to 4: aspect fill with Lanczos, centred crop, the filter at output size, sRGB.
    static func filteredPhoto(_ photo: CGImage, filter: ProofFilter, size: CGSize, grain: Bool = true) throws -> CGImage {
        let input = CIImage(cgImage: photo)
        let w = input.extent.width
        let h = input.extent.height
        guard w > 0, h > 0 else { throw RenderError.photo }
        let scale = max(size.width / w, size.height / h)
        let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
            kCIInputImageKey: input,
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])
        guard let scaled = lanczos?.outputImage else { throw RenderError.photo }
        let crop = CGRect(
            x: scaled.extent.minX + ((scaled.extent.width - size.width) / 2).rounded(.down),
            y: scaled.extent.minY + ((scaled.extent.height - size.height) / 2).rounded(.down),
            width: size.width,
            height: size.height
        )
        // Clamp first so the Lanczos edge falloff never shows as a soft border.
        let fitted = scaled.clampedToExtent()
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .cropped(to: CGRect(origin: .zero, size: size))
        let output = ProofFilterChain.apply(filter, to: fitted, grain: grain)
        guard let cg = ciContext.createCGImage(output, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: sRGB) else {
            throw RenderError.photo
        }
        return cg
    }

    // MARK: Layout

    /// The 4:5 coordinates from the spec, moved down by the size's offset.
    struct Layout {
        let size: ProofCardSize
        var height: CGFloat { size.pixelSize.height }
        var dy: CGFloat { size.yOffset }

        func y(_ feedY: CGFloat) -> CGFloat { feedY + dy }
    }

    private enum Palette {
        static let ink = cg(ColorToken.ink.hex)
        static let chalk = cg(ColorToken.chalk.hex)
        static let plate = cg(ColorToken.plate.hex)
        static let steel = cg(ColorToken.steel.hex)
        /// `ash` #6B6B73: the pending stamp's outline (a graphic, 3.72:1 on Ink).
        static let ash = cg(0x6B6B73)
        static let scrim = cg(ColorToken.ink.hex, alpha: ProofCardSpec.scrimOpacity)

        static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
            CGColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
    }

    // MARK: Drawing

    private static func drawScrim(_ ctx: CGContext, layout: Layout) {
        let top = layout.size.scrimTop
        ctx.setFillColor(Palette.scrim)
        ctx.fill(CGRect(x: 0, y: top, width: 1080, height: layout.height - top))
    }

    private static func drawWordmark(_ ctx: CGContext, layout: Layout) {
        ctx.setFillColor(Palette.ink)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 48, y: layout.y(48), width: 156, height: 68), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        ctx.saveGState()
        ctx.translateBy(x: 64.8, y: layout.y(62))
        ctx.scaleBy(x: 0.2, y: 0.2)
        ctx.setFillColor(Palette.chalk)
        ctx.addPath(ProofCardArt.wordmark)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    private static func drawStamp(_ ctx: CGContext, layout: Layout, stamp: ProofStampState) {
        let pending = stamp.isPending
        let ink = pending ? Palette.steel : Palette.plate
        let outline = pending ? Palette.ash : Palette.plate
        ctx.saveGState()
        if !pending {
            // 4 degrees anticlockwise about the box centre. In this y-down space a negative angle turns
            // anticlockwise on screen, the same as SVG `rotate(-4)`.
            let centre = CGPoint(x: 882, y: layout.y(118))
            ctx.translateBy(x: centre.x, y: centre.y)
            ctx.rotate(by: -CGFloat(Rotation.proofCardStamp) * .pi / 180)
            ctx.translateBy(x: -centre.x, y: -centre.y)
        }
        // Outer edge 732,48 300 x 140: the 4 px stroke sits inside it.
        let box = CGPath(roundedRect: CGRect(x: 734, y: layout.y(50), width: 296, height: 136), cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(box)
        ctx.setFillColor(Palette.ink)
        ctx.fillPath()
        ctx.addPath(box)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(4)
        ctx.strokePath()

        ctx.saveGState()
        ctx.translateBy(x: 792, y: layout.y(118))
        ctx.scaleBy(x: 0.11, y: 0.11)
        ctx.setStrokeColor(ink)
        ctx.setLineCap(.butt)
        ctx.setLineWidth(88)
        ctx.addPath(ProofCardArt.markRing)
        ctx.strokePath()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(96)
        ctx.addPath(ProofCardArt.markCheck)
        ctx.strokePath()
        ctx.restoreGState()

        let column: CGFloat = 164
        draw(ctx, ProofTextRun(text: "PROOF", font: ProofCardFont.mono(18), tracking: 1.5), at: CGPoint(x: 852, y: layout.y(86)), color: ink)
        let number = ProofCardText.proofNumber(stamp)
        let numberSize = ProofCardText.stampNumberSize(number, maxWidth: column)
        draw(ctx, ProofTextRun(text: number, font: ProofCardFont.anton(numberSize)), at: CGPoint(x: 852, y: layout.y(146)), color: ink)
        let streakFont = ProofCardFont.mono(14)
        let streak = ProofCardText.truncate(ProofCardText.streakLine(stamp), font: streakFont, maxWidth: column, tracking: 1)
        draw(ctx, ProofTextRun(text: streak, font: streakFont, tracking: 1), at: CGPoint(x: 852, y: layout.y(170)), color: ink)
        ctx.restoreGState()
    }

    private static func drawLowerBlock(_ ctx: CGContext, layout: Layout, summary: ProofCardSummary, stats: [ProofCardStat]) {
        let fit = ProofCardText.fitSessionName(summary.sessionName)
        let width = ProofCardText.lowerBlockWidth

        let stampFont = ProofCardFont.mono(28)
        let time = ProofCardText.truncate(ProofCardText.timestamp(summary.stamp, timezone: summary.timezone), font: stampFont, maxWidth: width, tracking: 2)
        draw(ctx, ProofTextRun(text: time, font: stampFont, tracking: 2), at: CGPoint(x: 64, y: layout.y(fit.timestampBaseline)), color: Palette.chalk)

        let nameFont = ProofCardFont.anton(fit.step.size)
        for (line, baseline) in zip(fit.lines, fit.baselines) {
            draw(ctx, ProofTextRun(text: line, font: nameFont), at: CGPoint(x: 64, y: layout.y(baseline)), color: Palette.chalk)
        }

        let columns: [CGFloat] = [64, 392, 720]
        let labelFont = ProofCardFont.mono(ProofCardText.labelSize)
        for (stat, x) in zip(stats, columns) {
            let cell = ProofCardText.statCell(stat, summary: summary)
            let value = ProofCardText.fitStatValue(cell)
            let valueRun = ProofTextRun(text: value.value, font: ProofCardFont.mono(value.size))
            draw(ctx, valueRun, at: CGPoint(x: x, y: layout.y(1208)), color: Palette.chalk)
            if let unit = cell.unit {
                let unitRun = ProofTextRun(text: unit, font: ProofCardFont.mono(ProofCardText.unitSize), tracking: ProofCardText.unitTracking)
                draw(ctx, unitRun, at: CGPoint(x: x + valueRun.width + ProofCardText.unitGap, y: layout.y(1208)), color: Palette.chalk)
            }
            let label = ProofCardText.truncate(cell.label, font: labelFont, maxWidth: ProofCardText.statColumnWidth, tracking: ProofCardText.labelTracking)
            draw(ctx, ProofTextRun(text: label, font: labelFont, tracking: ProofCardText.labelTracking), at: CGPoint(x: x, y: layout.y(1278)), color: Palette.chalk)
        }

        ctx.setFillColor(Palette.chalk)
        ctx.fill(CGRect(x: 64, y: layout.y(1232), width: width, height: 3))
    }

    /// Draws a run with its baseline at `point` in the y-down context.
    private static func draw(_ ctx: CGContext, _ run: ProofTextRun, at point: CGPoint, color: CGColor) {
        guard !run.text.isEmpty else { return }
        let line = run.line(color: color)
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
