import Foundation
import xpmcore

protocol TargetLinting: AnyObject {
    func lint(target: Target) -> [LintingIssue]
}

class TargetLinter: TargetLinting {

    // MARK: - TargetLinting

    func lint(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintHasSourceFiles(target: target))
        issues.append(contentsOf: lintOneSourcesPhase(target: target))
        issues.append(contentsOf: lintOneHeadersPhase(target: target))
        issues.append(contentsOf: lintOneResourcesPhase(target: target))
        issues.append(contentsOf: lintCopiedFiles(target: target))
        return issues
    }

    // MARK: - Fileprivate

    fileprivate func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let files = target.buildPhases.compactMap({ $0 as? SourcesBuildPhase })
            .flatMap({ $0.buildFiles })
            .flatMap({ $0.paths })
        var issues: [LintingIssue] = []
        if files.count == 0 {
            issues.append(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning))
        }
        return issues
    }

    fileprivate func lintOneSourcesPhase(target: Target) -> [LintingIssue] {
        let sourcesPhases = target.buildPhases
            .filter({ $0 is SourcesBuildPhase })
            .count
        if sourcesPhases <= 1 { return [] }
        return [LintingIssue(reason: "The target \(target.name) has more than one sources build phase.", severity: .error)]
    }

    fileprivate func lintOneHeadersPhase(target: Target) -> [LintingIssue] {
        let headerPhases = target.buildPhases
            .filter({ $0 is HeadersBuildPhase })
            .count
        if headerPhases <= 1 { return [] }
        return [LintingIssue(reason: "The target \(target.name) has more than one headers build phase.", severity: .error)]
    }

    fileprivate func lintOneResourcesPhase(target: Target) -> [LintingIssue] {
        let resourcesPhase = target.buildPhases
            .filter({ $0 is ResourcesBuildPhase })
            .count
        if resourcesPhase <= 1 { return [] }
        return [LintingIssue(reason: "The target \(target.name) has more than one resources build phase.", severity: .error)]
    }

    fileprivate func lintCopiedFiles(target: Target) -> [LintingIssue] {
        guard let resourcesPhase = target.buildPhases.compactMap({ $0 as? ResourcesBuildPhase }).first else {
            return []
        }

        var issues: [LintingIssue] = []

        let buildFiles = resourcesPhase.buildFiles.compactMap({ $0 as? ResourcesBuildFile }).flatMap({ $0.paths })
        let infoPlists = buildFiles.filter({ $0.asString.contains("Info.plist") })
        let entitlements = buildFiles.filter({ $0.asString.contains(".entitlements") })

        issues.append(contentsOf: infoPlists.map({ LintingIssue(reason: "Info.plist at path \($0.asString) being copied into the target \(target.name) product.", severity: .warning) }))
        issues.append(contentsOf: entitlements.map({ LintingIssue(reason: "Entitlements file at path \($0.asString) being copied into the target \(target.name) product.", severity: .warning) }))

        return issues
    }
}
