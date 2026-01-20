import Path

public enum Fixtures {
    public static var directory: AbsolutePath {
        // swiftlint:disable:next force_try
        return try! AbsolutePath(validating: "\(#file)").parentDirectory.parentDirectory.parentDirectory.parentDirectory
            .parentDirectory
            .appending(components: "examples", "xcode")
    }
}
