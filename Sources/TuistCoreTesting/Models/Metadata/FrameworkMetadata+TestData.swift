//
//  File.swift
//
//
//  Created by Kassem Wridan on 22/12/2020.
//

import Foundation
import TSCBasic
import TuistCore

public extension FrameworkMetadata {
    static func test(
        path: AbsolutePath = "/Frameworks/TestFramework.xframework",
        binaryPath: AbsolutePath = "/Frameworks/TestFramework.xframework/TestFramework",
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.arm64],
        isCarthage: Bool = false
    ) -> FrameworkMetadata {
        FrameworkMetadata(
            path: path,
            binaryPath: binaryPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            isCarthage: isCarthage
        )
    }
}
