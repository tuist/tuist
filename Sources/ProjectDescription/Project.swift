import Foundation

// MARK: - Project

public struct Project: Codable, Equatable {
    public let name: String
    public let organizationName: String?
    public let packages: [Package]
    public let targets: [Target]
    public let schemes: [Scheme]
    public let settings: Settings?
    public let fileHeaderTemplate: FileHeaderTemplate?
    public let additionalFiles: [FileElement]

    public init(name: String,
                organizationName: String? = nil,
                packages: [Package] = [],
                settings: Settings? = nil,
                targets: [Target] = [],
                schemes: [Scheme] = [],
                fileHeaderTemplate: FileHeaderTemplate? = nil,
                additionalFiles: [FileElement] = [])
    {
        self.name = name
        self.organizationName = organizationName
        self.packages = packages
        self.targets = targets
        self.schemes = schemes
        self.settings = settings
        self.additionalFiles = additionalFiles
        self.fileHeaderTemplate = fileHeaderTemplate
        dumpIfNeeded(self)
    }
}
