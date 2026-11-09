import Foundation
import Testing
import TuistConfig
import TuistCore

struct LintingIssuePromotingWarningsTests {
    @Test func promotingWarnings_none_keepsWarnings() {
        let issues = [
            LintingIssue(reason: "warning1", severity: .warning, category: .schemeTargetNotFound),
            LintingIssue(reason: "warning2", severity: .warning, category: .duplicateProductNames),
            LintingIssue(reason: "error1", severity: .error),
        ]

        let result = issues.promotingWarnings(with: .none)

        #expect(result.filter { $0.severity == .warning }.count == 2)
        #expect(result.filter { $0.severity == .error }.count == 1)
    }

    @Test func promotingWarnings_all_promotesAllWarnings() {
        let issues = [
            LintingIssue(reason: "warning1", severity: .warning, category: .schemeTargetNotFound),
            LintingIssue(reason: "warning2", severity: .warning, category: .duplicateProductNames),
            LintingIssue(reason: "uncategorized", severity: .warning),
            LintingIssue(reason: "error1", severity: .error),
        ]

        let result = issues.promotingWarnings(with: .all)

        let errors = result.filter { $0.severity == .error }
        let warnings = result.filter { $0.severity == .warning }
        #expect(errors.count == 4)
        #expect(errors.map(\.reason).contains("warning1"))
        #expect(errors.map(\.reason).contains("warning2"))
        #expect(errors.map(\.reason).contains("uncategorized"))
        #expect(warnings.isEmpty)
    }

    @Test func promotingWarnings_only_promotesMatchingCategories() {
        let issues = [
            LintingIssue(reason: "scheme", severity: .warning, category: .schemeTargetNotFound),
            LintingIssue(reason: "config", severity: .warning, category: .mismatchedConfigurations),
            LintingIssue(reason: "static", severity: .warning, category: .staticSideEffects),
        ]

        let result = issues.promotingWarnings(with: .only([.schemeTargetNotFound, .mismatchedConfigurations]))

        #expect(result[0].severity == .error)
        #expect(result[0].reason == "scheme")
        #expect(result[1].severity == .error)
        #expect(result[1].reason == "config")
        #expect(result[2].severity == .warning)
        #expect(result[2].reason == "static")
    }

    @Test func promotingWarnings_preservesCategory() {
        let issues = [
            LintingIssue(reason: "test", severity: .warning, category: .outdatedDependencies),
        ]

        let result = issues.promotingWarnings(with: .all)

        #expect(result.first?.category == .outdatedDependencies)
        #expect(result.first?.severity == .error)
    }

    @Test func promotingWarnings_doesNotDemoteExistingErrors() {
        let issues = [
            LintingIssue(reason: "real error", severity: .error),
        ]

        let result = issues.promotingWarnings(with: .none)

        #expect(result.first?.severity == .error)
    }
}
