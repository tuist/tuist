---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Registry {#registry}

As the number of dependencies grows, so does the time to resolve them. While other package managers like [CocoaPods](https://cocoapods.org/) or [npm](https://www.npmjs.com/) are centralized, Swift Package Manager is not. Because of that, SwiftPM needs to resolve dependencies by doing a deep clone of each repository, which can be time-consuming and takes up more memory than a centralized approach would. To address this, Tuist provides an implementation of the [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), so you can download only the commits you _actually need_. The packages in the registry are based on the [Swift Package Index](https://swiftpackageindex.com/) – if you can find a package there, the package is also available in the Tuist Registry. Additionally, the packages are distributed across the globe using an edge storage for minimum latency when resolving them.

## Usage {#usage}

Tuist Registry supports two modes of access:

### Unauthenticated Access (Default) {#unauthenticated-access}

This mode allows you to use the registry without authentication. It's the simplest way to get started and requires no account setup.

To set up the registry without authentication, run:

```bash
tuist registry setup
```

This command generates a registry configuration file. To ensure the rest of your team can access the registry, commit the generated file to your repository.

**Rate Limits:** Unauthenticated access has standard rate limits (1000 requests per minute).

### Authenticated Access (Higher Rate Limits) {#authenticated-access}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

This mode provides higher rate limits by authenticating with your Tuist account. Use this if you need more requests or are experiencing rate limit issues.

To set up the registry with account authentication, run:

```bash
tuist registry setup --authenticated
```

This command:
1. Generates a registry configuration file
2. Logs you into the registry with your account credentials

To ensure the rest of your team can access the registry with authentication:
1. Commit the generated configuration file to your repository
2. Have team members run `tuist registry login` to authenticate

**Rate Limits:** Authenticated access has no practical rate limits for normal usage.

Now you can access the registry! To resolve dependencies from the registry instead of from source control, continue reading based on your project setup:
- <LocalizedLink href="/guides/features/registry/xcode-project">Xcode project</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Generated project with the Xcode package integration</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">Generated project with the XcodeProj-based package integration</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Swift package</LocalizedLink>

To set up the registry on the CI, follow this guide: <LocalizedLink href="/guides/features/registry/continuous-integration">Continuous integration</LocalizedLink>.

### Package registry identifiers {#package-registry-identifiers}

When you use package registry identifiers in a `Package.swift` or `Project.swift` file, you need to convert the URL of the package to the registry convention. The registry identifier is always in the form of `{organization}.{repository}`. For example, to use the registry for the `https://github.com/pointfreeco/swift-composable-architecture` package, the package registry identifier would be `pointfreeco.swift-composable-architecture`.

::: info
<!-- -->
The identifier can't contain more than one dot. If the repository name contains a dot, it's replaced with an underscore.
For example, the `https://github.com/groue/GRDB.swift` package would have the registry identifier `groue.GRDB_swift`.
<!-- -->
:::
