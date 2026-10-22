import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var cornerRadius: CGFloat = 18

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.layer?.cornerRadius = cornerRadius
    }
}

extension View {
    func macGlassSurface(cornerRadius: CGFloat = 18) -> some View {
        self.background(
            ZStack {
                VisualEffectBackground(
                    material: .hudWindow,
                    blendingMode: .behindWindow,
                    state: .active,
                    cornerRadius: cornerRadius
                )
                // Frosted glass refractive highlight
                Color.white.opacity(0.05)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 30, x: 0, y: 14)
    }
}
