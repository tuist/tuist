//
//  assertCodableEqualToJson.swift
//  ProjectDescriptionTests
//
//  Created by Topic, Zdenek on 25/07/2018.
//

import Foundation
import XCTest

func assertCodableEqualToJson<C: Codable>(_ subject: C, _ json: String) {
    let decoded = try! JSONDecoder().decode(C.self, from: json.data(using: .utf8)!)
    let encoder = JSONEncoder()
    let jsonData = try! encoder.encode(decoded)
    let subjectData = try! encoder.encode(subject)
    
    XCTAssert(jsonData == subjectData, "JSON does not match the encoded \(String(describing: subject))")
}
