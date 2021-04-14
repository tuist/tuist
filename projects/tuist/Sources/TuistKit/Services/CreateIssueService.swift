import Foundation
import TSCBasic
import TuistSupport

final class CreateIssueService {
    static let createIssueUrl: String = "https://github.com/tuist/tuist/issues/new"

    func run() throws {
        try System.shared.run("/usr/bin/open", CreateIssueService.createIssueUrl)
    }
}
