# Synthesized files

Learn how Tuist synthesizes code and resources at generation-time

## Overview

### Target resources

Xcode projects support adding resources to targets. However, they present teams with a few challenges, specially when working with a modular project where sources and resources are often moved around:

- **Inconsistent runtime access**: Where the resources end up in the final product and how you access them depends on the target product. For example, if your target represents an application, the resources are copied to the application bundle. This leads to code to access the resources that makes assumptions on the bundle structure, which is not ideal because it makes the code harder to reason about and the resources to move around.
- **Products that don't support resources**: There are certain products like static libraries that are not bundles and therefore don't support resources. Because of that, you either have to resort to a different product type, for example frameworks, that might add some overhead on your project or app. For example, static frameworks will be linked statically to the final product, and a build phase is required to only copy the resources to the final product. Or dynamic frameworks, where Xcode will copy both the binary and the resources into the final product, but it'll increase the startup time of your app because the framework needs to be loaded dynamically.
- **Pone to runtime errors**: Resources are identified by their name and extension (strings). Therefore, a typo in any of those will lead to a runtime error when trying to access the resource. This is not ideal because it's not caught at compile time and might lead to crashes in release.

Tuist solves the problems above by **synthesizing a unified interface to access bundles and resources** that abstracts away the implementation details.

> Important: Even though accessing resources through the Tuist-synthesized interface is not mandatory, we recommend it because it makes the code easier to reason about and the resources to move around.

### Synthesized resources

Tuist provides interfaces to declare the content of files such as `Info.plist` or entitlements in Swift.
This is useful to ensure consistency across targets and projects,
and leverage the compiler to catch issues at compile time.
You can also come up with your own abstractions to model the content and share it across targets and projects.

When your project is generated,
Tuist will synthesize the content of those files and write them into the `Derived` directory relative to the directory containing the project that defines them.

> Note: We recommend adding the `Derived` directory to the `.gitignore` file of your project.

### Synthesized bundle accessor

Tuist synthesizes an interface to access the bundle that contains the target resources.

##### Swift

The target will contain an extension of the `Bundle` type that exposes the bundle:

```swift
let bundle = Bundle.module
```

##### Objective-C

In Objective-C, you'll get an interface `{Target}Resources` to access the bundle:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> Tip: If a target product, for example a library, doesn't support resources, Tuist will include the resources in a target of product type `bundle` ensuring that it ends up in the final product and that the interface points to the right bundle.

### Synthesized resource accessors

Resources are identified by their name and extension using strings. This is not ideal because it's not caught at compile time and might lead to crashes in release. To prevent that, Tuist integrates [SwiftGen](https://github.com/SwiftGen/SwiftGen) into the project generation process to synthesize an interface to access the resources. Thanks to that, you can confidently access the resources leveraging the compiler to catch any issues.

Tuist includes [templates](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates) to synthesize accessors for the following resource types by default:

| Resource type | Synthesized file |
| --- | ---- |
| Images and colors | `Assets+{Target}.swift` |
| Strings | `Strings+{Target}.swift` |
| Plists | `{NameOfPlist}.swift` |
| Fonts | `Fonts+{Target}.swift` |
| Files | `Files+{Target}.swift` |

> Note: You can disable the synthesizing of resource accessors in a per-project basis by passing the `disableSynthesizedResourceAccessors` option to the project options.

#### Custom templates

If you want to provide your own templates to synthesize accessors to other resource types,
which must be supported by [SwiftGen](https://docs.old.tuist.io/guides/resources),
you can create them at `Tuist/ResourceSynthesizers/{name}.stencil`,
where the name is the camel-case version of the resource.

| Resource | Template name |
| --- | --- |
| strings | `Strings.stencil` |
| assets | `Assets.stencil` |
| plists | `Plists.stencil` |
| fonts | `Fonts.stencil` |
| coreData | `CoreData.stencil` |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json | `JSON.stencil` |
| yaml | `YAML.stencil` |
| files | `Files.stencil` |

If you want to configure the list of resource types to synthesize accessors for,
you can use the `Project.resourceSynthesizers` property passing the list of resource synthesizers you want to use:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

<!-- TODO: Reference this page when writing the documentation for plugins >