import XCTest

final class MediaUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func test1_baseline() { run(mode: "baseline") }
    func test2_video() { run(mode: "video") }
    func test3_metal() { run(mode: "metal") }
    func test4_captureBackground() { run(mode: "capture-bg") }
    func test5_micBackground() { run(mode: "mic-bg") }
    func test6_mic() { run(mode: "mic") }
    func test7_capture() { run(mode: "capture") }

    private func run(mode: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-mode", mode]
        let start = Date()
        app.launch()
        let ready = app.buttons["Ready"]
        let appeared = ready.waitForExistence(timeout: 60)
        let elapsed = Date().timeIntervalSince(start)
        print("REPRO mode=\(mode) ready=\(appeared) after \(String(format: "%.1f", elapsed))s")
        if appeared {
            print("REPRO mode=\(mode) status:\n\(app.staticTexts["status"].label)")
            XCTAssertTrue(ready.isHittable)
            ready.tap()
            sleep(5)
            print("REPRO mode=\(mode) still responsive=\(app.staticTexts["status"].exists)")
        }
        XCTAssertTrue(appeared, "Ready button never appeared in mode \(mode)")
    }
}
