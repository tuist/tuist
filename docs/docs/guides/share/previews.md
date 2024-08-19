---
title: Previews
description: Learn how to generate and share previews of your apps with anyone.
---

# Previews


When building an app, you may want to share it with others to get feedback.
Traditionally, this is something that teams do by building, signing, and pushing their apps to platforms like Apple's [TestFlight](https://developer.apple.com/testflight/).
However, this process can be cumbersome and slow, especially when you're just looking for quick feedback from a colleague or a friend.

To make this process more streamlined, Tuist provides a way to generate and share previews of your apps with anyone.

> [!IMPORTANT] ONLY SIMULATOR ARCHITECTURES ARE CURRENTLY SUPPORTED
> We only support simulator architectures for previews at the moment. Support for devices will come in the future.

:::code-group
```bash [Tuist Project]
tuist build App # Build the app first
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug
tuist share App --configuration Debug --platform iOS
```
:::

The command will generate a link that you can share with anyone to run the app. All they'll need to do is to run the command below:

```bash
tuist run {url}
```

> [!IMPORTANT] PREVIEWS' VISIBILITY
> Only people with access to the organization the project belongs to can access the previews. We plan to add support for expiring links.