//
//  Dependency.swift
//  
//
//  Created by Facundo Menzella on 27/09/2020.
//

import Foundation

public struct Dependency: Codable, Equatable {

    let name: String
    let requirement: Dependency.Requirement

    public init(name: String, requirement: Dependency.Requirement) {
        self.name = name
        self.requirement = requirement
    }

    public static func carthage(name: String, requirement: Dependency.Requirement) -> Dependency {
        Dependency(name: name, requirement: requirement)
    }

    public static func == (lhs: Dependency, rhs: Dependency) -> Bool {
        lhs.name == rhs.name && lhs.requirement == rhs.requirement
    }
}

public struct Dependencies: Codable, Equatable {
    private let dependencies: [Dependency]

    public init(_ dependencies: [Dependency]) {
        self.dependencies = dependencies
        dumpIfNeeded(self)
    }
}


