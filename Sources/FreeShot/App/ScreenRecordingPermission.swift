import AppKit
import ScreenCaptureKit

/// The Screen Recording grant: the check, the alert and the System Settings pane.
/// Captures call `explainFailure(_:)` when they fail, so a missing grant is never silent.
enum ScreenRecordingPermission {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private static var alertShowing = false

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func openSettings() { NSWorkspace.shared.open(settingsURL) }

    /// True when the error is ScreenCaptureKit's "user declined" error.
    static func isUserDeclined(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    /// Call after a capture fails. When the grant is missing it shows the alert and returns true.
    @discardableResult
    static func explainFailure(_ error: Error? = nil) -> Bool {
        guard !isGranted || isUserDeclined(error) else { return false }
        DispatchQueue.main.async { showAlert() }
        return true
    }

    /// The alert with a button that opens the pane. Never two at once.
    static func showAlert() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !alertShowing else { return }
        alertShowing = true
        defer { alertShowing = false }
        let alert = NSAlert()
        alert.messageText = "FreeShot needs Screen Recording permission"
        alert.informativeText = """
        Open System Settings > Privacy & Security > Screen & System Audio Recording. \
        Turn on FreeShot, then quit and reopen FreeShot. \
        If FreeShot is on already, turn it off and on again, then reopen FreeShot.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit FreeShot")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: openSettings()
        case .alertSecondButtonReturn: NSApp.terminate(nil)
        default: break
        }
    }
}
