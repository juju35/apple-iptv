import SwiftUI

extension View {
    /// iOS: the keyboard can always be put away, on every screen. The iPhone Duo's split keyboard (and an
    /// iPad's floating one) has no hide key, and the search field's × also clears the search. So: a tap
    /// outside the text field, scrolling a list, the search key, or the button above the keyboard.
    /// Set on the tab view and on sheets with text fields: a sheet doesn't inherit toolbars.
    @ViewBuilder
    func keyboardDismissal() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.immediately)
            .onSubmit(of: .search) { KeyboardDismisser.dismiss() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: KeyboardDismisser.dismiss) {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide Keyboard")
                }
            }
            .onAppear(perform: KeyboardDismisser.installTapOutside)
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Puts the keyboard away when the user taps outside a text field: a recognizer on each window that lets
/// the tap through (buttons, rows and cards still get it) and ignores taps in text fields and the
/// search bar, which would otherwise lose the focus they just took.
@MainActor
enum KeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static let delegate = TapOutsideDelegate()

    /// Idempotent: a window gets one recognizer, whichever view asks first (sheets share their window).
    static func installTapOutside() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === delegate }) {
            let tap = UITapGestureRecognizer(target: delegate, action: #selector(TapOutsideDelegate.tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = delegate
            window.addGestureRecognizer(tap)
        }
    }

    private final class TapOutsideDelegate: NSObject, UIGestureRecognizerDelegate {
        @objc func tapped() {
            KeyboardDismisser.dismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UISearchBar { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
