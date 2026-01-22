---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Install Tuist {#install-tuist}

The Tuist CLI consists of an executable, dynamic frameworks, and a set of
resources (for example, templates). Although you could manually build Tuist from
[the sources](https://github.com/tuist/tuist), **we recommend using one of the
following installation methods to ensure a valid installation.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
<!-- -->
Mise is a recommended alternative to [Homebrew](https://brew.sh) if you are a
team or organization that needs to ensure deterministic versions of tools across
different environments.
<!-- -->
:::

You can install Tuist through any of the following commands:

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

Note that unlike tools like Homebrew, which install and activate a single
version of the tool globally, **Mise requires the activation of a version**
either globally or scoped to a project. This is done by running `mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

You can install Tuist using [Homebrew](https://brew.sh) and [our
formulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
You can verify that your installation's binaries have been built by us by
running the following command, which checks if the certificate's team is
`U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
