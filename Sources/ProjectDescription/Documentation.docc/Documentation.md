# ``ProjectDescription``

Define project and workspace Tuist manifests.

## Overview

The `ProjectDescription` framework contains different types that can be used to configure your app (or framework) project structure.

A project may consists of sources files, resources, configurations and a manifest file.
The Tuist project manifest file, called _Project.swift_, defines the project content (see ``Project`` for more).

Multiple _Project.swift_ manifests can be collected under a Tuist workspace manifest,
called _Workspace.swift_ (see ``Workspace`` for more).

A _Dependencies.swift_ manifests defines your external dependencies
from Swift Package Manager, Carthage or Cocoapods (see ``Dependencies`` for more).

``Plugin`` and other configurations are supported under the _Config.swift_ manifest (see ``Config`` for more).

## Topics

### Project

- ``Project``
- ``TestingOptions``
- ``ResourceSynthesizer``

### Target

- ``Target``
- ``Platform``
- ``Product``
- ``DeploymentTarget``
- ``DeploymentDevice``
- ``TargetDependency``
- ``TargetReference``
- ``SDKStatus``
- ``SDKType``

### Scheme

- ``Scheme``
- ``AnalyzeAction``
- ``ArchiveAction``
- ``BuildAction``
- ``ProfileAction``
- ``RunAction``
- ``RunActionOptions``
- ``TestAction``
- ``TestActionOptions``
- ``TestableTarget``
- ``ExecutionAction``
- ``LaunchArgument``
- ``Arguments``
- ``SchemeDiagnosticsOption``
- ``SchemeLanguage``
- ``Environment``

### Dependencies

- ``Dependencies``
- ``CarthageDependencies``
- ``SwiftPackageManagerDependencies``
- ``Package``
- ``Version``

### Workspace

- ``Workspace``

### Config

- ``Config``
- ``Plugin``
- ``PluginLocation``
- ``Cloud``
- ``Cache``
- ``Settings``
- ``DefaultSettings``
- ``SettingValue``
- ``SettingsDictionary``
- ``Configuration``
- ``ConfigurationName``
- ``SwiftCompilationMode``
- ``SwiftOptimizationLevel``
- ``DebugInformationFormat``
- ``CompatibleXcodeVersions``

### Files

- ``InfoPlist``
- ``SourceFilesList``
- ``SourceFileGlob``
- ``ResourceFileElements``
- ``ResourceFileElement``
- ``Headers``
- ``FileList``
- ``FileListGlob``
- ``FileElement``
- ``CoreDataModel``
- ``FileCodeGen``
- ``Path``

### Build phases

- ``CopyFilesAction``
- ``TargetScript``

### Template

- ``Template``
- ``TemplateString``
- ``FileHeaderTemplate``
