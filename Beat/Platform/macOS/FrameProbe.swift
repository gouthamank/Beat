import AppKit
import SwiftUI

/// The Mac's probe: a tiny AppKit view whose window frame `FrameProbe` reads (see HeroTransition.swift).
final class FrameProbeView: NSView {
    /// Never takes clicks; it only measures.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// AppKit's window coordinates start at the bottom left; flipped to the top-left origin shared code uses.
    func windowRect() -> CGRect? {
        guard let window, let content = window.contentView else { return nil }
        let r = convert(bounds, to: nil)
        return CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    var windowContentSize: CGSize? { window?.contentView?.bounds.size }
}

struct FrameProbeReader: NSViewRepresentable {
    let probe: FrameProbe

    func makeNSView(context: Context) -> FrameProbeView {
        let view = FrameProbeView()
        probe.view = view
        return view
    }

    func updateNSView(_ view: FrameProbeView, context: Context) {
        probe.view = view
    }
}
