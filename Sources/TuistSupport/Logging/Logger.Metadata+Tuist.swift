public extension Logger.Metadata {
    static let tuist: String = "is"

    static let successKey: String = "success"
    static var success: Logger.Metadata {
        [tuist: .string(successKey)]
    }

    static let sectionKey: String = "section"
    static var section: Logger.Metadata {
        [tuist: .string(sectionKey)]
    }

    static let subsectionKey: String = "subsection"
    static var subsection: Logger.Metadata {
        [tuist: .string(subsectionKey)]
    }

    static let prettyKey: String = "pretty"
    static var pretty: Logger.Metadata {
        [tuist: .string(prettyKey)]
    }
}
