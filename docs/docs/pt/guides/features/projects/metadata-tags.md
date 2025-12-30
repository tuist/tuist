---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Metadata tags {#metadata-tags}

As projects grow in size and complexity, working with the entire codebase at
once can become inefficient. Tuist provides **metadata tags** as a way to
organize targets into logical groups and focus on specific parts of your project
during development.

## What are metadata tags? {#what-are-metadata-tags}

Metadata tags are string labels that you can attach to targets in your project.
They serve as markers that allow you to:

- **Group related targets** - Tag targets that belong to the same feature, team,
  or architectural layer
- **Focus your workspace** - Generate projects that include only targets with
  specific tags
- **Optimize your workflow** - Work on specific features without loading
  unrelated parts of your codebase
- **Select targets to keep as sources** - Choose which group of targets you'd
  like to keep as sources when caching

Tags are defined using the `metadata` property on targets and are stored as an
array of strings.

## Defining metadata tags {#defining-metadata-tags}

You can add tags to any target in your project manifest:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## Focusing on tagged targets {#focusing-on-tagged-targets}

Once you've tagged your targets, you can use the `tuist generate` command to
create a focused project that includes only specific targets:

### Focus by tag

Use the `tag:` prefix to generate a project with all targets matching a specific
tag:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Focus by name

You can also focus on specific targets by name:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### How focus works

When you focus on targets:

1. **Included targets** - The targets matching your query are included in the
   generated project
2. **Dependencies** - All dependencies of the focused targets are automatically
   included
3. **Test targets** - Test targets for the focused targets are included
4. **Exclusion** - All other targets are excluded from the workspace

This means you get a smaller, more manageable workspace that contains only what
you need to work on your feature.

## Tag naming conventions {#tag-naming-conventions}

While you can use any string as a tag, following a consistent naming convention
helps keep your tags organized:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

Using prefixes like `feature:`, `team:`, or `layer:` makes it easier to
understand the purpose of each tag and avoid naming conflicts.

## Using tags with project description helpers {#using-tags-with-helpers}

You can leverage
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink> to standardize how tags are applied across your project:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

Then use it in your manifests:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## Benefits of using metadata tags {#benefits}

### Improved development experience

By focusing on specific parts of your project, you can:

- **Reduce Xcode project size** - Work with smaller projects that are faster to
  open and navigate
- **Speed up builds** - Build only what you need for your current work
- **Improve focus** - Avoid distractions from unrelated code
- **Optimize indexing** - Xcode indexes less code, making autocompletion faster

### Better project organization

Tags provide a flexible way to organize your codebase:

- **Multiple dimensions** - Tag targets by feature, team, layer, platform, or
  any other dimension
- **No structural changes** - Add organizational structure without changing
  directory layout
- **Cross-cutting concerns** - A single target can belong to multiple logical
  groups

### Integration with caching

Metadata tags work seamlessly with
<LocalizedLink href="/guides/features/cache">Tuist's caching features</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Best practices {#best-practices}

1. **Start simple** - Begin with a single tagging dimension (e.g., features) and
   expand as needed
2. **Be consistent** - Use the same naming conventions across all your manifests
3. **Document your tags** - Keep a list of available tags and their meanings in
   your project's documentation
4. **Use helpers** - Leverage project description helpers to standardize tag
   application
5. **Review periodically** - As your project evolves, review and update your
   tagging strategy

## Related features {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Code sharing</LocalizedLink> - Use project description helpers to standardize tag
  usage
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> - Combine
  tags with caching for optimal build performance
- <LocalizedLink href="/guides/features/selective-testing">Selective testing</LocalizedLink> - Run tests only for changed targets
