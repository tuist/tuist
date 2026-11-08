# TuistXcodeProjectOrWorkspacePathLocator

Honor `TUIST_WORKSPACE_PATH` through `Environment.current.workspacePath` before discovery. Otherwise prefer `.xcworkspace` over `.xcodeproj`, falling back to a project when no workspace exists.
