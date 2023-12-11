# Installation

Learn how to install Tuist in your environment

## Overview

Tuist is a [command-line application](https://en.wikipedia.org/wiki/Command-line_interface) that you need to install in your environment before you can use it. The installation consists of an executable, dynamic frameworks, and a set of resources (for example, templates). Although you could manually build Tuist from the sources, we recommend using one of the following installation methods to ensure a valid installation.

### Recommended: [rtx](https://github.com/jdx/rtx)

Tuist defaults to [rtx](https://github.com/jdx/rtx) as a tool to deterministically manage and activate versions of Tuist.
If you don't have it installed on your system,
you can use any of these [installation methods](https://github.com/jdx/rtx#installation).
Remember to add the suggested line to your shell, which will ensure the right version is activated when you choose a Tuist project directory in your terminal session.

> Note: rtx is recommended over alternatives like [Homebrew](https://brew.sh) because it supports scoping and activating versions to directories, ensuring every environment uses the same version of Tuist deterministically.

Once installed, you can install Tuist through any of the following commands:


```bash
# Tuist
rtx install tuist@3.36.0      # Install a specific version number
rtx install tuist@3           # Install a fuzzy version number
rtx use tuist@3.36.0          # Use tuist-3.36.0 in the current project
rtx use -g tuist@3.36.0       # Use tuist-3.36.0 as the global default
rtx install tuist             # Install the current version specified in .tool-versions/.rtx.toml
rtx use tuist@latest          # Use the latest tuist in the current directory
rtx use -g tuist@system       # Use the system's tuist as the global default

# Tuist Cloud (For users of Tuist Cloud)
# Note: You need to install one OR the other, not both
rtx install tuist-cloud@3.36.0
rtx install tuist-cloud@3
rtx use tuist-cloud@3.36.0   
rtx use -g tuist-cloud@3.36.0       # Use tuist-cloud-3.36.0 as the global default
rtx install tuist-cloud             # Install the current version specified in .tool-versions/.rtx.toml
rtx use tuist-cloud@latest          # Use the latest tuist-cloud in the current directory
rtx use -g tuist-cloud@system       # Use the system's tuist-cloud as the global default
```

> Tip: We recommend using `rtx use` in your Tuist projects to pin the version of Tuist across environments. The command will create a `.tool-versions` file containing the version of Tuist.

> Important: **Tuist Cloud** (<doc:Tuist-Cloud---What>), a closed-source extension of Tuist with optimizations such as binary caching and selective testing, is distributed as a different asdf plugin, tuist-cloud. Note that by using it, you agree to the [Tuist Cloud Terms of Service](https://tuist.io/terms/).

### Alternative: Homebrew

If version pinning across environments is not a concern for you,
you can install Tuist using [Homebrew](https://brew.sh) and [our formulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install tuist
brew install tuist@3.36.0
brew install tuist-cloud # If you are a Tuist Cloud user
```
