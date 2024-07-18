---
title: Templates
description: Learn how to create and use templates in Tuist to generate code in your projects.
---

# Templates

In projects with an established architecture, developers might want to bootstrap new components or features that are consistent with the project. With `tuist scaffold` you can generate files from a template. You can define your own templates or use the ones that are vendored with Tuist. These are some scenarios where scaffolding might be useful:

- Create a new feature that follows a given architecture: `tuist scaffold viper --name MyFeature`.
- Create new projects: `tuist scaffold feature-project --name Home`

> [!NOTE] NON-OPINIONATED
> Tuist is not opinionated about the content of your templates, and what you use them for. They are only required to be in a specific directory.

## Defining a template

To define templates, you can run [`tuist edit`](/guides/develop/projects/editing) and then create a directory called `name_of_template` under `Tuist/Templates` that represents your template. Templates need a manifest file, `name_of_template.swift` that describes the template. So if you are creating a template called `framework`, you should create a new directory `framework` at `Tuist/Templates` with a manifest file called `framework.swift` that could look like this:


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

## Using a template

After defining the template, we can use it from the `scaffold` command:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> Since platform is an optional argument, we can also call the command without the `--platform macos` argument.

If `.string` and `.files` don't provide enough flexibility, you can leverage the [Stencil](https://stencil.fuller.li/en/latest/) templating language via the `.file` case. Besides that, you can also use additional filters defined here.

Using string interpolation, `\(nameAttribute)` above would resolve to `{{ name }}`. If you'd like to use Stencil filters in the template definition, you can use that interpolation manually and add any filters you like. For example, you might use `{ { name | lowercase } }` instead of `\(nameAttribute)` to get the lowercased value of the name attribute.

You can also use `.directory` which gives the possibility to copy entire folders to a given path.

> [!TIP] PROJECT DESCRIPTION HELPERS
> Templates support the use of [project description helpers](/guides/develop/projects/code-sharing) to reuse code across templates.