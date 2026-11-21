import Foundation
import Mockable
import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistGenerator

struct ResourcesProjectMapperDeclaredContentsTests {
    private let subject: ResourcesProjectMapper
    private let projectPath = try! AbsolutePath(validating: "/Project") // swiftlint:disable:this force_try

    init() {
        let contentHasher = MockContentHashing()
        given(contentHasher)
            .hash(Parameter<Data>.any)
            .willProduce { String(data: $0, encoding: .utf8)! }
        subject = ResourcesProjectMapper(contentHasher: contentHasher, buildableFolderChecker: BuildableFolderChecker())
    }

    @Test(arguments: [Product.staticFramework, .staticLibrary])
    func staticTargetWithDeclaredSourcesAndResources_splitsTheFolderByFileType(product: Product) async throws {
        // Given
        let folder = generatedFolder(contents: [.sources, .resources])

        // When
        let (project, _) = try await map(product: product, folder: folder)

        // Then
        let target = try #require(project.targets["Framework"])
        let bundle = try #require(project.targets["Project_Framework"])
        #expect(target.buildableFolders.map(\.contents) == [[.sources]])
        #expect(bundle.buildableFolders.map(\.contents) == [[.resources]])
        #expect(target.dependencies.contains(.target(name: "Project_Framework", condition: .when([.ios]))))

        let targetExcluded = try listSetting("EXCLUDED_SOURCE_FILE_NAMES", in: target)
        let targetIncluded = try listSetting("INCLUDED_SOURCE_FILE_NAMES", in: target)
        let bundleExcluded = try listSetting("EXCLUDED_SOURCE_FILE_NAMES", in: bundle)
        let levels = (0 ..< 8).map { "$(SRCROOT)/Module/Generated" + String(repeating: "/*", count: $0) }
        #expect(targetExcluded == ["$(inherited)"] + levels.map { "\"\($0)/*\"" })
        #expect(targetIncluded.contains("\"$(SRCROOT)/Module/Generated/*.swift\""))
        #expect(targetIncluded.contains("\"$(SRCROOT)/Module/Generated/*/*/*/*/*/*/*/*.swift\""))
        #expect(targetIncluded.contains("\"$(SRCROOT)/Module/Generated/*.h\""))
        #expect(targetIncluded.contains("\"$(SRCROOT)/Module/Generated/*.xcassets\""))
        #expect(!targetIncluded.contains("\"$(SRCROOT)/Module/Generated/*.metal\""))
        #expect(!targetIncluded.contains("\"$(SRCROOT)/Module/Generated/*.json\""))
        #expect(bundleExcluded.contains("*.swift"))
        #expect(bundleExcluded.contains("*.h"))
        #expect(!bundleExcluded.contains("*.xcassets"))
        #expect(!bundleExcluded.contains("*.metal"))
        #expect(bundle.settings?.base["INCLUDED_SOURCE_FILE_NAMES"] == nil)
    }

    @Test
    func staticTargetWithDeclaredResources_movesTheWholeFolderToTheBundle() async throws {
        // Given
        let folder = generatedFolder(contents: [.resources])

        // When
        let (project, _) = try await map(product: .staticFramework, folder: folder)

        // Then
        let target = try #require(project.targets["Framework"])
        let bundle = try #require(project.targets["Project_Framework"])
        #expect(target.buildableFolders.isEmpty)
        #expect(bundle.buildableFolders.map(\.path) == [folder.path])
        #expect(target.settings?.base["INCLUDED_SOURCE_FILE_NAMES"] == nil)
        #expect(bundle.settings?.base["EXCLUDED_SOURCE_FILE_NAMES"] == nil)
    }

    @Test
    func staticTargetWithDeclaredSources_keepsTheFolderAndNeedsNoBundle() async throws {
        // Given
        let folder = generatedFolder(contents: [.sources], files: ["Resource.json"])

        // When
        let (project, sideEffects) = try await map(product: .staticFramework, folder: folder)

        // Then
        #expect(project.targets.keys.sorted() == ["Framework"])
        #expect(project.targets["Framework"]?.buildableFolders == [folder])
        #expect(sideEffects.isEmpty)
    }

