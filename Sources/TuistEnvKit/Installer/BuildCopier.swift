import Foundation
import TSCBasic
import TuistSupport

protocol BuildCopying: AnyObject {
    func copy(from: AbsolutePath, to: AbsolutePath) throws
}

class BuildCopier: BuildCopying {
    // MARK: - Static

    /// Files that should be copied (if they exist).
    static let files: [String] = [
        "tuist",
        Constants.templatesDirectoryName,
        Constants.vendorDirectoryName,
        // Project description
        "ProjectDescription.swiftmodule",
        "ProjectDescription.swiftdoc",
        "ProjectDescription.swiftinterface",
        "libProjectDescription.dylib",
    ]

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try BuildCopier.files.forEach { file in
            let filePath = from.appending(component: file)
            let toPath = to.appending(component: file)
            if !FileHandler.shared.exists(filePath) { return }
            try System.shared.run(["/bin/cp", "-rf", filePath.pathString, toPath.pathString])
            if file == "tuist" {
                try System.shared.run(["/bin/chmod", "+x", toPath.pathString])
            }
        }
    }
}
