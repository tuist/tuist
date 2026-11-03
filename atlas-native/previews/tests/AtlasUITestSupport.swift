import XCTest

@MainActor
extension XCUIApplication {
    private var contentBounds: CGRect {
        let top = navigationBars.firstMatch.frame.maxY
        var bottom = frame.maxY
        for control in [tabBars.firstMatch, buttons["Save connection"],
                        staticTexts["thread-presence"], buttons["thread-model"], buttons["thread-attach"],
                        textFields["thread-composer"], keyboards.firstMatch] where control.exists && control.isHittable {
            if control.frame.minY > top { bottom = min(bottom, control.frame.minY) }
        }
        return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
    }

    func scrollContent(up: Bool = true, distance: CGFloat? = nil) {
        let bounds = contentBounds
        let displacement = min(max(distance ?? bounds.height * 0.6, 24), bounds.height * 0.6) * (up ? 1 : -1)
        let origin = coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.width / 2, dy: bounds.midY + displacement / 2))
        let end = origin.withOffset(CGVector(dx: frame.width / 2, dy: bounds.midY - displacement / 2))
        if distance == nil {
            start.press(forDuration: 0.05, thenDragTo: end)
        } else {
            // Stop precise drags before lifting so inertia cannot fling past a small viewport.
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
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
            if let target {
                let top = target.frame.height <= bounds.height ? target.frame.minY : target.frame.midY
                let bottom = target.frame.height <= bounds.height ? target.frame.maxY : target.frame.midY
                let delta = bottom > bounds.maxY ? bottom - bounds.maxY + 16 : top - bounds.minY - 16
                scrollContent(up: delta > 0, distance: abs(delta))
            } else {
                scrollContent(up: up)
            }
        }
        let frames = descendants(matching: type).matching(identifier: id).allElementsBoundByIndex.map { $0.frame }
        return try XCTUnwrap(nil as XCUIElement?, "Missing visible control: \(id), bounds: \(contentBounds), frames: \(frames)")
    }
}
