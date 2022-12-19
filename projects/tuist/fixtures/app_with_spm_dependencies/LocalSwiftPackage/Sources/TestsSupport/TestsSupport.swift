//
//  TestsSupport.swift
//
import Foundation
import XCTest
import SnapshotTesting

public extension XCTestCase {
    /// Inverse of XCTFail()
    func XCTPass() {
        XCTAssert(true)
    }
    
    func testJson(_ json: String, record: Bool) {
        assertSnapshot(matching: json, as: .json, record: record)
    }
    
    func testView(_ view: UIView,  record: Bool) {
        assertSnapshot(matching: view, as: .image, record: record)
    }
}
