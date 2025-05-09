# hast-util-phrasing

[![Build][build-badge]][build]
[![Coverage][coverage-badge]][coverage]
[![Downloads][downloads-badge]][downloads]
[![Size][size-badge]][size]
[![Sponsors][sponsors-badge]][collective]
[![Backers][backers-badge]][collective]
[![Chat][chat-badge]][chat]

[hast][] utility to check if a node is [*phrasing*][spec] content.

## Contents

*   [What is this?](#what-is-this)
*   [When should I use this?](#when-should-i-use-this)
*   [Install](#install)
*   [Use](#use)
*   [API](#api)
    *   [`phrasing(value)`](#phrasingvalue)
*   [Types](#types)
*   [Compatibility](#compatibility)
*   [Security](#security)
*   [Related](#related)
*   [Contribute](#contribute)
*   [License](#license)

## What is this?

This package is a small utility that checks if a node is phrasing content
according to HTML.

## When should I use this?

This utility is super niche, if you’re here you probably know what you’re
looking for!

## Install

This package is [ESM only][esm].
In Node.js (version 16+), install with [npm][]:

```sh
npm install hast-util-phrasing
```

In Deno with [`esm.sh`][esmsh]:

```js
import {phrasing} from 'https://esm.sh/hast-util-phrasing@3'
```

In browsers with [`esm.sh`][esmsh]:

```html
<script type="module">
  import {phrasing} from 'https://esm.sh/hast-util-phrasing@3?bundle'
</script>
```

## Use

```js
import {phrasing} from 'hast-util-phrasing'

// Given flow content:
phrasing({
  type: 'element',
  tagName: 'div',
  children: [{type: 'text', value: 'Alpha'}]
})
// => false

// Given a phrasing element:
phrasing({
  type: 'element',
  tagName: 'meta',
  properties: {itemProp: 'bravo'},
  children: []
})
// => true

// Given a non-phrasing element:
phrasing({
  type: 'element',
  tagName: 'meta',
  properties: {charSet: 'utf8'},
  children: []
})
// => false

// Given text:
phrasing({type: 'text', value: 'Delta'})
// => true
```

## API

This package exports the identifier [`phrasing`][api-phrasing].
There is no default export.

### `phrasing(value)`

Check if the given value is [*phrasing*][spec] content.

###### Parameters

*   `value` ([`Node`][node])
    — node to check

###### Returns

Whether `value` is phrasing content (`boolean`).

## Types

This package is fully typed with [TypeScript][].
It exports no additional types.

## Compatibility

Projects maintained by the unified collective are compatible with maintained
versions of Node.js.

When we cut a new major release, we drop support for unmaintained versions of
Node.
This means we try to keep the current release line, `hast-util-phrasing@^3`,
compatible with Node.js 16.

## Security

`hast-util-phrasing` does not change the syntax tree so there are no openings
for [cross-site scripting (XSS)][xss] attacks.

## Related

*   [`hast-util-is-element`](https://github.com/syntax-tree/hast-util-is-element)
    — check if a node is a (certain) element
*   [`hast-util-has-property`](https://github.com/syntax-tree/hast-util-has-property)
    — check if a node has a property
*   [`hast-util-is-body-ok-link`](https://github.com/rehypejs/rehype-minify/tree/main/packages/hast-util-is-body-ok-link)
    — check if a node is “Body OK” link element
*   [`hast-util-is-conditional-comment`](https://github.com/rehypejs/rehype-minify/tree/main/packages/hast-util-is-conditional-comment)
    — check if a node is a conditional comment
*   [`hast-util-is-css-link`](https://github.com/rehypejs/rehype-minify/tree/main/packages/hast-util-is-css-link)
    — check if a node is a CSS link element
*   [`hast-util-is-css-style`](https://github.com/rehypejs/rehype-minify/tree/main/packages/hast-util-is-css-style)
    — check if a node is a CSS style element
*   [`hast-util-embedded`](https://github.com/syntax-tree/hast-util-embedded)
    — check if a node is an embedded element
*   [`hast-util-heading`](https://github.com/syntax-tree/hast-util-heading)
    — check if a node is a heading element
*   [`hast-util-interactive`](https://github.com/syntax-tree/hast-util-interactive)
    — check if a node is interactive
*   [`hast-util-is-javascript`](https://github.com/rehypejs/rehype-minify/tree/main/packages/hast-util-is-javascript)
    — check if a node is a JavaScript script element
*   [`hast-util-labelable`](https://github.com/syntax-tree/hast-util-labelable)
    — check whether a node is labelable
*   [`hast-util-script-supporting`](https://github.com/syntax-tree/hast-util-script-supporting)
    — check if a node is a script-supporting element
*   [`hast-util-sectioning`](https://github.com/syntax-tree/hast-util-sectioning)
    — check if a node is a sectioning element
*   [`hast-util-transparent`](https://github.com/syntax-tree/hast-util-transparent)
    — check if a node is a transparent element
*   [`hast-util-whitespace`](https://github.com/syntax-tree/hast-util-whitespace)
    — check if a node is inter-element whitespace

## Contribute

See [`contributing.md`][contributing] in [`syntax-tree/.github`][health] for
ways to get started.
See [`support.md`][support] for ways to get help.

This project has a [code of conduct][coc].
By interacting with this repository, organization, or community you agree to
abide by its terms.

## License

[MIT][license] © [Titus Wormer][author]

<!-- Definitions -->

[build-badge]: https://github.com/syntax-tree/hast-util-phrasing/workflows/main/badge.svg

[build]: https://github.com/syntax-tree/hast-util-phrasing/actions

[coverage-badge]: https://img.shields.io/codecov/c/github/syntax-tree/hast-util-phrasing.svg

[coverage]: https://codecov.io/github/syntax-tree/hast-util-phrasing

[downloads-badge]: https://img.shields.io/npm/dm/hast-util-phrasing.svg

[downloads]: https://www.npmjs.com/package/hast-util-phrasing

[size-badge]: https://img.shields.io/badge/dynamic/json?label=minzipped%20size&query=$.size.compressedSize&url=https://deno.bundlejs.com/?q=hast-util-phrasing

[size]: https://bundlejs.com/?q=hast-util-phrasing

[sponsors-badge]: https://opencollective.com/unified/sponsors/badge.svg

[backers-badge]: https://opencollective.com/unified/backers/badge.svg

[collective]: https://opencollective.com/unified

[chat-badge]: https://img.shields.io/badge/chat-discussions-success.svg

[chat]: https://github.com/syntax-tree/unist/discussions

[npm]: https://docs.npmjs.com/cli/install

[esm]: https://gist.github.com/sindresorhus/a39789f98801d908bbc7ff3ecc99d99c

[esmsh]: https://esm.sh

[typescript]: https://www.typescriptlang.org

[license]: license

[author]: https://wooorm.com

[health]: https://github.com/syntax-tree/.github

[contributing]: https://github.com/syntax-tree/.github/blob/main/contributing.md

[support]: https://github.com/syntax-tree/.github/blob/main/support.md

[coc]: https://github.com/syntax-tree/.github/blob/main/code-of-conduct.md

[spec]: https://html.spec.whatwg.org/multipage/dom.html#phrasing-content-2

[hast]: https://github.com/syntax-tree/hast

[node]: https://github.com/syntax-tree/hast#nodes

[xss]: https://en.wikipedia.org/wiki/Cross-site_scripting

[api-phrasing]: #phrasingvalue
