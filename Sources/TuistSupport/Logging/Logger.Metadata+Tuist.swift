extension Logger.Metadata {
    public static let tuist: String = "is"

    public static let successKey: String = "success"
    public static var success: Logger.Metadata {
        [tuist: .string(successKey)]
    }

    public static let sectionKey: String = "section"
    public static var section: Logger.Metadata {
        [tuist: .string(sectionKey)]
    }

    public static let subsectionKey: String = "subsection"
    public static var subsection: Logger.Metadata {
        [tuist: .string(subsectionKey)]
    }

    public static let prettyKey: String = "pretty"
    public static var pretty: Logger.Metadata {
        [tuist: .string(prettyKey)]
    }

    public static let warningTitleKey: String = "warning-title"
    public static var warningTitle: Logger.Metadata {
        [tuist: .string(warningTitleKey)]
    }

    public static let warningBodyKey: String = "warning-body"
    public static var warningBody: Logger.Metadata {
        [tuist: .string(warningBodyKey)]
    }
}
