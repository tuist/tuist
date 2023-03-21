import Foundation
import TuistGraph

extension CarthageController {
    enum CarthageArguments: String, CaseIterable {
        /// Don't use downloaded binaries when possible
        case noUseBinaries = "--no-use-binaries"

        /// Use authentication credentials from ~/.netrc file when downloading binary only frameworks.
        case useNetRC = "--use-netrc"

        /// Use cached builds when possible
        case cacheBuilds = "--cache-builds"

        /// Use the new resolver codeline when calculating dependencies.
        case newResolver = "--new-resolver"
    }
}

extension CarthageController.CarthageArguments {
    static func map(fromFlagOptions flags: CarthageDependencies.Options) -> [String] {
        var arguments: [CarthageController.CarthageArguments] = []

        if flags.noUseBinaries {
            arguments.append(.noUseBinaries)
        }

        if flags.useNetRC {
            arguments.append(.useNetRC)
        }

        if flags.cacheBuilds {
            arguments.append(.cacheBuilds)
        }

        if flags.newResolver {
            arguments.append(.newResolver)
        }

        return arguments.map(\.rawValue)
    }
}
