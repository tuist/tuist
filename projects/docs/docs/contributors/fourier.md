---
title: Fourier
slug: /contributors/fourier
description: Learn about Fourier, Tuist's CLI tool to automate certain development tasks.
---

Fourier is Tuist's CLI tool to automate development tasks with the goal of **easing the contributions to the project**.

Before Fourier's existence, Tuist used [Ruby's Rake](https://github.com/ruby/rake). Rake's approach to designing the CLI interface leads to a flat and non-standard interface that doesn't support the usage of arguments to customize workflows. For instance, the following command is not possible `./bin/rake test --unit` and has to be `./bin/test_unit` instead. This often leads to a non-conventional naming across tasks (e.g. `test_unit`, `run_acceptance_tests`, `test_all`), and a huge `Rakefile` that contains the parsing code and the business logic all together.

By implementing our CLI tool within the repository we can better ensure the interface is consistent, and that the business logic is well-structured and tested.

### Running Fourier

Before running Fourier, make sure that you have the Ruby version specified in the `.ruby-version` file, and that you have fetched the [Bundler](https://bundler.io) dependencies specified in the `Gemfile` by running `bundle install`. Then, you can run the following command:

```bash
./fourier
```

#### Fourier Commands

Commands typically have subcommands to reduce the number of options for a command.

```bash
./fourier lint tuist
./fourier lint all --fix
```

You can checkout the help text for any command (or subcommand) with `--help`.

```bash
./fourier lint --help
Commands:
  fourier lint all                   # Lint all the code in the repository
  fourier lint backbone              # Lint the Ruby code of the Backbone project
  fourier lint cloud                 # Lint the Ruby code of the Cloud project
  fourier lint cocoapods-interactor  # Lint the Ruby code of the CocoaPods interactor project
  fourier lint fixturegen            # Lint the Swift code of the fixturegen project
  fourier lint fourier               # Lint the Ruby code of the fixturegen project
  fourier lint help [COMMAND]        # Describe subcommands or one specific subcommand
  fourier lint lockfiles             # Ensures SPM and Tuist's generated lockfiles are consistent
  fourier lint tuist                 # Lint the Swift code of the Tuist CLI
  fourier lint tuistbench            # Lint the Swift code of the tuistbench project
```

#### Source build tools

When using some commands like `./fourier test tuist` we use `tuist` to generate the project and test it.
By default, `fourier` will attempt to use the installed version of `tuist` on the host machine. If no such version exists, it will build the `tuist` binary from the sources of the checked out repository.

You may also override this behavior if you explicitly want to build from source when using the build tools with `--source` on commands that support this option.

### Shadowenv

Tuist includes [Shadowenv](https://shopify.github.io/shadowenv/) directory to adjust your local environment as you enter Tuist's directory from an interactive shell. One of the environment configurations that we provide is exposing the `bin/` directory to your path. Thanks to that, you can run Fourier by simply running `fourier` in your terminal.

If you don't have Shadowenv installed locally, you can follow [these steps](https://shopify.github.io/shadowenv/getting-started/#installation).
