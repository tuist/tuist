import Foundation
import Testing

@testable import TuistBazelCommand

struct BazelBuildEventParserTests {
    @Test func parses_invocation_and_test_summary() throws {
        let events = """
        {"id":{"started":{}},"started":{"command":"test","buildToolVersion":"8.1.0","startTimeMillis":"1700000000000"}}
        {"structuredCommandLine":{"commandLineLabel":"original","sections":[{"sectionLabel":"executable","chunkList":{"chunk":["bazel"]}},{"sectionLabel":"command options","optionList":{"option":[{"optionName":"client_env","combinedForm":"--client_env=TOKEN=do-not-upload"},{"optionName":"remote_header","combinedForm":"--remote_header=x-api-key=do-not-upload"},{"optionName":"compilation_mode","combinedForm":"--compilation_mode=opt"}]}}]}}
        {"structuredCommandLine":{"commandLineLabel":"canonical","sections":[{"sectionLabel":"executable","chunkList":{"chunk":["bazel"]}},{"sectionLabel":"command","chunkList":{"chunk":["test","//App:AppTests"]}},{"sectionLabel":"command options","optionList":{"option":[{"optionName":"output_base","combinedForm":"--output_base=/private/path"},{"optionName":"config","combinedForm":"--config=continuous-integration"}]}}]}}
        {"id":{"optionsParsed":{}},"optionsParsed":{"cmdLine":["--config=continuous-integration","--compilation_mode=opt","--remote_cache=grpcs://cache.tuist.dev","--remote_executor=grpcs://executor.tuist.dev"]}}
        {"id":{"buildMetrics":{}},"buildMetrics":{"actionSummary":{"actionsExecuted":"89"},"targetMetrics":{"targetsLoaded":"42","targetsConfigured":"3964"},"packageMetrics":{"packagesLoaded":"160"},"timingMetrics":{"cpuTimeInMs":"15503","wallTimeInMs":"34200"}}}
        {"id":{"pattern":{"pattern":["//App:AppTests"]}}}
        {"id":{"testSummary":{"label":"//App:AppTests"}},"testSummary":{"overallStatus":"FLAKY","totalRunDurationMillis":"2500","lastStopTimeMillis":"1700000002500","attemptCount":"2"}}
        {"id":{"buildFinished":{}},"finished":{"overallSuccess":true,"finishTimeMillis":"1700000003000","exitCode":{"code":0}}}
        """

        let result = try #require(
            BazelBuildEventParser().parse(
                data: Data(events.utf8),
                invocationID: "invocation-id",
                startedAt: Date(timeIntervalSince1970: 0),
                command: "build",
                requestedCommand: "bazel test --remote_header=<REDACTED> //App:AppTests",
                finishedAt: Date(timeIntervalSince1970: 1),
                succeeded: false,
                gitBranch: "main",
                gitCommitSHA: "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f"
            )
        )

        #expect(result.invocation.invocationID == "invocation-id")
        #expect(result.invocation.command == "test")
        #expect(result.invocation.status == "success")
        #expect(result.invocation.requestedCommand == "bazel test --remote_header=<REDACTED> //App:AppTests")
        #expect(result.invocation.originalCommandLine == ["bazel", "--remote_header=<REDACTED>", "--compilation_mode=opt"])
        #expect(result.invocation.canonicalCommandLine == [
            "bazel",
            "test",
            "//App:AppTests",
            "--output_base=<REDACTED>",
            "--config=continuous-integration",
        ])
        #expect(result.invocation.targetPatterns == ["//App:AppTests"])
        #expect(result.invocation.bazelVersion == "8.1.0")
        #expect(result.invocation.gitBranch == "main")
        #expect(result.invocation.gitCommitSHA == "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f")
        #expect(result.invocation.configurations == ["continuous-integration"])
        #expect(result.invocation.compilationMode == "opt")
        #expect(result.invocation.remoteCacheEnabled)
        #expect(result.invocation.remoteExecutionEnabled)
        #expect(result.invocation.buildMetrics == BazelBuildMetricsTelemetry(
            cpuTimeMilliseconds: 15503,
            actionsExecuted: 89,
            targetsLoaded: 42,
            targetsConfigured: 3964,
            packagesLoaded: 160
        ))
        #expect(result.testResults == [
            BazelTestResultTelemetry(
                invocationID: "invocation-id",
                targetLabel: "//App:AppTests",
                status: "flaky",
                durationMilliseconds: 2500,
                attemptCount: 2,
                finishedAt: Date(timeIntervalSince1970: 1_700_000_002.5)
            ),
        ])
    }
}
