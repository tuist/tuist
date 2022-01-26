---
title: tuist scaffold
slug: '/commands/scaffold'
description: 'Learn how to use the scaffold command to generate files from a pre-defined template.'
---

In projects with an established architecture, developers might want to bootstrap new components or features that are consistent with the project.
With `tuist scaffold` you generate files, you can generate files from a template. You can define your own templates or use the ones that are vendored with Tuist. These are some **scenarios** where scaffolding might be useful:

- Create a new feature that follows a given architecture: `tuist scaffold viper --name MyFeature`.
- Create new projects: `tuist scaffold feature-project --name Home`

Tuist is not opinionated about the content of your templates, and what you use them for. They are only required to be in a specific directory.

### Defining a template

To define templates, you can run `tuist edit` and then create a directory called `name_of_template` under `Tuist/Templates` that represents your template. Templates need a manifest file, `name_of_template.swift` that describes the template. So if you are creating a template called `framework`, you should create a new directory `framework` at `Tuist/Templates` with a manifest file called `framework.swift` that could look like this:

```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

### Command

After defining the template, we can use it from the `scaffold` command:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

Since platform is an optional argument, we can also call the command without the `--platform macos` argument.

If `.string` and `.files` don't provide enough flexibility, you can leverage the [Stencil](https://github.com/stencilproject/Stencil) templating language via the `.file` case. Besides that, you can also use additional filters defined [here](https://github.com/SwiftGen/StencilSwiftKit#filters)

You can also use `.directory` which gives the possibility to copy entire folders to a given path.

Templates can import [project description helpers](guides/helpers.md). Just add `import ProjectDescriptionHelpers` at the top, and extract reusable logic into the helpers.
