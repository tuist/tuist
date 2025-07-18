---
title: Tuist 1.4.0 - Lint command, more verbose logs, and configuration of the project organization
category: "product"
tags: [tuist, release, swift, project generation, xcode, apple, '1.4.0']
excerpt: The just released version of Tuist, 1.4.0, adds support for printing more verbose logs, and configuring the Xcode organization.
author: pepicrft
---

In difficult times where 🦠 COVID-19 presented the world with an unprecedented challenge,
Tuist maintainers and contributors continue devoting their time to help companies scale up their Xcode projects.
All the effort that they put into the project is reflected in a new release that we are announcing in this blog post, 1.4.0.
Although there aren't major features shipping this time, there are small features and improvements that you might find handy for your projects.
Let's dive right into what those improvements are.

## Configure the organization name

As you probably know,
when you create a new project in Xcode,
one of the fields that you need to fill out is the name of the organization.
That information ends up codified in your projects
and Xcode uses it to create copyright headers when adding new files.

Until today,
configuring that in Tuist was not possible,
but thanks to [Sylvain](https://github.com/c0diq)'s [amazing contribution](https://github.com/tuist/tuist/pull/1062),
that's finally possible.

```swift
// It can be configured at the project level
let project = Project(organizationName: "Tuist")

// Or globaly in the config file
let config = Config(organizationName: "Tuist")
```

## Verbose argument

Despite our efforts to handle all possible scenarios in Xcode projects gracefully,
we may miss some.
The consequence of that is that developers get unexpected results that we need to debug and fix.
To make that work easier,
we [introduced support for a new argument](https://github.com/tuist/tuist/pull/1027), `--verbose`,
that configures the output to be more verbose.
When passed to any of the commands,
the output contains information that is useful to understand the issue and provide users with a solution as soon as possible.

## Lint command

As part of the project generation,
we lint your project definition to uncover errors that otherwise would cause compilation issues later on.
If developers wanted to run the linting logic without generating the project,
there was no option to do so.
Fortunately, that changes with Tuist 1.4.0 because it introduces [a new command](https://github.com/tuist/tuist/pull/1043) `tuist lint`.
You can read more about how it works on the [commands](https://docs.old.tuist.io/commands/linting/) documentation page.

If you are currently using Tuist,
we recommend you to set up a CI pipeline that runs that command for every commit.
That'll fail PRs immediately before `xcodebuild` starts compiling the project.
The developers will get faster feedback and therefore waste less time waiting for the build system to surface issues in the shape of compilation errors.

## TuistConfig.swift renamed to Config.swift

Since `TuistConfig.swift` is a file that contains configuration that is global to all the projects in the same directory and subdirectories,
we decided that it makes more sense to require it to be in a directory where other global files are _(e.g. project description helpers)_.
That directory is the root `/Tuist` directory.

For that reason, from Tuist 1.4.0 the file [is expected to be](https://github.com/tuist/tuist/pull/1083) under `/Tuist` and with the name `Config.swift` to avoid some naming redundancy.
Since this is a minor release,
and we follow [semantic versioning](https://semver.org/),
we made this change a non-breaking change.
In other words,
it does not break your current projects if you follow the old convention.
However,
we encourage you to move the file to the new directory and change its name.
That'll make the future adoption of major releases a seamless process.

## Website improvements

As you might have noticed,
the website looks a bit different than the last time you visited it.
That's because we gave it a facelift to have consistent and themeable styling.
That makes the website more accessible and more pleasant to navigate.
There's a tiny button at the top-right corner that you can use to adjust the theme to the one you find the most comfortable to your taste.
For those of you who are curious about how we achieved that so quickly while other website takes a lot of time to introduce theming,
we used the package [theme-ui](https://theme-ui.com/),
that provides a beautiful and concise abstraction for consistently styling [React](https://reactjs.org/) website.
If you are considering implementing a statically-generated website,
we strongly recommend the combo [GatsbyJS](https://www.gatsbyjs.org/) with theme-ui.
Once you know the basic building blocks,
creating a website becomes very straightforward.

## Bug fixes and improvements

- [Support](https://github.com/tuist/tuist/pull/1037) spaces in `TargetAction` for `PROJECT_DIR`.
- [Fix](https://github.com/tuist/tuist/pull/1081) compilation issues in the code example that is shown in the "Project description helpers" documentation.
- [Introduce descriptors](https://github.com/tuist/tuist/pull/1007) to remove side effects and IO during project generation to ease optimizations and make the process more deterministic.
- [Add a new TuistInsights](https://github.com/tuist/tuist/pull/1084) target to start working on a cloud-based feature to help teams make informed decisions on PRs based on collected insights.
