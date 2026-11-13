import SwiftUI
import UIKit

/// The iPad and iPhone probe: a tiny UIKit view whose window frame `FrameProbe` reads (see HeroTransition.swift).
final class FrameProbeView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Never takes touches; it only measures.
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// UIKit's window coordinates already have a top-left origin, as the Mac's version computes.
    func windowRect() -> CGRect? {
        guard let window else { return nil }
        return convert(bounds, to: window)
    }

    var windowContentSize: CGSize? { window?.bounds.size }
}

struct FrameProbeReader: UIViewRepresentable {
    let probe: FrameProbe

    func makeUIView(context: Context) -> FrameProbeView {
        let view = FrameProbeView()
        probe.view = view
        return view
    }

    func updateUIView(_ view: FrameProbeView, context: Context) {
        probe.view = view
    }
}
