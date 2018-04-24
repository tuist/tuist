import ProjectDescription

let project = Project(name: "xcbuddy",
                      schemes: [
                          /* Project schemes are defined here */
                          Scheme(name: "xcbuddy",
                                 shared: true,
                                 buildAction: BuildAction(targets: ["xcbuddy"])),
                      ],
                      settings: Settings(base: [:],
                                         debug: Configuration(settings: [:],
                                                              xcconfig: "Debug.xcconfig")),
                      targets: [
                          Target(name: "xcbuddy",
                                 platform: .ios,
                                 product: .app,
                                 bundleId: "com.xcbuddy.xcbuddy",
                                 infoPlist: "Info.plist",
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "/path/framework.framework") */
                                 ],
                                 settings: nil,
                                 buildPhases: [
                                     .sources([.include(["./Sources/**/*.swift"])]),
                                     /* Other build phases can be added here */
                                     /* .resources([.include(["./Resousrces /**/ *"])]) */
                          ]),
])
