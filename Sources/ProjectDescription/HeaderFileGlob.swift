//
//  HeaderFileGlob.swift
//  ProjectDescription
//
//  Created by Paweł Trafimuk on 01/12/2021.
//

import Foundation

/// A type that represents a list of source files defined by a glob.
public struct HeaderFileGlob: Codable, Equatable {
    /// Glob pattern to header files
    public var glob: Path

    /// Relative glob patterns for excluded files.
    public var excluding: [Path]

    /// Initializes the header file glob.
    /// - Parameters:
    ///   - glob: Glob pattern to header files
    ///   - excluding: Glob pattern used for filtering out files.
    public init(_ glob: Path,
                excluding: [Path] = [])
    {
        self.glob = glob
        self.excluding = excluding
    }
    
    public init(_ glob: Path,
                excluding: Path?)
    {
        let paths: [Path] = excluding.flatMap { [$0] } ?? []
        self.init(glob, excluding: paths)
    }

}

extension HeaderFileGlob: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(Path(value))
    }
}
