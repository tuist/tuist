//
//  TestsSupport.swift
//
import Foundation
import SnapshotTesting
import XCTest

extension XCTestCase {
    /// Inverse of XCTFail()
    public func XCTPass() {
        XCTAssert(true)
    }

    public func testJson(_ json: String, record: Bool) {
        assertSnapshot(matching: json, as: .json, record: record)
    }

    public func testView(_ view: UIView, record: Bool) {
        assertSnapshot(matching: view, as: .image, record: record)
    }
}
