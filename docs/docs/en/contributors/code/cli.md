---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

Source: [github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) and [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## What it is for {#what-it-is-for}

The CLI is the heart of Tuist. It handles project generation, automation workflows (test, run, graph, and inspect), and provides the interface to the Tuist server for features like authentication, cache, insights, previews, registry, and selective testing.

## How to contribute {#how-to-contribute}

### Requirements {#requirements}

- macOS 14.0+
- Xcode 26+

### Set up locally {#set-up-locally}

- Clone the repository: `git clone git@github.com:tuist/tuist.git`
- Install Mise and run `mise install`
- Install Tuist dependencies: `tuist install`
- Generate the workspace: `tuist generate`

The generated project opens automatically. If you need to reopen it later, run `open Tuist.xcworkspace`.

::: info XED .
<!-- -->
If you try to open the project using `xed .`, it will open the package, not the Tuist-generated workspace. Use `Tuist.xcworkspace`.
<!-- -->
:::

### Run Tuist {#run-tuist}

#### From Xcode {#from-xcode}

Edit the `tuist` scheme and set arguments like `generate --no-open`. Set the working directory to the project root (or use `--path`).

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
The CLI depends on `ProjectDescription` being built. If it fails to run, build the `Tuist-Workspace` scheme first.
<!-- -->
:::

#### From the terminal {#from-the-terminal}

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Or via Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
