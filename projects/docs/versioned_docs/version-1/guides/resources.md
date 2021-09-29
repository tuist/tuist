---
title: Accessing resources
slug: '/guides/resources'
description: 'In this page documents how Tuist synthesizes accessors for resources to provide an interface that is consistent across all target products (e.g. framework. library).'
---

Depending on the target product (e.g. app, framework), resources are accessed differently.
For example, if we are trying to get an image that is part of an app target, we get the image from the `Bundle.main`.
Conversely, if the image is part of a framework, we access it from the `Bundle` that represents the framework, `Bundle(for: FrameworkClass.self).resourceURL`.
Having an **inconsistent interface** for accessing resources complicates moving code and resources around.

Moreover,
as you might know,
libraries can't contain resources - only frameworks can.
On iOS,
this often leads projects to use dynamic frameworks instead of static libraries,
and in some cases,
add custom build phases that copy resources from dependencies into the final product (app).
Resorting to this setup is not ideal because it introduces side effects, complicates the maintenance of the project, and makes the setup hard to reason about.

### A consistent way for accessing resources

Tuist solves this by generating a `Bundle` extension for accessing the right bundle depending on the type of target.
For example, given a target framework `MyFeature`, you'll be able to get the right bundle with:

```swift
let bundle = Bundle.module
```

Furthermore, we support defining resources in products that don't support it (e.g. libraries). For those, we generate an associated bundle target (e.g. `MyFeatureResources.bundle`) that contains all the resources. The bundle ends up being copied into the final product bundle that contains compiled target.

:::note Strongly recommended
Accessing the resources this way is not mandatory, yet we recommend it strongly. It'll ease making changes in your project like turning a library into a framework.
:::

#### Objective-C

Tuist also synthesizes accessors for Objective-C.
In this case, the Bundle needs to be accessed using the target name to avoid name conflicts:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

### Synthesized Resource Interface Accessors

Accessing images, strings and other resources with String-based APIs gets messy real fast, which is why lots of teams
have opted to use [SwiftGen](https://github.com/SwiftGen/SwiftGen) or some other code generator.

This is why we think it is a great opportunity to integrate [SwiftGen](https://github.com/SwiftGen/SwiftGen) into tuist,
so teams can use it out of the box without having to set it up themselves!

So, how does one synthesize the resource interface accessors? It's simple, you just add `resources` to your `Target`
and define the appropriate `ResourceSynthesizers` in `Project` (more on that below).

It generates code that uses tuist's aforementioned bundle accessor, so you can use it safely in your libraries, too.

Currently, tuist has templates for these types of resources with the following interface names and files:

- Assets (images and colors) {TargetName}Assets `Assets+{TargetName}.swift`
- Strings {TargetName}Assets `Strings+{TargetName}.swift`
- Plists {NameOfPlist} `{NameOfPlist}.swift`
- Fonts `Fonts+{TargetName}.swift`

So, for example if you have a target `MyFramework` with the following resources:

- Assets.xcassets
  - image1
  - image2
- Environment.plist
  - myKey
- Fonts
  - SF-Pro-Display-Bold.otf
  - SF-Pro-Display-Heavy.otf

```swift
// Accessing Asset Catalog Images
let image1 = MyFrameworkAssets.myImage1
let image2 = MyFrameworkAssets.myImage2

// Accessing Plist Key values
let myKeyValue = Environment.myKey

// Accessing Fonts
let sfProBoldFont = MyFrameworkFontFamily.SFProDisplay.bold
let sfProHeavyFont = MyFrameworkFontFamily.SFProDisplay.heavy
```

These templates are used by default via a parameter in `Project`, `resourceSynthesizers`. But there is a lot that you can customize here 👇

## ResourceSynthesizers

Resource synthesizers support all parsers that [SwiftGen](https://github.com/SwiftGen/SwiftGen) offers.

That means:

- `strings`
- `assets`
- `plists`
- `fonts`
- `coreData`
- `interfaceBuilder`
- `json`
- `yaml`

For `strings`, `plists`, `fonts`, and `assets` there are templates offered by tuist, to initialize eg. strings resource synthesizer (as described above):

```swift
.strings()
```

:::note Default templates
Default templates used by Tuist can be examined [here](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates).
:::

You can also use a local template. Just add it to `Tuist/ResourceSynthesizers/{name}.stencil` where name is derived from the resource and then use the default initializer (e.g. `plists()` for Plists). Here you have listed all of the name mappings:

- `strings` => `Strings.stencil`
- `assets` => `Assets.stencil`
- `plists` => `Plists.stencil`
- `fonts` => `Fonts.stencil`
- `coreData` => `CoreData.stencil`
- `interfaceBuilder` => `InterfaceBuilder.stencil`
- `json` => `JSON.stencil`
- `yaml` => `YAML.stencil`

If a plugin offers a resource synthesizer template, you can also do:

```swift
.json(plugin: "CustomPlugin")
```

These initializers have pre-defined parser and extensions to determine for which resources it should do the synthesization.

If you need something more custom, eg. Lottie template that uses `.json` parser and finds resources with `.lottie` extension, you can do:

```swift
.custom(
  name: "Lottie",
  parser: .json,
  extensions: ["lottie"]
)
```

where the template should again be present at `Tuist/ResourceSynthesizers/Lottie.stencil`.

The same can be done for a plugin:

```swift
.custom(
  plugin: "CustomPlugin",
  parser: .json,
  extensions: ["lottie"],
  resourceName: "Lottie"
)
```

To ensure that it works well with our cache feature, it's not possible to run it from a build path.

If you don't want to use resource synthesizers at all, you can just pass empty array: `resourceSynthesizers: []` in `Project` initializer.
