import AppKit
import FreeShotCore

// CLI mode is decided before NSApplication runs, so it never touches hotkeys.
do {
    if let cmd = try CLICommand.parse(Array(CommandLine.arguments.dropFirst())) {
        CLIRunner.run(cmd)
    }
} catch {
    CLIRunner.fail(.usage, "\(error). Usage: FreeShot --capture fullscreen [--out <path>]")
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
