//
//  DependencyRequirement.swift
//
//
//  Created by Facundo Menzella on 02/10/2020.
//

import Foundation

// The idea of Requirement comes from SPM PackageRequirement
// https://github.com/apple/swift-package-manager/blob/main/Sources/PackageDescription/PackageRequirement.swift
// This could be further extended for more cases

public extension Dependency {
    enum Requirement: Codable, Equatable {
        case exact(Version)
//        case range(Range<Version>)
//        case branch(String)

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = .exact(try container.decode(Version.self, forKey: .exact))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if case let .exact(version) = self {
                try container.encode(version, forKey: .exact)
            }
        }

        enum CodingKeys: String, CodingKey {
            case exact
        }
    }
}
