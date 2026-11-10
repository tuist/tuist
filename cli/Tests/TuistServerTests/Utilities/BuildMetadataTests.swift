import Foundation
import Testing
@testable import TuistServer

struct BuildMetadataTests {
    @Test func explicitValuesAreNeverEvictedOrOverwritten() {
        let explicit = Dictionary(uniqueKeysWithValues: (1 ... 20).map { ("customer.\($0)", "value") })
        let observations = ["tuist.cpu.available_processors": "8"]
        #expect(BuildMetadata.merge(explicit: explicit, observations: observations, limit: 20) == explicit)
        #expect(BuildMetadata.merge(explicit: explicit, observations: observations, limit: 64).count == 21)
        #expect(BuildMetadata.merge(
            explicit: ["tuist.os.type": "explicit"], observations: ["tuist.os.type": "darwin"], limit: 64
        )["tuist.os.type"] == "explicit")
    }

    @Test func runnerNameIsOptInAndEnvironmentCollectionIsAllowlisted() {
        let environment = ["RUNNER_NAME": "private-runner", "USER": "private-user", "SECRET": "secret"]
        let observations = BuildMetadata.observations(environment: environment)
        #expect(observations["tuist.ci.runner_name"] == nil)
        #expect(!observations.values.contains("private-user"))
        #expect(!observations.values.contains("secret"))
        #expect(BuildMetadata.observations(environment: environment.merging(
            ["TUIST_BUILD_METADATA_RUNNER_NAME": "1"], uniquingKeysWith: { _, new in new }
        ))["tuist.ci.runner_name"] == "private-runner")
    }

    @Test func discoveryPreservesTheReportPathPrefixWithoutForwardingCredentials() throws {
        let base = try #require(URL(string: "https://user:secret@example.com/tuist/?token=secret#fragment"))
        #expect(BuildMetadata.discoveryURL(serverURL: base)?.absoluteString == "https://example.com/tuist/api/metadata/limits")
    }

    @Test func arbitraryFutureKeysRemainStringValuesInTheWireContract() throws {
        let values = Dictionary(uniqueKeysWithValues: (1 ... 64).map { ("future.\($0)", "value \($0)") })
        let data = try JSONSerialization.data(withJSONObject: ["tags": [], "values": values])
        let decoded = try JSONDecoder().decode(BuildCustomMetadata.self, from: data)
        #expect(decoded.values?.additionalProperties == values)
        #expect(decoded.tags == [])
    }
}
