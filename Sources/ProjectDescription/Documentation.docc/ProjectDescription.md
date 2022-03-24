# ``ProjectDescription``

A framework that defines Tuist's manifests, like projects or workspaces.

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

### Defining Manifests

- ``Project``
- ``Workspace``

### Managing Dependencies

- ``Dependencies``

### Plugin and Configuration

- ``Config``

### Scaffolding

- ``Template``
