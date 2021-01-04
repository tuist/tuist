//
//  File.swift
//
//
//  Created by Kassem Wridan on 22/12/2020.
//

import Foundation
import TSCBasic
import TuistCore

public extension LibraryMetadata {
    static func test(
        path: AbsolutePath = "/Libraries/libTest/libTest.a",
        publicHeaders: AbsolutePath = "/Libraries/libTest/include",
        swiftModuleMap: AbsolutePath? = "/Libraries/libTest/libTest.swiftmodule",
        architectures: [BinaryArchitecture] = [.arm64],
        linking: BinaryLinking = .static
    ) -> LibraryMetadata {
        LibraryMetadata(
            path: path,
            publicHeaders: publicHeaders,
            swiftModuleMap: swiftModuleMap,
            architectures: architectures,
            linking: linking
        )
    }
}
