import Foundation
import TSCBasic
import TuistSupport
import TuistSupportTesting
import Testing
@testable import TuistEnvKit

struct BuildCopierTests {
    let subject: BuildCopier
    let fileManager: FileManager
    init() {
        fileManager = .default
        subject = BuildCopier()
    }


    @Test
    func test_files() {
        #expect(BuildCopier.files == [
            "tuist",
            "Templates",
            "vendor",
            "ProjectDescription.swiftmodule",
            "ProjectDescription.swiftdoc",
            "ProjectDescription.swiftinterface",
            "libProjectDescription.dylib",
        ])
    }

    @Test
    func test_copy() throws {
        let fromDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let fromPath = fromDir.path

        let toDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let toPath = toDir.path

        // Creating files
        for file in BuildCopier.files {
            let filePath = fromPath.appending(component: file)
            try Data().write(to: filePath.url)
        }
        let testFilePath = fromPath.appending(component: "test")
        try Data().write(to: testFilePath.url)

        try subject.copy(from: fromPath, to: toPath)

        #expect(toPath.glob("*").count == BuildCopier.files.count)
        #expect(!fileManager.fileExists(atPath: toPath.appending(component: "test").pathString))
    }

    @Test
    func test_copy_without_templates() throws {
        let fromDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let fromPath = fromDir.path

        let toDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let toPath = toDir.path

        // Creating files
        try BuildCopier.files
            // Simulate Templates directory not being present
            .filter { $0 != Constants.templatesDirectoryName }
            .forEach { file in
                let filePath = fromPath.appending(component: file)
                try Data().write(to: filePath.url)
            }
        let testFilePath = fromPath.appending(component: "test")
        try Data().write(to: testFilePath.url)

        try subject.copy(from: fromPath, to: toPath)

        #expect(toPath.glob("*").count == BuildCopier.files.count - 1)
        #expect(!fileManager.fileExists(atPath: toPath.appending(component: "test").pathString))
    }
}
