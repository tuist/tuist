struct PackageDescriptionContext: Encodable {
    let packageDirectory: String
    let gitInformation: GitInformation?

    struct GitInformation: Encodable {
        let currentTag: String?
        let currentCommit: String
        let hasUncommittedChanges: Bool
    }
}
