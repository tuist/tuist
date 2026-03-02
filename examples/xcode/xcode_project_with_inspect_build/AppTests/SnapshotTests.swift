import SnapshotTesting
import SwiftUI
import XCTest
@testable import App

final class SnapshotTests: XCTestCase {
    func testContentViewSnapshot() {
        let vc = UIHostingController(rootView: ContentView())
        assertSnapshot(of: vc, as: .image(on: .iPhone13))
    }
}
