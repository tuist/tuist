import XCTest

@MainActor
extension XCUIApplication {
    func scrollContent(up: Bool = true) {
        let top = navigationBars.firstMatch.frame.maxY
        var bottom = frame.maxY
        for control in [tabBars.firstMatch, buttons["Save connection"], keyboards.firstMatch] where control.exists {
            if control.frame.minY > top { bottom = min(bottom, control.frame.minY) }
        }
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: top + (bottom - top) * (up ? 0.8 : 0.2)))
        let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: top + (bottom - top) * (up ? 0.2 : 0.8)))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func visibleElement(_ id: String, type: XCUIElement.ElementType = .any, up: Bool = true) throws -> XCUIElement {
        for _ in 0..<8 {
            let elements = descendants(matching: type).matching(identifier: id).allElementsBoundByIndex
            if let element = elements.first(where: \.isHittable) { return element }
            scrollContent(up: up)
        }
        return try XCTUnwrap(nil as XCUIElement?, "Missing visible control: \(id)")
    }
}
