import Foundation

// MARK: - Project

/// Project is similar to what you specify in `.xcodeproj`
public struct Project: Codable, Equatable {
    /// Name of the project
    public let name: String
    /// Organization name to be used for the project
    public let organizationName: String?
    /// Project Swift packages
    public let packages: [Package]
    /// Project targets
    public let targets: [Target]
    /// Project schemes
    public let schemes: [Scheme]
    /// Project settings
    public let settings: Settings?
    /// Customizable file header template for Xcode built-in file templates
    public let fileHeaderTemplate: FileHeaderTemplate?
    /// The additional files to include in the project (won't be included in a build phase)
    public let additionalFiles: [FileElement]
    /// Resource synthesizers create type-safe accessors for your resources
    public let resourceSynthesizers: [ResourceSynthesizer]

    public init(
        name: String,
        organizationName: String? = nil,
        packages: [Package] = [],
        settings: Settings? = nil,
        targets: [Target] = [],
        schemes: [Scheme] = [],
        fileHeaderTemplate: FileHeaderTemplate? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = .default
    ) {
        self.name = name
        self.organizationName = organizationName
        self.packages = packages
        self.targets = targets
        self.schemes = schemes
        self.settings = settings
        self.additionalFiles = additionalFiles
        self.fileHeaderTemplate = fileHeaderTemplate
        self.resourceSynthesizers = resourceSynthesizers
        dumpIfNeeded(self)
    }
}
