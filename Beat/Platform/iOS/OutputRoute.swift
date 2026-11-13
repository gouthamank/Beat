import AVFoundation
import AVKit
import Observation
import UIKit

/// Beat's one output (AirPlay) picker on iPad and iPhone, lent to whichever now-playing bar is in front, as on
/// the Mac (where a picker per bar dropped the route). On iOS the picker routes the app's audio session, and
/// whether Beat is playing to AirPlay is read from the session's current route.
@MainActor
@Observable
final class OutputRoute {
    /// Playing to an AirPlay speaker: Beat's volume slider steps aside, as on the Mac.
    private(set) var isExternal = false
    /// Keyboard focus on the picker; only the Mac draws a ring for it.
    let hasFocus = false

    @ObservationIgnored let picker = AVRoutePickerView()
    @ObservationIgnored private var hosts: [Host] = []
    @ObservationIgnored private var routeChanges: NSObjectProtocol?

    private struct Host {
        weak var view: UIView?
    }

    init(player: AVPlayer) {
        picker.tintColor = .secondaryLabel
        picker.activeTintColor = .tintColor
        picker.prioritizesVideoDevices = false
        checkAirPlay()
        routeChanges = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAirPlay() }
        }
    }

    private func checkAirPlay() {
        let airPlay = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        if airPlay != isExternal { isExternal = airPlay }
    }

    /// A bar appeared: it becomes the front host and shows the picker.
    func register(_ host: UIView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        hosts.append(Host(view: host))
        attach(to: host)
    }

    /// A bar went away: the picker goes back to the bar that was in front before it.
    func unregister(_ host: UIView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        guard picker.superview === host || picker.superview == nil, let previous = hosts.last?.view else { return }
        attach(to: previous)
    }

    private func attach(to host: UIView) {
        guard picker.superview !== host else { return }
        picker.removeFromSuperview()
        picker.frame = host.bounds
        picker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(picker)
    }
}
