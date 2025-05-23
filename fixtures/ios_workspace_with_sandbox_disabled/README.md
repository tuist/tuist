# iOS workspace with sandbox disabled

An example of workspace and project manifests that access the file system, and therefore require the sandbox to be disabled.

Tuist commands must be run with the working directory set to the root of this fixture. Otherwise the workspace and project manifests will be unable to locate `config.json`.

*Note: disabling the sandbox is discouraged and should only be used if absolutely necessary.*
