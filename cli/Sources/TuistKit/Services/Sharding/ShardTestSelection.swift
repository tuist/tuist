import Foundation
import TuistCore

/// Narrows sharded work by the test identifiers the run was asked to test.
///
/// Neither stage of sharding sees `--test-targets` on its own. The plan takes its universe from the
/// built `.xctestrun`, which records a test plan's selection but never a command-line
/// `-only-testing`, so a suite-level request leaves the module looking unrestricted and the server
/// resolves its suites from history. A shard then takes its identifiers from that plan, and both
/// those and the requested ones reach xcodebuild as `-only-testing`, which runs their union. The
/// requested identifiers therefore have to be intersected back in at each stage.
enum ShardTestSelection {
    /// The module universe and per-module suite restrictions a plan is created from.
    struct Plan: Equatable {
        let modules: [String]
        let parallelizableModules: [String]
        let selectedTestSuites: [String]
        let skippedTestSuites: [String]
    }

    /// Restricts what a plan may distribute to the modules and suites `requested` names.
    ///
    /// A module the request doesn't name is dropped. A module named without a suite stays
    /// unrestricted, since that is what running it whole means. A module the products already
    /// restrict keeps only the suites both sides allow, and is dropped when that leaves nothing.
    static func plan(
        modules: [String],
        parallelizableModules: [String],
        selectedTestSuites: [String],
        skippedTestSuites: [String],
        requested: [TestIdentifier]
    ) -> Plan {
        guard !requested.isEmpty else {
            return Plan(
                modules: modules,
                parallelizableModules: parallelizableModules,
                selectedTestSuites: selectedTestSuites,
                skippedTestSuites: skippedTestSuites
            )
        }

        let requestedSuitesByModule = requestedSuitesByModule(requested)
        let productSuitesByModule = Dictionary(grouping: selectedTestSuites, by: module(of:))
            .mapValues(Set.init)

        var narrowedModules: [String] = []
        var narrowedSuites: Set<String> = []

        for module in modules {
            guard let requestedSuites = requestedSuitesByModule[module] else { continue }
            let productSuites = productSuitesByModule[module] ?? []
            let suites: Set<String>
            if requestedSuites.isEmpty {
                suites = productSuites
            } else if productSuites.isEmpty {
                suites = requestedSuites
            } else {
                suites = productSuites.intersection(requestedSuites)
                if suites.isEmpty { continue }
            }
            narrowedModules.append(module)
            narrowedSuites.formUnion(suites)
        }

        let survivingModules = Set(narrowedModules)
        return Plan(
            modules: narrowedModules,
            parallelizableModules: parallelizableModules.filter { survivingModules.contains($0) },
            selectedTestSuites: narrowedSuites.sorted(),
            skippedTestSuites: skippedTestSuites.filter { survivingModules.contains(module(of: $0)) }
        )
    }

    /// The `-only-testing` identifiers a shard runs, restricted to what `requested` names.
    ///
    /// Two identifiers overlap when one is a prefix of the other, and the narrower of the two is
    /// what runs. An empty result means the shard holds nothing the run asked for.
    static func onlyTestIdentifiers(shard: [String], requested: [TestIdentifier]) -> [String] {
        let requested = requested.map(\.description)
        guard !requested.isEmpty else { return shard }
        guard !shard.isEmpty else { return requested }

        var narrowed: Set<String> = []
        for shardIdentifier in shard {
            for requestedIdentifier in requested {
                if let identifier = narrower(shardIdentifier, requestedIdentifier) {
                    narrowed.insert(identifier)
                }
            }
        }
        return narrowed.sorted()
    }

    private static func requestedSuitesByModule(_ requested: [TestIdentifier]) -> [String: Set<String>] {
        var suitesByModule: [String: Set<String>] = [:]
        var unrestrictedModules: Set<String> = []

        for identifier in requested {
            guard let suite = identifier.class else {
                unrestrictedModules.insert(identifier.target)
                continue
            }
            suitesByModule[identifier.target, default: []].insert("\(identifier.target)/\(suite)")
        }

        for module in unrestrictedModules {
            suitesByModule[module] = []
        }
        return suitesByModule
    }

    private static func narrower(_ lhs: String, _ rhs: String) -> String? {
        let lhsComponents = lhs.split(separator: "/")
        let rhsComponents = rhs.split(separator: "/")
        guard zip(lhsComponents, rhsComponents).allSatisfy({ $0 == $1 }) else { return nil }
        return lhsComponents.count >= rhsComponents.count ? lhs : rhs
    }

    private static func module(of identifier: String) -> String {
        identifier.split(separator: "/").first.map(String.init) ?? identifier
    }
}
