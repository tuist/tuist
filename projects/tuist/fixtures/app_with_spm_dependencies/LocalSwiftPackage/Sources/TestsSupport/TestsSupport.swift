//
//  TestsSupport.swift
//
import Foundation
import XCTest

public extension XCTestCase {
    /// Inverse of XCTFail()
    func XCTPass() {
        XCTAssert(true)
    }
    
    func getSomething() -> String {
        "Something"
    }
}
