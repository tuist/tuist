import XcodeGraph

extension Target {
    /// This function validates the sources against other target metadata returning which sources from the list
    /// are valid and invalid.
    /// - Returns: A list of valid and invalid sources.
    var validatedSources: (valid: [SourceFile], invalid: [SourceFile]) {
        switch product {
        case .stickerPackExtension, .watch2App:
            return (valid: [], invalid: sources)
        case .bundle:
            if isExclusiveTo(.macOS) {
                return (valid: sources, invalid: [])
            } else {
                return (
                    valid: sources.filter { $0.path.extension == "metal" },
                    invalid: sources.filter { $0.path.extension != "metal" }
                )
            }
        default:
            return (valid: sources, invalid: [])
        }
    }

    var shouldCoredataModelsBeSources: Bool {
        switch product {
        case .stickerPackExtension, .watch2App:
            return false
        case .bundle:
            return isExclusiveTo(.macOS)
        default:
            return true
        }
    }
}
