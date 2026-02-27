# ``ProjectDescription``

@Metadata {
    @DisplayName("ProjectDescription")
    @TitleHeading("Documentation Portal")
    @PageColor(blue)
}

The Swift DSL for defining Tuist manifest files.

## Overview

`ProjectDescription` provides the types and APIs you use in Tuist manifest files (`Project.swift`, `Workspace.swift`, `Tuist.swift`, and others) to describe your Xcode projects declaratively. Instead of managing `.xcodeproj` files by hand, you express your project structure, targets, dependencies, schemes, and settings in Swift, and Tuist generates the Xcode projects for you.

## Topics

### Manifests

- ``Project``
- ``Workspace``
- ``Tuist``

### Targets and Products

- ``Target``
- ``Product``
- ``Executable``
- ``TargetReference``
- ``TargetMetadata``
- ``TargetQuery``
- ``MergedBinaryType``

### Dependencies

- ``TargetDependency``
- ``Package``
- ``PackageSettings``

### Schemes and Actions

- ``Scheme``
- ``BuildAction``
- ``RunAction``
- ``TestAction``
- ``ArchiveAction``
- ``ProfileAction``
- ``AnalyzeAction``
- ``ExecuteAction``
- ``TestableTarget``
- ``RunActionOptions``
- ``TestActionOptions``
- ``TestingOptions``
- ``SchemeDiagnosticsOptions``
- ``LaunchArgument``
- ``LaunchStyle``
- ``SimulatedLocation``
- ``ScreenCaptureFormat``
- ``SchemeLanguage``

### Build Settings and Configuration

- ``Settings``
- ``SettingsTransformers``
- ``ConfigurationName``
- ``BuildRule``
- ``BuildOrder``
- ``MetalOptions``
- ``CompatibleXcodeVersions``

### Resources and Files

- ``ResourceFileElements``
- ``ResourceFileElement``
- ``ResourceSynthesizer``
- ``FileElement``
- ``FileList``
- ``FileListGlob``
- ``CopyFilesAction``
- ``CopyFileElement``
- ``SourceFilesList``
- ``Headers``
- ``FileCodeGen``
- ``PrivacyManifest``
- ``CoreDataModel``
- ``OnDemandResourcesTags``

### Info.plist and Entitlements

- ``InfoPlist``
- ``Plist``
- ``Entitlements``
- ``FileHeaderTemplate``

### Platforms and Destinations

- ``Platform``
- ``Destination``
- ``PlatformCondition``
- ``PlatformFilter``
- ``DeploymentTargets``

### Paths and Environment

- ``Path``
- ``TemplateString``
- ``Environment``
- ``EnvironmentVariable``
- ``Arguments``
- ``Version``

### Scripts

- ``TargetScript``

### Plugins

- ``Plugin``
- ``PluginLocation``

### Project Options

- ``ProjectOptions``
- ``WorkspaceGenerationOptions``
- ``ConfigGenerationOptions``
- ``ConfigInstallOptions``
- ``ConfigInspectOptions``
- ``TuistXcodeProjectOptions``
- ``CacheOptions``
- ``CacheProfiles``

### Buildable Folders

- ``BuildableFolder``
- ``BuildableFolderException``
- ``BuildableFolderExceptions``

### Cloud

- ``Cloud``
