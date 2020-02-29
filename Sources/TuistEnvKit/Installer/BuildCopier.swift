import Basic
import Foundation
import TuistSupport

protocol BuildCopying: AnyObject {
    func copy(from: AbsolutePath, to: AbsolutePath) throws
}

class BuildCopier: BuildCopying {
    // MARK: - Static

    /// Files that should be copied (if they exist).
    static let files: [String] = [
        "tuist",
        "Templates"
    ] + libraryFiles(for: "ProjectDescription") + libraryFiles(for: "TemplateDescription")

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try BuildCopier.files.forEach { file in
            let filePath = from.appending(component: file)
            let toPath = to.appending(component: file)
            if !FileHandler.shared.exists(filePath) { return }
            try System.shared.run("/bin/cp", "-rf", filePath.pathString, toPath.pathString)
            if file == "tuist" {
                try System.shared.run("/bin/chmod", "+x", toPath.pathString)
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func libraryFiles(for name: String) -> [String] {
        [
            "\(name).swiftmodule",
            "\(name).swiftdoc",
            "\(name).swiftinterface",
            "lib\(name).dylib",
        ]
    }
}
