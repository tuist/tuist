---
title: "We are deprecating tuistenv in favor of Mise"
category: "product"
tags: ["mise", "asdf"]
excerpt: "In this blog post, we share why we are deprecating tuistenv in favor of mise, a runtime executor that allows you to manage multiple versions of a tool and activate the right one when you choose a directory in your terminal."
author: pepicrft
---

If you've used Tuist for a while,
you probably know that Tuist's default installation installs a version manager,
`tuistenv`,
which allows you to install multiple versions of Tuist and switch between them easily.
We built this early in the life of Tuist,
because installation solutions like [Homebrew](https://brew.sh/) are not able to install and activate multiple versions of the same tool.

Using the same Tuist version across environments is important to avoid non-deterministic results across environments.
Do you remember when you used to do `bundle exec pod install`?
[Bundler](https://bundler.io/),
Ruby's official dependency manager,
provides that `exec` command to ensure everyone is using the same version pinned in the `Gemfile.lock` file.

As we [shared earlier this year](/blog/2023/07/26/2023-tuist-direction),
one of our focus this years is to make Tuist **sustainable**,
and that means we need to focus on the core features that make Tuist great.
**Version management is not one of them.**
But if Homebrew is not a sensible solution for Tuist,
what could we use instead?

Luckily, a few years ago I had the opportunity to met with [Jeff Dickey](https://twitter.com/jdxcode).
He's one of the talented engineers behind [OCLIF](https://oclif.io/),
a framework for building command line interfaces,
and a person I admire for his work on open source and CLI tools.
He told me about a new project of him,
[mise](https://github.com/jdx/mise),
which he describes as a "runtime executor".
`mise` can manage multiple versions of a tool,
and not only that, but activate the right one when you choose a directory in your terminal.
It does it by using a `.tools-version` file in the directory,
which contains the version of the tool that should be used in that directory and its subdirectories.
Sounds familiar? We solved the exact same problem with `tuistenv` and the `.tuist-version` file.
It sounded too good to be true, so we decided to give it a try.

Tuist [uses it](https://github.com/tuist/tuist/blob/main/.tool-versions) to manage and activate versions of `tuist` (which we use with Tuist itself), swiftformat, and swiftlint, and it's been working great so far.
It's proven to be one of those tools that works so well that you forget it's there.
`mise` includes handy commands like `ls-remote`, which lists all the remotely-available versions:

```bash
$ mise ls-remote tuist

3.35.0
3.35.1
3.35.2
3.35.4
3.35.5
3.36.0
```

After thorough usage and having a great experience, we've decided to deprecate `tuistenv` in favor of `mise`.
If you are currently using `tuistenv` to manage Tuist versions, we recommend you to migrate to `mise` by following the instructions below.

```bash
# Uninstall Tuist
curl -Ls https://uninstall.tuist.io | bash

# Install mise
curl https://mise.jdx.dev/mise-latest-macos-arm64 > ~/bin/mise
chmod +x ~/bin/mise

# Install and activate Tuist
mise install tuist@3.36.0
mise install tuist@3
mise use tuist@3.36.0
```

We'll continue to support `tuistenv` until we release the next major version of Tuist in January, Tuist 4.
We are sharing this early so you have time to migrate and give us feedback.
We belive `mise` is the right solution for Tuist. It provides a great developer experience, it's very well maintained and stable, and most importantly, it'll allow us to focus on the core features that make Tuist great.
