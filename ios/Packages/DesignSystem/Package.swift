// swift-tools-version:5.9
// PGYM design system: colour, type, spacing and radius tokens, the bundled fonts,
// and the shared components. Source of truth for the values: pgym-design-style.md.
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [
                // Copied as a folder so the TTFs keep their names and the OFL texts ship next to them.
                .copy("Resources/Fonts"),
            ]
        ),
        // Tests for this module live in the app's PGYMTests target, so
        // `xcodebuild -scheme PGYM test` runs them on the simulator.
    ]
)
