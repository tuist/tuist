---
title: Config.swift
slug: '/manifests/config'
description: This page documents how to use the Config manifest file to configure Tuist's functionalities globally.
---

Tuist can be configured through a `Config.swift` manifest.
When Tuist is executed, it traverses up the directories to find a `Tuist` directory that contains a `Config.swift` file.
Defining a configuration manifest **is not required** but recommended to ensure a consistent behavior across all the projects that are part of the repository.

The example below shows a project that has a global `Config.swift` file that will be used when Tuist is run from any of the subdirectories:

```bash
/.git
.gitignore
/Tuist/Config.swift # Configuration manifest
/Framework/Project.swift
/App/Project.swift
```

That way, when Tuist runs in any of the subdirectories, it'll use the root configuration.

The structure is similar to the project manifest. We need to create a root variable, `config` of type `Config`:

```swift
import ProjectDescription

let config = Config(
    compatibleXcodeVersions: ["10.3"],
    swiftVersion: "5.4.0",
    generationOptions: [
        .xcodeProjectName("SomePrefix-\(.projectName)-SomeSuffix"),
        .organizationName("Tuist"),
        .developmentRegion("de")
    ]
)
```

### Config

It allows configuring Tuist and share the configuration across several projects.

| Property                  | Description                                                                                                                    | Type                                                    | Required | Default |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------- | -------- | ------- |
| `compatibleXcodeVersions` | Set the versions of Xcode that the project is compatible with.                                                                 | [`CompatibleXcodeVersions`](#compatible-xcode-versions) | No       | `.all`  |
| `swiftVersion`            | The specified version of Swift that will be used by Tuist. When `nil` is passed then Tuist will use the environment’s version. | Version                                                 | No       |         |
| `generationOptions`       | Options to configure the generation of Xcode projects.                                                                         | [`[GenerationOption]`](#generationoption)               | No       | `[]`    |

### Compatible Xcode versions

This object represents the versions of Xcode the project is compatible with. If a developer tries to generate a project and its selected Xcode version is not compatible with the project, Tuist will yield an error:

| Case                               | Description                                                                                                                    |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `.all`                             | The project is compatible with any version of Xcode.                                                                           |
| `.exact(Version)`                  | The project is compatible with a specific version of Xcode.                                                                    |
| `.upToNextMajor(Version)`          | The project is compatible with any version of Xcode from the specified version up to but not including the next major version. |
| `.upToNextMinor(Version)`          | The project is compatible with any version of Xcode from the specified version up to but not including the next minor version. |
| `.list([CompatibleXcodeVersions])` | The project is compatible with a list of Xcode versions.                                                                       |

:::note ExpressibleByArrayLiteral and ExpressibleByStringLiteral
Note that 'Version' can also be initialized with a string that represents the supported Xcode version.
Note that 'CompatibleXcodeVersions' can also be initialized with a string or array of strings that represent the supported Xcode versions.
:::

### GenerationOption

Generation options allow customizing the generation of Xcode projects.

| Case                                           | Description                                                                                                                                                                                                                                                                                                                                                        |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.xcodeProjectName(TemplateString)`            | Customize the name of the generated .xcodeproj.                                                                                                                                                                                                                                                                                                                    |
| `.organizationName(String)`                    | Customize the organization name of the generated .xcodeproj.                                                                                                                                                                                                                                                                                                       |
| `.developmentRegion(String)`                   | Customize the development region of the generated .xcodeproj. The default development region is `en`.                                                                                                                                                                                                                                                              |
| `.autogeneratedSchemes(AutogenerationOptions)` | Enable or disable automatic generation of schemes. If enabled, options to configure test targets can be passed in via an instance of `TestingOptions`. Not setting any value for `autogeneratedSchemes` is equivalent to `.autogeneratedSchemes(.enabled([]))` (i.e. schemes are autogenerated with default test config).                                          |
| `.disableShowEnvironmentVarsInScriptPhases`    | Suppress logging of environment in Run Script build phases.                                                                                                                                                                                                                                                                                                        |
| `.disableSynthesizedResourceAccessors`         | Do not automatically synthesize resource accessors (assets, localized strings, etc.).                                                                                                                                                                                                                                                                              |
| `.enableCodeCoverage(CodeCoverageMode)`        | Enable code coverage for auto generated schemes.                                                                                                                                                                                                                                                                                                                   |
| `.templateMacros(IDETemplateMacros)`           | Apply IDE Template macros to your project.                                                                                                                                                                                                                                                                                                                         |
| `.resolveDependenciesWithSystemScm`            | Resolve SPM dependencies using your system's SCM credentials, instead of Xcode accounts.                                                                                                                                                                                                                                                                           |
| `.disablePackageVersionLocking`                | Disables locking Swift packages. This can speed up generation but does increase risk if packages are not locked in their declarations.                                                                                                                                                                                                                             |
| `.disableBundleAccessors`                      | Disables generating Bundle accessors.                                                                                                                                                                                                                                                                                                                              |
| `.lastXcodeUpgradeCheck(Version)`              | Allows to suppress warnings in Xcode about updates to recommended settings added in or below the specified Xcode version. The warnings appear when Xcode version has been upgraded. It is recommended to set the version option to Xcode's version that is used for development of a project, for example `.lastUpgradeCheck(Version(13, 0, 0))` for Xcode 13.0.0. |

### TemplateString

Allows a string with interpolated properties to be specified. For example, `Prefix-\(.projectname)`.

| Case           | Description                      |
| -------------- | -------------------------------- |
| `.projectName` | The name of the current project. |

### CodeCoverageMode

Allows you to define what targets will be enabled for code coverage data gathering.

| Case                          | Description                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `.all`                        | Gather code coverage data for all targets in workspace.                                          |
| `.relevant`                   | Enable code coverage for targets that have enabled code coverage in any of schemes in workspace. |
| `.targets([TargetReference])` | Gather code coverage for specified target references.                                            |

### TestingOptions

Allows you to define which testing options are applied on autogenerated schemes. An empty list of options will default to `false` for both options.

| Option                     | Description                                       |
| -------------------------- | ------------------------------------------------- |
| `.parallelizable`          | Enables parallel test execution (where possible). |
| `.randomExecutionOrdering` | Randomizes order of execution of tests            |
