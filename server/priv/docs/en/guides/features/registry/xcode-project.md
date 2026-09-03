---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode project {#xcode-project}

To add packages using the registry in your Xcode project, use the default Xcode UI. You can search for packages in the registry by clicking on the `+` button in the `Package Dependencies` tab in Xcode. If the package is available in the registry, you will see the `tuist.dev` registry in the top right:

![Adding package dependencies](/images/guides/features/build/registry/registry-add-package.png)

## Resolving source control packages {#resolving-source-control-packages}

Packages that are declared with a source control URL, such as the transitive dependencies of the packages you add, are resolved from source control by default. `tuist registry setup` and `tuist registry login` configure Xcode to resolve them from the registry instead by writing the following user default:

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

Xcode then resolves a source control package from the registry whenever a registry equivalent exists, and falls back to source control when it doesn't.

> [!NOTE]
> This is a per-machine Xcode preference and not a project setting, so committing the registry configuration file doesn't share it with the rest of your team. Every developer needs to run `tuist registry setup` or `tuist registry login` once on their machine. The preference then applies to all Xcode projects on that machine.
