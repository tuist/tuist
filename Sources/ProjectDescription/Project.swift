import Foundation

// MARK: - Project

public class Project {
    public let name: String
    public let schemes: [Scheme]
    public let targets: [Target]
    public let settings: Settings?
    public let config: String?

    public init(name: String,
                config: String? = nil,
                schemes: [Scheme] = [],
                settings: Settings? = nil,
                targets: [Target] = []) {
        self.name = name
        self.schemes = schemes
        self.targets = targets
        self.settings = settings
        self.config = config
        dumpIfNeeded(self)
    }
}

// MARK: - Project (JSONConvertible)

extension Project: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["name"] = name.toJSON()
        dictionary["schemes"] = schemes.toJSON()
        dictionary["targets"] = targets.toJSON()
        if let settings = settings {
            dictionary["settings"] = settings.toJSON()
        }
        if let config = config {
            dictionary["config"] = config.toJSON()
        }
        return .dictionary(dictionary)
    }
}

// func initProject() {
// let project = Project(name: "{{NAME}}",
//                      schemes: [
//                          /* Project schemes are defined here */
//                          Scheme(name: "{{NAME}}",
//                                 shared: true,
//                                 buildAction: BuildAction(targets: ["{{NAME}}"])),
//                      ],
//                      settings: Settings(base: [:],
//                                         debug: Configuration(settings: [:],
//                                                              xcconfig: "Configs/Debug.xcconfig")),
//                      targets: [
//                          Target(name: "{{NAME}}",
//                                 platform: .ios,
//                                 product: .app,
//                                 infoPlist: "Info.plist",
//                                 dependencies: [
//                                     /* Target dependencies can be defined here */
//                                     /* .framework(path: "framework") */
//                                 ],
//                                 settings: nil,
//                                 buildPhases: [
//                                     .sources([.include(["./Sources/**/*.swift"])]),
//                                     /* Other build phases can be added here */
//                                     /* .resources([.include(["./Resousrces /**/ *"])]) */
//                          ]),
// ])
// }
