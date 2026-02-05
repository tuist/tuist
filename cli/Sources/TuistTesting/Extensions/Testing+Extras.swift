import Path
import Testing
import TuistSupport

public func expectDirectoryContentEqual(
    _ directory: AbsolutePath,
    _ expected: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let directoryContent = try FileHandler.shared
        .contentsOfDirectory(directory)
        .map(\.pathString)
        .sorted()

    let expectedContent = try expected
        .map { directory.appending(try RelativePath(validating: $0)) }
        .map(\.pathString)
        .sorted()

    let message = """
    The directory content:
    ===========
    \(directoryContent.isEmpty ? "<Empty>" : directoryContent.joined(separator: "\n"))

    Doesn't equal to expected:
    ===========
    \(expectedContent.isEmpty ? "<Empty>" : expectedContent.joined(separator: "\n"))
    """

    #expect(directoryContent == expectedContent, "\(message)", sourceLocation: sourceLocation)
}
