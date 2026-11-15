import SwiftUI

/// Ink background with screen margins, fonts registered. Used by the component previews
/// and handy for any screen preview in the app.
public struct PreviewSurface<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        FontRegistry.registerAll()
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            content.padding(Spacing.screenMargin)
        }
        .preferredColorScheme(.dark)
    }
}
