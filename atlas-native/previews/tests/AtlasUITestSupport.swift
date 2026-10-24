import XCTest

@MainActor
extension XCUIApplication {
    private var contentBounds: CGRect {
        let top = navigationBars.firstMatch.frame.maxY
        var bottom = frame.maxY
        for control in [tabBars.firstMatch, buttons["Save connection"], buttons["orbit-private"],
                        staticTexts["thread-presence"], buttons["thread-address-agent"], buttons["thread-attach"],
                        textFields["thread-composer"], keyboards.firstMatch] where control.exists {
            if control.frame.minY > top { bottom = min(bottom, control.frame.minY) }
        }
        return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
    }

    func scrollContent(up: Bool = true) {
        let bounds = contentBounds
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: bounds.minY + bounds.height * (up ? 0.8 : 0.2)))
        let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: bounds.minY + bounds.height * (up ? 0.2 : 0.8)))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func visibleElement(_ id: String, type: XCUIElement.ElementType = .any, up: Bool = true) throws -> XCUIElement {
        for _ in 0..<8 {
            let elements = descendants(matching: type).matching(identifier: id).allElementsBoundByIndex
            let bounds = contentBounds
            // Native accessibility can mark offscreen children as hittable.
            if let element = elements.first(where: {
                $0.isHittable && ($0.frame.height <= bounds.height
                    ? bounds.contains($0.frame)
                    : bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)))
            }) { return element }
            let target = elements.first { $0.frame.height > 0 }
            scrollContent(up: target.map { $0.frame.maxY > bounds.maxY } ?? up)
        }
        return try XCTUnwrap(nil as XCUIElement?, "Missing visible control: \(id)")
    }
}
