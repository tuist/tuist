extension Logger.Metadata {
    
    public static let tuist: String = "is"
    
    public static let successKey: String = "success"
    public static var success: Logger.Metadata {
        return [ tuist: .string(successKey) ]
    }
    
    public static let sectionKey: String = "section"
    public static var section: Logger.Metadata {
        return [ tuist: .string(sectionKey) ]
    }
    
    public static let subsectionKey: String = "subsection"
    public static var subsection: Logger.Metadata {
        return [ tuist: .string(subsectionKey) ]
    }
    
    public static let prettyKey: String = "pretty"
    public static var pretty: Logger.Metadata {
        return [ tuist: .string(prettyKey) ]
    }
    
}
