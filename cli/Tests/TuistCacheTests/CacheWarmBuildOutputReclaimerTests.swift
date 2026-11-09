import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistCache

struct CacheWarmBuildOutputReclaimerTests {
    private let fileSystem = FileSystem()
    private let subject = CacheWarmBuildOutputReclaimer()

    @Test(.inTemporaryDirectory)
    func reclaimRemovesTheProductsAndIntermediatesOfTheDestinationJustBuilt() async throws {
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await seedBuild(in: derivedDataPath, productsDirectoryName: "Debug-iphonesimulator", projects: ["Tuist", "Rosalind"])

        await subject.reclaim(
            derivedDataPath: derivedDataPath,
            productsDirectoryName: "Debug-iphonesimulator",
            reservedProductsDirectoryNames: []
        )

        #expect(try await fileSystem.exists(
            derivedDataPath.appending(components: ["Build", "Products", "Debug-iphonesimulator"])
        ) == false)
        #expect(try await fileSystem.exists(
            derivedDataPath.appending(components: ["Build", "Intermediates.noindex", "Tuist.build", "Debug-iphonesimulator"])
        ) == false)
        // Every project in the workspace has intermediates of its own, so reclaiming one destination has to
        // reach all of them and not just the first match.
        #expect(try await fileSystem.exists(
            derivedDataPath.appending(components: ["Build", "Intermediates.noindex", "Rosalind.build", "Debug-iphonesimulator"])
        ) == false)
    }

    @Test(.inTemporaryDirectory)
    func reclaimLeavesTheDestinationsThatHaveNotBeenBuiltYet() async throws {
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await seedBuild(in: derivedDataPath, productsDirectoryName: "Debug-iphonesimulator", projects: ["Tuist"])
        try await seedBuild(in: derivedDataPath, productsDirectoryName: "Debug-iphoneos", projects: ["Tuist"])
        try await seedBuild(in: derivedDataPath, productsDirectoryName: "Debug", projects: ["Tuist"])
        // Shared build state lives beside the per-destination directories and must survive.
        let sharedBuildData = derivedDataPath.appending(components: ["Build", "Intermediates.noindex", "XCBuildData"])
        try await fileSystem.makeDirectory(at: sharedBuildData)

        await subject.reclaim(
            derivedDataPath: derivedDataPath,
            productsDirectoryName: "Debug-iphonesimulator",
            reservedProductsDirectoryNames: []
        )

        for surviving in ["Debug-iphoneos", "Debug"] {
            #expect(try await fileSystem.exists(
                derivedDataPath.appending(components: ["Build", "Products", surviving])
            ))
            #expect(try await fileSystem.exists(
                derivedDataPath.appending(components: ["Build", "Intermediates.noindex", "Tuist.build", surviving])
            ))
        }
        #expect(try await fileSystem.exists(sharedBuildData))
    }

    @Test(.inTemporaryDirectory)
    func reclaimKeepsAProductsDirectoryALaterSchemeBuildsIntoAgain() async throws {
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await seedBuild(in: derivedDataPath, productsDirectoryName: "Debug-iphonesimulator", projects: ["Tuist"])

        await subject.reclaim(
            derivedDataPath: derivedDataPath,
            productsDirectoryName: "Debug-iphonesimulator",
            reservedProductsDirectoryNames: ["Debug-iphonesimulator"]
        )

        #expect(try await fileSystem.exists(
            derivedDataPath.appending(components: ["Build", "Products", "Debug-iphonesimulator"])
        ))
        #expect(try await fileSystem.exists(
            derivedDataPath.appending(components: ["Build", "Intermediates.noindex", "Tuist.build", "Debug-iphonesimulator"])
        ))
    }

    @Test(.inTemporaryDirectory)
    func reclaimDoesNotThrowWhenTheBuildWroteNothing() async throws {
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)

        await subject.reclaim(
            derivedDataPath: derivedDataPath,
            productsDirectoryName: "Debug",
            reservedProductsDirectoryNames: []
        )
    }

    @Test(.inTemporaryDirectory)
    func reclaimResultBundleRemovesTheBundle() async throws {
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        let resultBundlePath = derivedDataPath.appending(component: UUID().uuidString)
        try await fileSystem.makeDirectory(at: resultBundlePath)
        try await fileSystem.writeText("result", at: resultBundlePath.appending(component: "Info.plist"))

        await subject.reclaimResultBundle(at: resultBundlePath)

        #expect(try await fileSystem.exists(resultBundlePath) == false)
    }

    private func seedBuild(
        in derivedDataPath: AbsolutePath,
        productsDirectoryName: String,
        projects: [String]
    ) async throws {
        let products = derivedDataPath.appending(components: ["Build", "Products", productsDirectoryName])
        try await fileSystem.makeDirectory(at: products)
        try await fileSystem.writeText("framework", at: products.appending(component: "Product.framework"))

        for project in projects {
            let intermediates = derivedDataPath.appending(components: [
                "Build",
                "Intermediates.noindex",
                "\(project).build",
                productsDirectoryName,
            ])
            try await fileSystem.makeDirectory(at: intermediates)
            try await fileSystem.writeText("object", at: intermediates.appending(component: "Object.o"))
        }
    }
}
