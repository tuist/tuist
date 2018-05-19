import Basic
import Foundation
@testable import xcbuddykit

extension SourcesBuildPhase {
    static func test(buildfiles: [SourcesBuildFile] = [SourcesBuildFile([AbsolutePath("/Sources/Test.swift")])]) -> SourcesBuildPhase {
        return SourcesBuildPhase(buildFiles: buildfiles)
    }
}

extension ResourcesBuildPhase {
    static func test(buildfiles: [ResourcesBuildFile] = [ResourcesBuildFile([AbsolutePath("/Sources/Test.swift")])]) -> ResourcesBuildPhase {
        return ResourcesBuildPhase(buildFiles: buildfiles)
    }
}

extension CopyBuildPhase {
    static func test(name: String = "Copy",
                     destination: Destination = .frameworks,
                     subpath: String? = nil,
                     copyWhenInstalling: Bool = true) -> CopyBuildPhase {
        return CopyBuildPhase(name: name,
                              destination: destination,
                              subpath: subpath,
                              copyWhenInstalling: copyWhenInstalling)
    }
}

extension ScriptBuildPhase {
    static func test(name: String = "Script",
                     shell: String = "/bin/sh",
                     script: String = "",
                     inputFiles: [String] = [],
                     outputFiles: [String] = []) -> ScriptBuildPhase {
        return ScriptBuildPhase(name: name,
                                shell: shell,
                                script: script,
                                inputFiles: inputFiles,
                                outputFiles: outputFiles)
    }
}

extension HeadersBuildPhase {
    static func test(buildFiles: [HeadersBuildFile] = [
        HeadersBuildFile([AbsolutePath("/Headers/public.h")], accessLevel: .public),
        HeadersBuildFile([AbsolutePath("/Headers/project.h")], accessLevel: .project),
        HeadersBuildFile([AbsolutePath("/Headers/private.h")], accessLevel: .private),
    ]) -> HeadersBuildPhase {
        return HeadersBuildPhase(buildFiles: buildFiles)
    }
}
