import AppKit
import FreeShotCore

/// Headless mode: `FreeShot --capture fullscreen [--out <path>]`. Captures and exits.
/// Never registers hotkeys and never starts the app run loop.
enum CLIRunner {
    enum Exit: Int32 {
        case ok = 0
        case failure = 1
        case noPermission = 2
        case usage = 64
    }

    static func run(_ cmd: CLICommand) -> Never {
        guard cmd.action == .fullscreen else {
            fail(.usage, "only '--capture fullscreen' runs headless; use freeshot://capture/\(cmd.action.rawValue) for the rest")
        }
        // Do not prompt from the CLI: the TCC prompt would name the parent process.
        // A run from a shell checks the terminal's grant, not FreeShot's (TCC holds the parent
        // responsible). scripts/verify-capture.sh launches through LaunchServices to test FreeShot's own grant.
        guard CGPreflightScreenCaptureAccess() else {
            fail(.noPermission, "Screen Recording permission is not granted. Grant it to FreeShot in System Settings > Privacy & Security.")
        }
        // A window-server connection for ScreenCaptureKit; no run loop, no Dock icon.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        // AppKit screen data is read here, on the main thread; the task gets plain values.
        guard let screen = DisplayCapture.screenUnderMouse(), let displayID = DisplayCapture.displayID(of: screen) else {
            fail(.failure, "capture failed: no screen under the mouse")
        }
        let frame = screen.frame, scale = screen.backingScaleFactor

        Task.detached {
            do {
                let shot = try await DisplayCapture.capture(displayID: displayID, cocoaFrame: frame, scale: scale)
                let url = cmd.output ?? FilenameGenerator().uniqueURL(
                    in: AppSettings.shared.saveFolder, kind: .screenshot(scale: shot.scale), date: Date())
                try ImageExport.writePNG(shot.image, to: url, scale: shot.scale)
                print(url.path)
                exit(Exit.ok.rawValue)
            } catch {
                fail(.failure, "capture failed: \(error)")
            }
        }
        dispatchMain()
    }

    static func fail(_ code: Exit, _ message: String) -> Never {
        FileHandle.standardError.write("FreeShot: \(message)\n".data(using: .utf8)!)
        exit(code.rawValue)
    }
}
