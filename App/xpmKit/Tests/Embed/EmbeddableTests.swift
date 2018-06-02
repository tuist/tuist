import Foundation
import XCTest
@testable import xpmKit

final class EmbeddableTests: XCTestCase {
    func test_embeddableType() {
        XCTAssertEqual(EmbeddableType.framework.rawValue, "FMWK")
        XCTAssertEqual(EmbeddableType.bundle.rawValue, "BNDL")
        XCTAssertEqual(EmbeddableType.dSYM.rawValue, "dSYM")
    }

    func test_constants() {
        XCTAssertEqual(Embeddable.Constants.lipoArchitecturesMessage, "Architectures in the fat file:")
        XCTAssertEqual(Embeddable.Constants.lipoNonFatFileMessage, "Non-fat file:")
    }
}
