import XCTest
@testable import FreeShotCore

final class ActionParsingTests: XCTestCase {
    func testURLScheme() {
        let cases: [String: FreeShotAction] = [
            "freeshot://capture/fullscreen": .fullscreen, "freeshot://capture/area": .area,
            "freeshot://capture/window": .window, "freeshot://capture/allinone": .allInOne,
            "freeshot://capture/previous": .previousArea, "freeshot://capture/ocr": .ocr,
            "freeshot://capture/record": .record, "FREESHOT://capture/AREA": .area,
        ]
        for (s, a) in cases { XCTAssertEqual(FreeShotAction.from(url: URL(string: s)!), a, s) }
        for bad in ["freeshot://capture/", "freeshot://capture/nope", "freeshot://open/area",
                    "https://capture/area", "freeshot://capture/area/extra"] {
            XCTAssertNil(FreeShotAction.from(url: URL(string: bad)!), bad)
        }
        for a in FreeShotAction.allCases { XCTAssertEqual(FreeShotAction.from(url: a.url), a) }
    }

    func testCLINormalLaunchIsNil() throws {
        XCTAssertNil(try CLICommand.parse([]))
        XCTAssertNil(try CLICommand.parse(["-NSDocumentRevisionsDebugMode", "YES"]))
    }

    func testCLICapture() throws {
        XCTAssertEqual(try CLICommand.parse(["--capture", "fullscreen", "--out", "/tmp/x.png"]),
                       CLICommand(action: .fullscreen, output: URL(fileURLWithPath: "/tmp/x.png")))
        XCTAssertEqual(try CLICommand.parse(["--out", "/tmp/y.png", "--capture", "area"])?.action, .area)
        XCTAssertNil(try CLICommand.parse(["--capture", "fullscreen"])?.output)
        let tilde = try CLICommand.parse(["--capture", "fullscreen", "--out", "~/a.png"])?.output
        XCTAssertEqual(tilde?.path, NSHomeDirectory() + "/a.png")
    }

    func testCLIErrors() {
        XCTAssertThrowsError(try CLICommand.parse(["--capture"])) {
            XCTAssertEqual($0 as? CLICommand.ParseError, .missingValue("--capture"))
        }
        XCTAssertThrowsError(try CLICommand.parse(["--capture", "bogus"])) {
            XCTAssertEqual($0 as? CLICommand.ParseError, .unknownAction("bogus"))
        }
        XCTAssertThrowsError(try CLICommand.parse(["--capture", "fullscreen", "--zap"])) {
            XCTAssertEqual($0 as? CLICommand.ParseError, .unknownFlag("--zap"))
        }
        XCTAssertThrowsError(try CLICommand.parse(["--capture", "fullscreen", "--out"]))
    }
}
