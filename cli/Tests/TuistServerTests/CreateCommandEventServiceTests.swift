import Foundation
import Testing
import TuistCore

@testable import TuistServer

struct CreateCommandEventServiceTests {
    @Test func serializes_individual_hash_inputs_without_replacing_declared_destinations() throws {
        let binary = TargetContentHashSubhashes.test(
            embeddedProductReferences: "embedded-hash",
            destinations: ["iPhone"],
            foreignBuild: "foreign-hash"
        )
        let selective = TargetContentHashSubhashes.test(
            destinations: ["mac"],
            testDevice: "iPhone 16",
            testRuntime: "iOS-16"
        )
        let graph = RunGraph(
            name: "Graph",
            projects: [.test(targets: [.test(
                destinations: [.iPhone, .iPad, .mac],
                binaryCacheMetadata: .init(hash: "binary", hit: .miss, subhashes: binary)
            ), .test(
                selectiveTestingMetdata: .init(hash: "testing", hit: .local, subhashes: selective)
            )])],
            binaryBuildDuration: nil
        )
        let data = try JSONEncoder().encode(CreateCommandEventService().map(graph: graph))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let projects = try #require(json["projects"] as? [[String: Any]])
        let targets = try #require(projects.first?["targets"] as? [[String: Any]])
        let target = try #require(targets.first)
        #expect(Set(try #require(target["destinations"] as? [String])) == ["iphone", "ipad", "mac"])
        let binaryMetadata = try #require(target["binary_cache_metadata"] as? [String: Any])
        let binaryInputs = try #require(binaryMetadata["subhashes"] as? [String: Any])
        #expect(binaryInputs["destinations"] as? [String] == binary.destinations)
        #expect(binaryInputs["foreign_build"] as? String == "foreign-hash")
        #expect(binaryInputs["test_device"] as? String == "")
        #expect(binaryInputs["test_runtime"] as? String == "")
        #expect(binaryInputs["embedded_product_references"] as? String == "embedded-hash")
        let selectiveMetadata = try #require(targets[1]["selective_testing_metadata"] as? [String: Any])
        let selectiveInputs = try #require(selectiveMetadata["subhashes"] as? [String: Any])
        #expect(selectiveInputs["destinations"] as? [String] == selective.destinations)
        #expect(selectiveInputs["foreign_build"] as? String == "")
        #expect(selectiveInputs["test_device"] as? String == "iPhone 16")
        #expect(selectiveInputs["test_runtime"] as? String == "iOS-16")
        #expect(selectiveInputs["embedded_product_references"] as? String == "")
    }

    @Test func historical_report_omits_unavailable_hash_inputs() throws {
        let graph = RunGraph(
            name: "Graph",
            projects: [.test(targets: [.test(
                binaryCacheMetadata: .init(hash: "old", hit: .miss, subhashes: .test())
            )])],
            binaryBuildDuration: nil
        )
        let data = try JSONEncoder().encode(CreateCommandEventService().map(graph: graph))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("foreign_build"))
        #expect(!json.contains("test_device"))
        #expect(!json.contains("test_runtime"))
        #expect(!json.contains("embedded_product_references"))
        let target = try #require(CreateCommandEventService().map(graph: graph).projects.first?.targets.first)
        #expect(target.binary_cache_metadata?.subhashes?.destinations == nil)
    }
}
