import SwiftUI

// The only place that branches on Liquid Glass availability.
// macOS 26+ and iOS (26+, its minimum): real Liquid Glass. macOS 15: materials that approximate it.

extension View {
    /// Applies a glass surface behind the view, clipped to `shape`.
    @ViewBuilder
    func beatGlass(in shape: some Shape = Capsule(), interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.regularMaterial)
                        if let tint { shape.fill(tint.opacity(0.18)) }
                    }
                }
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .background(ShapeShadow(shape: shape, opacity: 0.18, radius: 12, y: 4))
        }
    }

    @ViewBuilder
    func beatGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

/// A drop shadow cast by `shape`'s outline alone, which Core Animation draws from the path. SwiftUI's
/// `.shadow` shadows everything in the view, text included, and redrew it on every scrolled frame: on the
/// album page's track list and the now-playing bar that was the biggest cost of scrolling.
#if os(macOS)
struct ShapeShadow<S: Shape>: NSViewRepresentable {
    let shape: S
    var opacity: Float
    var radius: CGFloat
    var y: CGFloat = 0

    func makeNSView(context: Context) -> ShapeShadowView { ShapeShadowView() }

    func updateNSView(_ view: ShapeShadowView, context: Context) {
        view.path = { shape.path(in: $0).cgPath }
        // Layer coordinates run up from the bottom on the Mac, so a shadow cast downwards has a negative offset.
        view.update(opacity: opacity, radius: radius, offset: CGSize(width: 0, height: -y),
                    animated: context.transaction.animation != nil)
    }
}

final class ShapeShadowView: NSView {
    var path: ((CGRect) -> CGPath)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks go to the view the shadow is under.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.shadowPath = path?(bounds)
    }

    func update(opacity: Float, radius: CGFloat, offset: CGSize, animated: Bool) {
        guard let layer else { return }
        needsLayout = true
        ShadowLayer.update(layer, opacity: opacity, radius: radius, offset: offset, animated: animated && window != nil)
    }
}
#else
struct ShapeShadow<S: Shape>: UIViewRepresentable {
    let shape: S
    var opacity: Float
    var radius: CGFloat
    var y: CGFloat = 0

    func makeUIView(context: Context) -> ShapeShadowView { ShapeShadowView() }

    func updateUIView(_ view: ShapeShadowView, context: Context) {
        view.path = { shape.path(in: $0).cgPath }
        // UIKit layers run down from the top, so a shadow cast downwards has a positive offset.
        view.update(opacity: opacity, radius: radius, offset: CGSize(width: 0, height: y),
                    animated: context.transaction.animation != nil)
    }
}

final class ShapeShadowView: UIView {
    var path: ((CGRect) -> CGPath)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Touches go to the view the shadow is under.
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = path?(bounds)
    }

    func update(opacity: Float, radius: CGFloat, offset: CGSize, animated: Bool) {
        setNeedsLayout()
        ShadowLayer.update(layer, opacity: opacity, radius: radius, offset: offset, animated: animated && window != nil)
    }
}
#endif

/// The shadow's layer settings, shared by both platforms' views. A change made inside a SwiftUI animation (a
/// tile's hover) eases over, as `.shadow` did.
@MainActor
enum ShadowLayer {
    static func update(_ layer: CALayer, opacity: Float, radius: CGFloat, offset: CGSize, animated: Bool) {
        let current = layer.presentation() ?? layer
        if animated {
            ease(layer, "shadowOpacity", from: current.shadowOpacity, to: opacity, changed: layer.shadowOpacity != opacity)
            ease(layer, "shadowRadius", from: current.shadowRadius, to: radius, changed: layer.shadowRadius != radius)
            ease(layer, "shadowOffset", from: current.shadowOffset, to: offset, changed: layer.shadowOffset != offset)
        }
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowOffset = offset
    }

    private static func ease(_ layer: CALayer, _ key: String, from: Any, to: Any, changed: Bool) {
        guard changed else { return }
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = 0.25
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }
}

/// Groups glass views so they blend and morph together on macOS 26 and iOS 26.
struct BeatGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
