import Foundation
import Mockable
import TuistEnvironment
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
            let shardSessionId: String? = if let runId = env["GITHUB_RUN_ID"] {
                "github-\(runId)-\(env["GITHUB_RUN_ATTEMPT"] ?? "1")"
            } else {
                nil
            }
            return CIInfo(
                provider: .github,
                runId: env["GITHUB_RUN_ID"],
                projectHandle: env["GITHUB_REPOSITORY"],
                shardSessionId: shardSessionId
            )
        }

        // GitLab CI
        if env["GITLAB_CI"] != nil {
            let shardSessionId: String? = if let pipelineId = env["CI_PIPELINE_ID"] {
                "gitlab-\(pipelineId)"
            } else {
                nil
            }
            return CIInfo(
                provider: .gitlab,
                runId: env["CI_PIPELINE_ID"],
                projectHandle: env["CI_PROJECT_PATH"],
                host: env["CI_SERVER_HOST"],
                shardSessionId: shardSessionId
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
            let shardSessionId: String? = if let workflowId = env["CIRCLE_WORKFLOW_ID"] {
                "circleci-\(workflowId)"
            } else {
                nil
            }
            return CIInfo(
                provider: .circleci,
                runId: env["CIRCLE_BUILD_NUM"],
                projectHandle: projectHandle,
                shardSessionId: shardSessionId
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
            let shardSessionId: String? = if let buildId = env["BUILDKITE_BUILD_ID"] {
                "buildkite-\(buildId)"
            } else {
                nil
            }
            return CIInfo(
                provider: .buildkite,
                runId: env["BUILDKITE_BUILD_NUMBER"],
                projectHandle: projectHandle,
                shardSessionId: shardSessionId
            )
        }

        // Codemagic
        if env["CM_BUILD_ID"] != nil {
            let shardSessionId: String? = if let buildId = env["CM_BUILD_ID"] {
                "codemagic-\(buildId)"
            } else {
                nil
            }
            return CIInfo(
                provider: .codemagic,
                runId: env["CM_BUILD_ID"],
                projectHandle: env["CM_PROJECT_ID"],
                shardSessionId: shardSessionId
            )
        }

        return nil
    }
}
