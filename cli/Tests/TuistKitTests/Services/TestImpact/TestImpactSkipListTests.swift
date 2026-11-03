import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistServer
@testable import TuistKit

struct TestImpactSkipListTests {
    @Test func splits_whole_modules_from_single_tests() {
        let skipList = TestImpactSkipList([
            SkippedTest(module: "CoreTests", suite: "MoneyTests", name: "testAdd()"),
            SkippedTest(module: "AppUITests", suite: nil, name: nil),
            SkippedTest(module: "CoreTests", suite: "DiscountTests", name: nil),
            SkippedTest(module: "CoreTests", suite: "MoneyTests", name: "testAdd()"),
        ])

        #expect(skipList.modules == ["AppUITests"])
        #expect(skipList.tests == ["CoreTests/MoneyTests/testAdd()"])
    }

    @Test func round_trips_through_its_identifiers() {
        let skipList = TestImpactSkipList(modules: ["AppUITests"], tests: ["CoreTests/MoneyTests/testAdd()"])

        #expect(skipList.identifiers == ["AppUITests", "CoreTests/MoneyTests/testAdd()"])
        #expect(TestImpactSkipList(identifiers: skipList.identifiers) == skipList)
    }

    @Test(.inTemporaryDirectory) func writes_the_tests_to_the_file_the_test_process_reads() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let skipList = TestImpactSkipList(
            modules: ["AppUITests"],
            tests: ["CoreTests/MoneyTests/testAdd()", "CatalogTests/CatalogTests/testLoads()"]
        )

        let environment = try await skipList.environment(directory: directory, fileSystem: fileSystem)

        let path = try #require(environment["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE"])
        #expect(
            try await fileSystem.readTextFile(at: .init(validating: path))
                == "CatalogTests/CatalogTests/testLoads()\nCoreTests/MoneyTests/testAdd()\n"
        )
    }

    @Test(.inTemporaryDirectory) func needs_no_file_without_single_tests() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)

        let environment = try await TestImpactSkipList(modules: ["AppUITests"], tests: [])
            .environment(directory: directory, fileSystem: FileSystem())

        #expect(environment.isEmpty)
    }
}
