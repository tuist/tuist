
---
title: Bundle Size
titleTemplate: :title · Develop · Guides · Tuist
description: Find out how to make and keep your app's memory footprint as small as possible.
---

# Bundle Size {#bundle-size}

> [!IMPORTANT] REQUIREMENTS
> - A <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist account and project</LocalizedLink>

As you add more features to your app, your app bundle size keeps growing. While some of the bundle size growth is inevitable as you ship more code and assets, there are many ways to minimze that growth, such as by ensuring your assets are not duplicated across your bundles or stripping unused binary symbols. With Tuistl, you can dive deep into your app bundle to see where
