import Foundation
import TuistHTTP
import TuistServer

struct BazelInvocationLogChunk: Sendable, Equatable {
    enum Stream: Sendable, Equatable {
        case standardOutput
        case standardError
    }

    let sequenceNumber: Int
    let stream: Stream
    let message: String
}

enum BazelInvocationUploadServiceError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        "Tuist could not accept the Bazel invocation telemetry."
    }
}

struct BazelInvocationUploadService {
    private let fullHandleService: FullHandleServicing

    init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    func upload(
        invocation: BazelInvocationTelemetry,
        criticalPath: BazelCriticalPathTelemetry?,
        buildTimeline: BazelBuildTimelineTelemetry?,
        testResults: [BazelTestResultTelemetry],
        logs: [BazelInvocationLogChunk],
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let handles = try fullHandleService.parse(fullHandle)
        let client = Client.authenticated(serverURL: serverURL)
        let path = Operations.createBazelInvocation.Input.Path(
            account_handle: handles.accountHandle,
            project_handle: handles.projectHandle
        )

        let invocationResponse = try await client.createBazelInvocation(
            .init(
                path: path,
                body: .json(
                    invocationPayload(
                        invocation,
                        criticalPath: criticalPath,
                        buildTimeline: buildTimeline
                    )
                )
            )
        )
        guard case .accepted = invocationResponse else { throw BazelInvocationUploadServiceError.unexpectedResponse }

        if !testResults.isEmpty {
            let testResultsResponse = try await client.createBazelTestResults(
                .init(
                    path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                    body: .json(.init(test_results: testResults.map(testResultPayload)))
                )
            )
            guard case .accepted = testResultsResponse else { throw BazelInvocationUploadServiceError.unexpectedResponse }
        }

        if !logs.isEmpty {
            let logsResponse = try await client.createBazelInvocationLogs(
                .init(
                    path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                    body: .json(.init(invocation_id: invocation.invocationID, logs: logs.map(logPayload)))
                )
            )
            guard case .accepted = logsResponse else { throw BazelInvocationUploadServiceError.unexpectedResponse }
        }
    }

    private func invocationPayload(
        _ invocation: BazelInvocationTelemetry,
        criticalPath: BazelCriticalPathTelemetry?,
        buildTimeline: BazelBuildTimelineTelemetry?
    ) -> Operations.createBazelInvocation.Input.Body.jsonPayload {
        .init(
            bazel_version: invocation.bazelVersion,
            build_timeline: buildTimelinePayload(buildTimeline),
            build_metrics: .init(
                actions_executed: invocation.buildMetrics.actionsExecuted,
                cpu_time_ms: invocation.buildMetrics.cpuTimeMilliseconds,
                packages_loaded: invocation.buildMetrics.packagesLoaded,
                targets_configured: invocation.buildMetrics.targetsConfigured,
                targets_loaded: invocation.buildMetrics.targetsLoaded
            ),
            canonical_command_line: invocation.canonicalCommandLine,
            command: invocation.command,
            client_platform: invocation.clientPlatform,
            compilation_mode: compilationMode(invocation.compilationMode),
            configurations: invocation.configurations,
            critical_path: criticalPathPayload(criticalPath),
            exit_code: invocation.exitCode,
            finished_at: invocation.finishedAt,
            git_branch: invocation.gitBranch,
            git_commit_sha: invocation.gitCommitSHA,
            invocation_id: invocation.invocationID,
            original_command_line: invocation.originalCommandLine,
            remote_cache_enabled: invocation.remoteCacheEnabled,
            remote_execution_enabled: invocation.remoteExecutionEnabled,
            requested_command: invocation.requestedCommand,
            started_at: invocation.startedAt,
            status: invocation.status == "success" ? .success : .failure,
            target_patterns: invocation.targetPatterns
        )
    }

    private func criticalPathPayload(
        _ criticalPath: BazelCriticalPathTelemetry?
    ) -> Operations.createBazelInvocation.Input.Body.jsonPayload.critical_pathPayload? {
        guard let criticalPath else { return nil }

        return .init(
            actions: criticalPath.actions.map { action in
                .init(description: action.description, duration_ms: action.durationMilliseconds)
            },
            duration_ms: criticalPath.durationMilliseconds
        )
    }

    private func buildTimelinePayload(
        _ buildTimeline: BazelBuildTimelineTelemetry?
    ) -> Operations.createBazelInvocation.Input.Body.jsonPayload.build_timelinePayload? {
        guard let buildTimeline else { return nil }

        return .init(
            duration_ms: buildTimeline.durationMilliseconds,
            lanes: buildTimeline.laneLabels,
            spans: buildTimeline.spans.map { span in
                .init(
                    category: buildTimelineCategory(span.category),
                    description: span.description,
                    duration_ms: span.durationMilliseconds,
                    lane: span.lane,
                    start_ms: span.startMilliseconds
                )
            }
        )
    }

    private func testResultPayload(
        _ testResult: BazelTestResultTelemetry
    ) -> Operations.createBazelTestResults.Input.Body.jsonPayload.test_resultsPayloadPayload {
        .init(
            attempt_count: testResult.attemptCount,
            duration_ms: testResult.durationMilliseconds,
            finished_at: testResult.finishedAt,
            invocation_id: testResult.invocationID,
            status: testResultStatus(testResult.status),
            target_label: testResult.targetLabel
        )
    }

    private func logPayload(
        _ log: BazelInvocationLogChunk
    ) -> Operations.createBazelInvocationLogs.Input.Body.jsonPayload.logsPayloadPayload {
        .init(
            message: log.message,
            sequence_number: log.sequenceNumber,
            stream: log.stream == .standardOutput ? .stdout : .stderr
        )
    }

    private func compilationMode(
        _ value: String
    ) -> Operations.createBazelInvocation.Input.Body.jsonPayload.compilation_modePayload {
        switch value {
        case "dbg": .dbg
        case "fastbuild": .fastbuild
        case "opt": .opt
        default: ._empty
        }
    }

    private func buildTimelineCategory(
        _ value: String
    ) -> Operations.createBazelInvocation.Input.Body.jsonPayload.build_timelinePayload.spansPayloadPayload.categoryPayload {
        switch value {
        case "analysis": .analysis
        case "critical_path": .critical_path
        case "execution": .execution
        case "loading": .loading
        case "setup": .setup
        default: .other
        }
    }

    private func testResultStatus(
        _ value: String
    ) -> Operations.createBazelTestResults.Input.Body.jsonPayload.test_resultsPayloadPayload.statusPayload {
        switch value {
        case "success": .success
        case "flaky": .flaky
        case "skipped": .skipped
        default: .failure
        }
    }
}
