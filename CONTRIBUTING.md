# Contribution guidelines

Contributors should read the sections in this document before contributing to the project.

## Mission

Tuist's mission is to simplify and facilitate the maintenance and interactions with large Xcode projects.

## Design principles

The project features should be designed meeting the following principles:

- **Aligned with Xcode conventions:** In order to facilitate the adoption and future moves from Tuist, features should be aligned with the Xcode conventions. CocoaPods is a good example of a project that doesn't follow this principle. The generated Pods project doesn't have a standard structure.
- **Zero environment assumptions:** Features shouldn't make assumptions about the environment. For example, if we need to call a tool from the feature, we shouldn't assume the tool will be available, unless we are quite certain about it. If we are not sure, we should check whether it exists, and if it doesn't, either trigger the installation process or let developer know about how to install it.
