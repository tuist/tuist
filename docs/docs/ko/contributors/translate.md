---
title: Translate
titleTemplate: :title | Contributors | Tuist
description: This document describes the principles that guide the development of Tuist.
---

# Translate

Languages can be barriers to understanding. We want to make sure that Tuist is accessible to as many people as possible. If you speak a language that Tuist doesn't support, you can help us by translating the various surfaces of Tuist. 

Since maintaining translations is a continuous effort, we add languages as we see contributors willing to help us maintain them. The following languages are currently supported:

- English
- Korean
- Japanese
- Russian

> [!TIP] REQUEST A NEW LANGUAGE
> If you believe Tuist would benefit from supporting a new language, please create a new [topic in the community forum](https://community.tuist.io/c/general/4) to discuss it with the community.

## How to translate

We use [Crowdin](https://crowdin.com/) to manage the translations. First, go to the project that you want to contribute to:

- [Documentation](https://crowdin.com/project/tuist-documentation)

You'll need an account to start translating. You can sign in with GitHub. Once you have access, you can start translating. You'll see the list of resources that are available for translation. When you click on a resource, the editor will open, and you'll see a split view with the resource in the source language on the left and the translation on the right. Translate the text on the right and save your changes.

As translations are updated, Crowdin will push them automatically to the right repository opening a pull request, which the maintainers will review and merge.

> [!IMPORTANT] DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
> Crowdin segments the files to bind source and target languages. If you modify the source language, you'll break the binding, and the reconciliation might yield unexpected results.