    @Test
    func dynamicFrameworkWithDeclaredResources_keepsTheFolderAndGeneratesTheAccessor() async throws {
        // Given
        let folder = generatedFolder(contents: [.sources, .resources])

        // When
        let (project, sideEffects) = try await map(product: .framework, folder: folder)

        // Then
        let target = try #require(project.targets["Framework"])
        #expect(project.targets.keys.sorted() == ["Framework"])
        #expect(target.buildableFolders == [folder])
        #expect(target.sources.map(\.path.basename) == ["TuistBundle+Framework.swift"])
        #expect(sideEffects.count == 1)
    }

    @Test
    func staticTargetWithDeclaredContents_keepsThemWhenAnExplicitCatalogIsExcluded() async throws {
        // Given
        let folder = generatedFolder(contents: [.sources, .resources], files: ["Assets.xcassets"])
        let catalog = folder.path.appending(component: "Assets.xcassets")

        // When
        let (project, _) = try await map(product: .staticFramework, folder: folder, resources: [.file(path: catalog)])

        // Then
        let target = try #require(project.targets["Framework"])
        let bundle = try #require(project.targets["Project_Framework"])
        #expect(target.buildableFolders.map(\.contents) == [[.sources]])
        #expect(bundle.buildableFolders.map(\.contents) == [[.resources]])
    }

    @Test(arguments: [Product.staticFramework, .framework, .app])
    func declaredFolder_mapsTheSameEmptyAndFilled(product: Product) async throws {
        for contents: Set<BuildableFolderContent> in [[.sources], [.resources], [.sources, .resources]] {
            // Given
            let empty = generatedFolder(contents: contents)
            let filled = generatedFolder(
                contents: contents,
                files: ["Generated.swift", "Generated.h", "Data.json", "Shaders.metal", "Assets.xcassets"]
            )

            // When
            let (emptyProject, emptySideEffects) = try await map(product: product, folder: empty)
            let (filledProject, filledSideEffects) = try await map(product: product, folder: filled)

            // Then
            #expect(shape(of: emptyProject) == shape(of: filledProject))
            #expect(emptySideEffects == filledSideEffects)
        }
    }

    // MARK: - Helpers

    private func generatedFolder(contents: Set<BuildableFolderContent>, files: [String] = []) -> BuildableFolder {
        let path = projectPath.appending(components: "Module", "Generated")
        return BuildableFolder(
            path: path,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: files.map { BuildableFolderFile(path: path.appending(component: $0), compilerFlags: nil) },
            contents: contents
        )
    }

    private func map(
        product: Product,
        folder: BuildableFolder,
        resources: [ResourceFileElement] = []
    ) async throws -> (Project, [SideEffectDescriptor]) {
        let target = Target.test(
            name: "Framework",
            product: product,
            sources: [],
            resources: ResourceFileElements(resources),
            buildableFolders: [folder]
        )
        let project = Project.test(path: projectPath, sourceRootPath: projectPath, name: "Project", targets: [target])
        return try await subject.map(project: project)
    }

    private func listSetting(_ key: String, in target: Target) throws -> [String] {
        guard case let .array(values) = try #require(target.settings?.base[key]) else {
            Issue.record("Expected \(key) to be a list")
            return []
        }
        return values
    }

    /// Everything the generated project is built from, without the files Tuist resolved on disk.
    private func shape(of project: Project) -> [String] {
        project.targets.values.sorted(by: { $0.name < $1.name }).map { target in
            let folders = target.buildableFolders.map { folder in
                "\(folder.path.pathString):\(folder.contents.map { $0.map(\.rawValue).sorted() } ?? [])"
            }
            return [
                target.name,
                target.product.rawValue,
                "\(target.sources.map(\.path))",
                "\(folders)",
                "\(target.dependencies)",
                "\(target.settings?.base.sorted(by: { $0.key < $1.key }) ?? [])",
            ].joined(separator: "|")
        }
    }
}
