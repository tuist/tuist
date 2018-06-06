import Foundation

// MARK: - Project

public class Project {
    public let name: String
    public let schemes: [Scheme]
    public let targets: [Target]
    public let settings: Settings?

    public init(name: String,
                schemes: [Scheme] = [],
                settings: Settings? = nil,
                targets: [Target] = []) {
        self.name = name
        self.schemes = schemes
        self.targets = targets
        self.settings = settings
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
//                      settings: Settings(base: [:]),
//                      targets: [
//                          Target(name: "{{NAME}}",
//                                 platform: .iOS,
//                                 product: .app,
//                                 bundleId: "com.xcodepm.{{NAME}}",
//                                 infoPlist: "Info.plist",
//                                 dependencies: [
//                                     /* Target dependencies can be defined here */
//                                     /* .framework(path: "framework") */
//                                 ],
//                                 settings: nil,
//                                 buildPhases: [
//
//                                     .sources([.sources("./Sources/**/*.swift")]),
//                                     /* Other build phases can be added here */
//                                     /* .resources([.include(["./Resousrces /**/ *"])]) */
//                                ]),
//                    ])
// }
