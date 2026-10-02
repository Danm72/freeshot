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
        guard CGPreflightScreenCaptureAccess() else {
            fail(.noPermission, "Screen Recording permission is not granted. Grant it to FreeShot in System Settings > Privacy & Security.")
        }
        // A window-server connection for ScreenCaptureKit; no run loop, no Dock icon.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        Task.detached {
            do {
                let shot = try await DisplayCapture.captureDisplayUnderMouse()
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
