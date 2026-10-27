# Noora

[![Hex.pm](https://img.shields.io/hexpm/v/noora.svg)](https://hex.pm/packages/noora) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/noora/)

<!-- MDOC !-->

Noora is a component library for building web applications with Phoenix LiveView and standards-based web components. See all our components in our [Storybook](https://storybook.noora.tuist.dev).

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
  hooks: { ...Noora.Hooks },
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

## Web components

The `@tuist/noora` package on the [Node Package Manager package registry](https://www.npmjs.com/) provides framework-independent [custom elements](https://developer.mozilla.org/en-US/docs/Web/API/Web_components/Using_custom_elements) built with [Lit](https://lit.dev/). The browser distribution includes Noora's actions, data display, feedback, forms, navigation, overlays, and layout components.

Install the package:

```sh
npm install @tuist/noora
```

Load the design tokens and register the components:

```javascript
import "@tuist/noora/tokens.css";
import "@tuist/noora/web-components";
```

Then use the components in plain Hypertext Markup Language or in your preferred framework:

```html
<noora-button label="Create project"></noora-button>

<noora-button variant="secondary" size="medium">
  <svg slot="icon-left" aria-hidden="true"><!-- icon --></svg>
  Previous
</noora-button>

<noora-button icon-only variant="destructive" aria-label="Delete project">
  <svg aria-hidden="true"><!-- icon --></svg>
</noora-button>

<noora-badge appearance="light-fill" color="success"> Available </noora-badge>

<noora-text-input type="email" label="Email" name="email"></noora-text-input>

<noora-dropdown label="Options">
  <noora-dropdown-item value="edit" icon="edit">Edit</noora-dropdown-item>
  <noora-dropdown-item value="delete" icon="trash">Delete</noora-dropdown-item>
</noora-dropdown>
```

The browser components reuse the same source styles, icons, defaults, allowed values, and terminology as their Phoenix counterparts. Native form controls participate in validation and submission, menus and overlays expose controlled `open` properties, and collection-based components use declarative child elements. Structured properties remain available for programmatic rendering, while chart configuration remains property-driven.

Respond to standard browser events and Noora custom events with `addEventListener`. Form controls emit familiar events such as `input` and `change`. Composite controls use `noora-*` custom events whose structured payload is available through `event.detail`:

```javascript
const select = document.querySelector("noora-select");

select.addEventListener("change", () => {
  console.log(select.value);
});

select.addEventListener("noora-select", (event) => {
  console.log(event.detail.value);
});
```

Noora custom events bubble and cross shadow-root boundaries, so listeners can be attached directly to a component or to an ancestor. Every public event and its payload type is listed in the generated component reference, TypeScript declarations, Storybook, and Custom Elements Manifest.

Use named slots where a component accepts custom content. For example, Button provides `icon-left` and `icon-right`, Modal provides `trigger`, `header-icon`, `header-button`, and `footer`, and Dropdown provides `icon` and `search`.

If an application already imports `@tuist/noora/noora.css` for the Phoenix components, it does not need to import `tokens.css` separately.

The Phoenix and Lit renderers share component contracts and source stylesheets. LiveView-specific behavior remains in the Phoenix adapters, while the custom elements only use browser standards.

The package includes a generated [web component guide](docs/web-components.md), a reference for every component, TypeScript declarations, and a [Custom Elements Manifest](https://custom-elements-manifest.open-wc.org/) at `custom-elements.json`. These artifacts are generated from the component contracts, so attributes, properties, defaults, allowed values, examples, and documentation stay aligned.

The contract is compile-time input. The package build generates the documentation and metadata, and the browser bundle inlines the values it needs. Consumer applications do not fetch component contract files at runtime.

For local development and visual verification, run the Noora Storybook and open any story under **Web components**.
