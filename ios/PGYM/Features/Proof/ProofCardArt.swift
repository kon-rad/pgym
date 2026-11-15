import CoreGraphics
import Foundation

/// The wordmark letters and the mono mark, copied from the card templates
/// (Areas/PGYM/design/proof-card/pgym-card-4x5.svg, which take them from the D1 logo files).
/// Kept as SVG path data so a logo change is a copy and paste.
enum ProofCardArt {
    /// "PGYM" lockup letters, in lockup units (200 tall). Fill with even-odd.
    static let wordmark: CGPath = {
        let path = CGMutablePath()
        let letters: [(dx: CGFloat, d: String)] = [
            (0, "M0 0 H76 A44 44 0 0 1 120 44 V80 A44 44 0 0 1 76 124 H44 V200 H0 Z M44 34 H70 A6 6 0 0 1 76 40 V84 A6 6 0 0 1 70 90 H44 Z"),
            (148, "M44 0 H80 A44 44 0 0 1 124 44 V70 H80 V40 A6 6 0 0 0 74 34 H50 A6 6 0 0 0 44 40 V160 A6 6 0 0 0 50 166 H74 A6 6 0 0 0 80 160 V132 H62 V100 H124 V156 A44 44 0 0 1 80 200 H44 A44 44 0 0 1 0 156 V44 A44 44 0 0 1 44 0 Z"),
            (300, "M0 0 H46 L64 76 L82 0 H128 L86 116 V200 H42 V116 Z"),
            (456, "M0 0 H54 L78 104 L102 0 H156 V200 H114 V80 L94 160 H62 L42 80 V200 H0 Z"),
        ]
        for letter in letters {
            path.addPath(SVGPath.parse(letter.d), transform: CGAffineTransform(translationX: letter.dx, y: 0))
        }
        return path
    }()

    /// The mark's open ring, centred on the origin; stroke 88, butt caps.
    static let markRing: CGPath = SVGPath.parse("M291.1 -72.6 A300 300 0 1 1 102.6 -281.9")

    /// The mark's check; stroke 96, round caps and joins.
    static let markCheck: CGPath = SVGPath.parse("M-136 12 L-44 104 L245 -252.7")
}

/// The subset of SVG path syntax the logo uses: absolute M, L, H, V, Z and circular A.
enum SVGPath {
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = tokenize(d)[...]
        var current = CGPoint.zero
        var command: Character = "M"

        func number() -> CGFloat {
            guard case let .number(value)? = tokens.first else { return 0 }
            tokens.removeFirst()
            return value
        }

        while let token = tokens.first {
            if case let .command(c) = token {
                command = c
                tokens.removeFirst()
            }
            switch command {
            case "M":
                current = CGPoint(x: number(), y: number())
                path.move(to: current)
                command = "L"
            case "L":
                current = CGPoint(x: number(), y: number())
                path.addLine(to: current)
            case "H":
                current.x = number()
                path.addLine(to: current)
            case "V":
                current.y = number()
                path.addLine(to: current)
            case "A":
                let rx = number()
                _ = number() // ry: the logo's arcs are circles
                _ = number() // x-axis rotation
                let largeArc = number() != 0
                let sweep = number() != 0
                let end = CGPoint(x: number(), y: number())
                addArc(path, from: current, to: end, radius: rx, largeArc: largeArc, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                if let next = tokens.first, case .number = next { tokens.removeFirst() }
            default:
                tokens.removeFirst()
            }
        }
        return path
    }

    /// SVG endpoint arc to a centre arc (SVG 1.1 implementation notes, F.6.5), for a circle.
    static func addArc(_ path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, radius: CGFloat, largeArc: Bool, sweep: Bool) {
        guard radius > 0, p1 != p2 else {
            path.addLine(to: p2)
            return
        }
        let x1p = (p1.x - p2.x) / 2
        let y1p = (p1.y - p2.y) / 2
        var r = radius
        let lambda = (x1p * x1p + y1p * y1p) / (r * r)
        if lambda > 1 { r *= sqrt(lambda) }
        let numerator = r * r * r * r - r * r * y1p * y1p - r * r * x1p * x1p
        let denominator = r * r * y1p * y1p + r * r * x1p * x1p
        var coef = sqrt(max(0, numerator / denominator))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * y1p
        let cyp = -coef * x1p
        let centre = CGPoint(x: cxp + (p1.x + p2.x) / 2, y: cyp + (p1.y + p2.y) / 2)
        let start = atan2(p1.y - centre.y, p1.x - centre.x)
        let end = atan2(p2.y - centre.y, p2.x - centre.x)
        // SVG sweep 1 runs toward increasing angles, which Core Graphics calls not clockwise.
        path.addArc(center: centre, radius: r, startAngle: start, endAngle: end, clockwise: !sweep)
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        func flush() {
            if let value = Double(buffer) { tokens.append(.number(CGFloat(value))) }
            buffer = ""
        }
        for char in d {
            if char.isLetter {
                flush()
                tokens.append(.command(char))
            } else if char == " " || char == "," {
                flush()
            } else if char == "-" {
                flush()
                buffer.append(char)
            } else {
                buffer.append(char)
            }
        }
        flush()
        return tokens
    }
}
