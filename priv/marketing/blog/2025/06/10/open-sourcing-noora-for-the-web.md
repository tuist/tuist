---
title: "Open sourcing Noora for the web"
category: "community"
tags: ["design", "open-source"]
excerpt: "We're open sourcing Noora for the web—a complete, accessible design system for Phoenix LiveView with Figma files and ready-to-use components."
author: cschmatzler
highlighted: false
og_image_path: /marketing/images/blog/2025/06/10/open-sourcing-noora-for-the-web/og.png
---

We love open source - that's not a secret. A few months ago, we open sourced [Noora](https://github.com/tuist/Noora), our design system for building CLIs in Swift, which our own CLI is now built on. Today, we're extending Noora to the web: a complete design system for building web applications with Phoenix LiveView.

Two months ago, we [announced](https://tuist.dev/blog/2025/04/17/meet-new-tuist) the redesigned Tuist dashboard and today we are releasing the building blocks that we created to build it: a complete design system for building web applications with Phoenix LiveView, including all the Figma design files and the fully accessible components.

## Building blocks for LiveView

When we started building the new dashboard, we evaluated several ways to implement the beautiful designs from our designer [Asmit](https://www.asmitbm.me/).

As a starter, our server is implemented in Elixir using Phoenix. All pages are built with Phoenix LiveView and therefore server-side rendered. This allows us to iterate much faster than if we had to deal with client-side state management, which is why we decided to build the new dashboard with LiveView as well.

Using server-side rendering is amazing for us, but it also comes with some challenges when building a highly interactive user interface like our dashboard. We had a few important principles that we wanted to follow while bringing our design system to life:

- **It needs to be accessible**: We want our tools to be accessible to invite everyone to use our tools, benefit from them, and share ideas to make the product better every day.
- **It needs to be keyboard-navigatable**: Being developers ourselves, we use our keyboard a lot to navigate the tools we use every day, and we want to make sure that our tools feel great to use with the keyboard.

Both of these are solved by [so](https://react-spectrum.adobe.com/react-aria/index.html) [many](https://radix-ui.com/) [different](https://kobalte.dev/) [libraries](https://headlessui.com/) in the JavaScript world, but there is a lack of good solutions for LiveView, while the bundled JavaScript functionality is not sufficient to meet our requirements.

- **It needs to be as close to the web as possible**: The web is designed to last. As a small team of four, we want to focus on building features rather than chasing breaking changes. Modern CSS has improved dramatically—we use plain CSS without post-processing. While we embrace web standards for JavaScript, we still bundle our code because loading external dependencies (like Zag) from CDNs within a library would require consumers to configure CSP headers and handle version management—complexity we want to avoid.

In the end, we decided to build our design system on plain CSS while building our own hook system based on [Zag](https://zagjs.com/), a library of state machines for building UI components that is agnostic to what rendering framework is used. It has been amazing to work with, and I'm happy to have our components be fully keyboard-controllable.

The result is a complete set of LiveView components that handle focus management, ARIA attributes, and keyboard interactions out of the box. No more wrestling with other dependencies and hand-writing focus trapping logic.

### The quick start

For detailed setup instructions, check our full documentation on [HexDocs](https://hexdocs.pm/noora/), but here's a quick start to get you going if you just want to try it out. There's also a [Storybook](https://storybook.noora.tuist.dev/) available to explore the components and their available properties.

1. Add the dependency to your `mix.exs` file:

```elixir
defp deps do
  [
    {:noora, "~> 0.1.0"}
  ]
end
```

2. Import the styles in your `app.css` file:

```css
@import "noora/noora.css";
```

3. Add the JavaScript hook to your `app.js` file:

```javascript
import Noora from "noora";

let liveSocket = new LiveSocket("/live", Socket, {
  // Your existing socket setup
  hooks: { ...Noora },
});
```

That's it! You can now use the components in your LiveView templates. As a helper, we also expose a `use Noora` macro that automatically imports all components.

```html
<.button variant="primary" label="Hello, Noora!" />
<.badge label="Passed" color="success" style="fill" size="large" />
```

## The Figma files

![Preview of components](/marketing/images/blog/2025/06/10/open-sourcing-noora-for-the-web/preview.png)

We're not just open sourcing code - we're releasing the entire design system, including the Figma files with all of our tokens, designs and examples. You can find them directly on [Figma](https://www.figma.com/community/file/1512465864777652939), ready to explore before installing Noora and building your website with it.

## What's next?

We are excited to release this first version. It's been in production for a while now, has received a lot of love and attention, and we are genuinely looking forward to seeing what you build with it. We will continue to push new components and updates to existing ones to power all of the new stuff we are working on, and are also welcoming contributions in the form of bug reports and pull requests.

We will also update our [Noora documentation page](https://noora.tuist.dev) which is currently focused on the CLI version of Noora to include the web version as well. This didn't quite make the cut for the initial release, but we will have it ready soon. We are also going to update the Storybook with more real-world examples from our own usage patterns building Tuist.

Looking further into the future, we are keeping a close eye on what's possible with web components and how we can leverage them to make Noora for the web completely agnostic of where you use them, decoupling it from Elixir and LiveView and allowing other server-side frameworks such as [Vapor](https://vapor.codes/) to use Noora as well.

## The links, all in one place
             
- [GitHub](https://github.com/tuist/Noora)
- [Figma](https://www.figma.com/community/file/1512465864777652939)
- [Hex](https://hex.pm/packages/noora)
- [HexDocs](https://hexdocs.pm/noora/)
- [Storybook](https://storybook.noora.tuist.dev/)
