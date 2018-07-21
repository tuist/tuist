# Initialize your project

After installing *xpm* the first step is creating a project. *xpm* comes with a very useful `init` command that helps you bootstrap a new project:

```bash
xpm init
```

You can specify the platform and the type of project you'd like to create.

The command generates a `Project.swift` and some files that are required for your project to compile, like an `Info.plist` file. The `Project.swift` file, also known as "manifest", is the file where you define the structure of your project. If you have used the Swift Package Manager before, it's the equivalent to the Swift Package Manager, but it contains the definition of a project instead:

```swift
import ProjectDescription

let project = Project(name: "MyProject",
            schemes: [
                /* Project schemes are defined here */
                Scheme(name: "documentation",
                        shared: true,
                        buildAction: BuildAction(targets: ["documentation"])),
            ],
            settings: Settings(base: [:]),
            targets: [
                Target(name: "MyProject",
                        platform: .iOS,
                        product: .app,
                        bundleId: "com.xcodepm.MyProject",
                        infoPlist: "Info.plist",
                        dependencies: [
                            /* Target dependencies can be defined here */
                            /* .framework(path: "framework") */
                        ],
                        settings: nil,
                        buildPhases: [
                          
                            .sources([.sources("./Sources/*")]),
                            /* Other build phases can be added here */
                            /* .resources([.include(["./Resources/**/*"])]) */
                      ]),
          ])
```

The `Project` model has a structure similar to the Xcode's. Let's analyze each of the properties:
- **Schemes:** It contains your project schemes. Each scheme has a name, whether it's shared, and some actions.
- **Settings:** It defines the project settings. The `Settings` model supports passing the settings as a dictionary and also as references to `.xcconfig` files.
- **Targets:** They represent the targets of your project.

### Target
A Target represents a Xcode project target so its attributes are also similar:

- **Name:** The target name.
- **Platform:** The platform your target product is for. *xpm* automatically configures the target build settings with the right SDK root path, and supported platform.
- **Bundle Identifier:** The target bundle identifier.
- **Info Plist:** A reference to the target info.plist. All references to files in your project definition need to be relative. We discourage using absolute paths.
- **Build phases:** Contain the build target build phases. You'll find the same types of build phases with exception of the frameworks linking. We'll talk more about why, and how *xpm* in the [dependencies section](/basic/dependencies).

### Generating the Xcode project

The next step after initializing the project manfiest is generating the Xcode project to start working on our app. Run the following command in your terminal:

```
xpm generate
```

It'll generate a Xcode workspace and project in the same directory. The name of the project and workspace matches the name specified in the `Project.swift`. If your project doesn't have dependencies you can open the Xcode project. However, most of the times you'll have dependencies defined with projects in other folders. In those cases you should use the workspace instead, because it includes the other projects your project depends on.

If you open the workspace, there should be two targets:

- The target that was defined in the `Project.swift`.
- A target named `MyProjectDescription`.

The latter, is a target that includes the `Project.swift`. Here's one of the great things of using Swift as the language for defining Xcode projects, you can safely define your projects using Xcode. If you make a typo or you don't know the project structure Xcode will complain and tell you how to fix it.
