import Foundation
import UIKit

/// A stand-in for the camera hardware, for the UI test that walks sign-in to a stamped proof (card I9).
/// The simulator has no camera, so with the launch argument `-pgym-ui-test-camera` D7 skips the
/// permission prompt and the shutter returns a picture drawn here in code.
///
/// This is not a photo import: nothing is read from the library or the disk, and the whole type is
/// compiled only into Debug builds. A Release or archive build has no way to turn it on, so the rule
/// UI tests use a synthetic photo; production accepts a camera capture or a user-selected library photo.
enum UITestCamera {
    static let argument = "-pgym-ui-test-camera"

    static var isOn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(argument)
        #else
        false
        #endif
    }

    /// A 3:4 synthetic scene as JPEG data, like the camera's file data: a warm wall, a dark floor and
    /// a loaded bar. No person and no real photo.
    static func photoData() -> Data? {
        #if DEBUG
        let size = CGSize(width: 1536, height: 2048)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(red: 0.77, green: 0.63, blue: 0.50, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: size.height * 0.74, width: size.width, height: size.height * 0.26))
            UIColor(white: 0.82, alpha: 1).setFill()
            cg.fill(CGRect(x: 80, y: size.height * 0.45, width: size.width - 160, height: 28))
            for (index, color) in [UIColor.systemRed, .systemBlue, .systemYellow].enumerated() {
                let height = CGFloat(300 - index * 60)
                for side: CGFloat in [-1, 1] {
                    let x = size.width / 2 + side * (460 + CGFloat(index) * 68) - 28
                    color.setFill()
                    cg.fill(CGRect(x: x, y: size.height * 0.45 + 14 - height, width: 56, height: height * 2))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
    }
}
