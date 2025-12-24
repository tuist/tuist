---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Xcode project {#xcode-project}

To add packages using the registry in your Xcode project, use the default Xcode
UI. You can search for packages in the registry by clicking on the `+` button in
the `Package Dependencies` tab in Xcode. If the package is available in the
registry, you will see the `tuist.dev` registry in the top right:

![Adding package
dependencies](/images/guides/features/build/registry/registry-add-package.png)

::: info
<!-- -->
Xcode currently doesn't support automatically replacing source control packages
with their registry equivalents. You will need to manually remove the source
control package and add the registry package to speed up the resolution.
<!-- -->
:::
