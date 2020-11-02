---
layout: post
title: 'Version 0.9.0 published'
date: 2018-12-03
categories: [tuist, release, swift]
excerpt: In this blog post we talk about the changes that come with the recently published version 0.9.0.
author: pepibumur
---

Today we have [published the version 0.9.0](https://github.com/tuist/tuist/releases/tag/0.9.0) of Tuist. It's been a while without releasing updates but we are getting back to speed. Stay tuned because we are working on a lot of improvements and cool features to make your experience dealing with Xcode projects more enjoyable.

## Files and groups order

Files and groups were sorted alphabetically when the project was generated. That resulted in a non-standard sorting order as Igor reported on [this issue](https://github.com/tuist/tuist/issues/140). With 0.9.0, we've changed the order to default to sort files before groups, and then sort them alphabetically.

In our aim to define conventions and good practices in Xcode projects, we don't plan to make the sorting configurable. We believe that the order that we set in this version is navigatable and aligned with Xcode defaults.

## Generation of both, Debug and Release configurations

Previous versions of Tuist generated only the Debug or the Release configuration _(depending on the flag that you passed when running the tool)_. We have changed that behavior to generate both configurations. That allows developers building for any of the configurations without having to regenerate the Xcode project. Thanks Robin for [reporting the issue](https://github.com/tuist/tuist/issues/159).

## More reliability through acceptance tests

Although this is not a user-facing feature, it has a huge impact in the reliability of the tool. Although we took seriously and covered most of the execution paths with unit test, they don't prevent common Tuist use cases from breaking at any time. In [this PR](https://github.com/tuist/tuist/pull/166) we add Cucumber to the toolbox to define acceptance tests that will be executed on CI. If you are curious about how a Cucumber test looks, you can have a look at the test below:

```ruby
Feature: Initialize a new project using Tuist
Scenario: The project is a compilable macOS application
Given that tuist is available
And I have have a working directory
When I initialize a macos application named Test
Then I generate the project
Then I should be able to build the scheme Test
Then I delete the working directory
```

If any of the feature steps breaks, the test fails and we have to fix it before merging the changes into main. This brings more confidence when adding changes to the project, which is very handy for new project contributors.

## How to update

It's very easy, did you know that Tuist knows how to update itself? There's no need to depend on third-party tools to drive the update. Just run the following command in your terminal:

```ruby
tuist update
```

I hope you like the release and that keep reporting issues and ideas to help Xcode developers deliver stunning high-quality apps.

> Don't forget to listen to the [soundtrack](https://soundcloud.com/samar_elsayed/florencethemachine_hunger) of this release.

Have a wonderful week.
