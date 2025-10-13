import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol CIControlling {
    /// Detects CI environment and returns CI information
    func ciInfo() -> CIInfo?
}

public struct CIController: CIControlling {
    public init() {}

    public func ciInfo() -> CIInfo? {
        let env = Environment.current.variables

        // GitHub Actions
        if env["GITHUB_ACTIONS"] != nil {
            return CIInfo(
                provider: .github,
                runId: env["GITHUB_RUN_ID"],
                projectHandle: env["GITHUB_REPOSITORY"]
            )
        }

        // GitLab CI
        if env["GITLAB_CI"] != nil {
            return CIInfo(
                provider: .gitlab,
                runId: env["CI_PIPELINE_ID"],
                projectHandle: env["CI_PROJECT_PATH"],
                host: env["CI_SERVER_HOST"]
            )
        }

        // Bitrise
        if env["BITRISE_IO"] != nil {
            return CIInfo(
                provider: .bitrise,
                runId: env["BITRISE_BUILD_SLUG"],
                projectHandle: env["BITRISE_APP_SLUG"]
            )
        }

        // CircleCI
        if env["CIRCLECI"] != nil {
            let projectHandle: String? = if let username = env["CIRCLE_PROJECT_USERNAME"],
                                            let reponame = env["CIRCLE_PROJECT_REPONAME"]
            {
                "\(username)/\(reponame)"
            } else {
                nil
            }
            return CIInfo(
                provider: .circleci,
                runId: env["CIRCLE_BUILD_NUM"],
                projectHandle: projectHandle
            )
        }

        // Buildkite
        if env["BUILDKITE"] != nil {
            let projectHandle: String? = if let orgSlug = env["BUILDKITE_ORGANIZATION_SLUG"],
                                            let pipelineSlug = env["BUILDKITE_PIPELINE_SLUG"]
            {
                "\(orgSlug)/\(pipelineSlug)"
            } else {
                nil
            }
            return CIInfo(
                provider: .buildkite,
                runId: env["BUILDKITE_BUILD_NUMBER"],
                projectHandle: projectHandle
            )
        }

        // Codemagic
        if env["CM_BUILD_ID"] != nil {
            return CIInfo(
                provider: .codemagic,
                runId: env["CM_BUILD_ID"],
                projectHandle: env["CM_PROJECT_ID"]
            )
        }

        return nil
    }
}
