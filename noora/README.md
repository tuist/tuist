# Noora

[![Hex.pm](https://img.shields.io/hexpm/v/noora.svg)](https://hex.pm/packages/noora) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/noora/)

<!-- MDOC !-->

Noora is a component library for building web applications with Phoenix LiveView. See all our components in our [Storybook](https://storybook.noora.tuist.dev).

This is the web component library, part of the [tuist/tuist](https://github.com/tuist/tuist) monorepo. The CLI component library lives in [tuist/Noora](https://github.com/tuist/Noora).

## Installation

To start, add `noora` to your list of dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:noora, "~> 0.1.0"}
  ]
end
```

Additionally, you need to add the stylesheet and scripts to your own assets.
These come bundled with the package, so, assuming that you are using the default Phoenix setup, you can import them to your `assets/css/app.css` and `assets/js/app.js` files:

```css
/* assets/css/app.css */
@import "noora/noora.css";
```

```javascript
// assets/js/app.js
import Noora from "noora";

let liveSocket = new LiveSocket("/live", Socket, {
  // Your existing socket setup
  hooks: { ...Noora },
});
```

## Fonts

Noora uses the following fonts:

- **Inter Variable** (weights 100-900) - Headings and body text font
- **Geist Mono** (weights 400, 700) - Monospace font for code

Fonts are not included by default, giving you control over how they are loaded. You have two options:

### Option 1: Use the bundled fonts from CDNs

Import `fonts.css` before `noora.css` to load fonts from Google Fonts and rsms.me:

```css
/* assets/css/app.css */
@import "noora/fonts.css";
@import "noora/noora.css";
```

This is the simplest option but makes external requests to third-party CDNs.

### Option 2: Self-host fonts

For better performance, privacy, or to avoid external requests, self-host the fonts:

```css
/* assets/css/app.css */

/* Define your self-hosted font faces */
@font-face {
  font-family: "Inter Variable";
  src: url("/fonts/InterVariable.woff2") format("woff2");
  font-weight: 100 900;
  font-display: swap;
  font-optical-sizing: auto;
}

@font-face {
  font-family: "Geist Mono";
  src: url("/fonts/GeistMono.woff2") format("woff2");
  font-weight: 400 700;
  font-display: swap;
}

/* Then import noora */
@import "noora/noora.css";
```

You can download the fonts from:
- [Inter](https://rsms.me/inter/)
- [Geist Mono](https://vercel.com/font)

## Usage

Noora provides a set of Phoenix components that you can use in your LiveView templates.
To see a list of available components, check the [documentation](https://hexdocs.pm/noora/).
