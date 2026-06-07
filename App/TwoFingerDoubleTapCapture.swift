import SwiftUI
import UIKit

struct TwoFingerDoubleTapCapture: UIViewRepresentable {
    var onDetected: () -> Void

    /// Not `private`: `UIViewRepresentable` needs `makeUIView` / `updateUIView` to use at least
    /// `internal` types; a `private` nested class forces those methods to be `private`, which
    /// does not match the protocol’s requirements.
    final class MuteGestureHostView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            backgroundColor = .clear
            isMultipleTouchEnabled = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// Single-finger drags/scrolls go to the `ScrollView` behind; we only claim hits when
        /// a multi-touch sequence is in progress (2-finger double-tap).
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let touches = event?.allTouches, touches.count >= 2 else { return false }
            return bounds.contains(point)
        }
    }

    func makeUIView(context: Context) -> MuteGestureHostView {
        let view = MuteGestureHostView()
        let g = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle))
        g.numberOfTapsRequired = 2
        g.numberOfTouchesRequired = 2
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        g.delegate = context.coordinator
        view.addGestureRecognizer(g)
        return view
    }

    func updateUIView(_: MuteGestureHostView, context: Context) {
        context.coordinator.onDetected = onDetected
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDetected: onDetected)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDetected: () -> Void
        init(onDetected: @escaping () -> Void) {
            self.onDetected = onDetected
        }

        @objc func handle() {
            onDetected()
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
