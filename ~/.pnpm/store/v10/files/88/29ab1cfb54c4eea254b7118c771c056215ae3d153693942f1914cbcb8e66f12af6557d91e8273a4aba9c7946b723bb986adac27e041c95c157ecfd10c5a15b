# hast-util-format

[![Build][build-badge]][build]
[![Coverage][coverage-badge]][coverage]
[![Downloads][downloads-badge]][downloads]
[![Size][size-badge]][size]
[![Sponsors][sponsors-badge]][collective]
[![Backers][backers-badge]][collective]
[![Chat][chat-badge]][chat]

[hast][] utility to format whitespace in HTML.

## Contents

* [What is this?](#what-is-this)
* [When should I use this?](#when-should-i-use-this)
* [Install](#install)
* [Use](#use)
* [API](#api)
  * [`Options`](#options)
  * [`format(tree, options)`](#formattree-options)
* [Compatibility](#compatibility)
* [Related](#related)
* [Security](#security)
* [Contribute](#contribute)
* [License](#license)

## What is this?

This package is a utility that formats whitespace in HTML.
In short, it works as follows:

* collapse all existing whitespace to either a line ending or a single space
  ([`hast-util-minify-whitespace`][hast-util-minify-whitespace])
* remove those spaces and line endings if they do not contribute to the
  document
* inject needed line endings
* indent previously collapsed line endings properly

## When should I use this?

This package is useful when you want to improve the readability of an HTML
fragment as it adds insignificant but pretty whitespace between elements.
The plugin [`rehype-format`][rehype-format] uses this package to format HTML
at the plugin level.
The package [`hast-util-minify-whitespace`][hast-util-minify-whitespace] does
the inverse.

## Install

This package is [ESM only][esm].
In Node.js (version 16+), install with [npm][]:

```sh
npm install hast-util-format
```

In Deno with [`esm.sh`][esmsh]:

```js
import {format} from 'https://esm.sh/hast-util-format@1'
```

In browsers with [`esm.sh`][esmsh]:

```html
<script type="module">
  import {format} from 'https://esm.sh/hast-util-format@1?bundle'
</script>
```

## Use

Say we have the following `example.html`:

```html
<!doCTYPE HTML><html>
 <head>
    <title>Hello!</title>
<meta charset=utf8>
      </head>
  <body><section>    <p>hi there</p>
     </section>
 </body>
</html>
```

Say we have the following `example.js`:

```js
import fs from 'node:fs/promises'
import {format} from 'hast-util-format'
import {fromHtml} from 'hast-util-from-html'
import {toHtml} from 'hast-util-to-html'

const document = await fs.readFile('example.html', 'utf8')

const tree = fromHtml(document)

format(tree)

const result = toHtml(tree)

console.log(result)
```

…now running `node example.js` yields:

```html
<!doctype html>
<html>
  <head>
    <title>Hello!</title>
    <meta charset="utf8">
  </head>
  <body>
    <section>
      <p>hi there</p>
    </section>
  </body>
</html>
```

> 👉 **Note**:
> some of the changes have been made by `hast-util-to-html`.

## API

### `Options`

Configuration.

###### Fields

* `blanks?` (`Array<string> | null | undefined`)
  — list of tag names to join with a blank line (default: `[]`);
  these tags,
  when next to each other,
  are joined by a blank line (`\n\n`);
  for example,
  when `['head', 'body']` is given,
  a blank line is added between these two
* `indent?` (`string | number | null | undefined`)
  — indentation per level (default: `2`);
  when `number`,
  uses that amount of spaces; when `string`,
  uses that per indentation level
* `indentInitial?` (`boolean | null | undefined`)
  — whether to indent the first level (default: `true`);
  this is usually the `<html>`,
  thus not indenting `head` and `body`

### `format(tree, options)`

Format whitespace in HTML.

###### Parameters

* `tree` (`Root`)
  — tree
* `options?` (`Options | null | undefined`)
  — configuration (optional)

###### Returns

Nothing (`undefined`).

## Compatibility

Projects maintained by the unified collective are compatible with maintained
versions of Node.js.

When we cut a new major release, we drop support for unmaintained versions of
Node.
This means we try to keep the current release line, `hast-util-format@1`,
compatible with Node.js 16.

## Related

* [`hast-util-minify-whitespace`][hast-util-minify-whitespace]
  — minify whitespace between elements

## Security

This package is safe.

## Contribute

See [`contributing.md` in `syntax-tree/.github`][contributing] for ways to get
started.
See [`support.md`][support] for ways to get help.

This project has a [code of conduct][coc].
By interacting with this repository, organization, or community you agree to
abide by its terms.

## License

[MIT][license] © [Titus Wormer][author]

<!-- Definitions -->

[build-badge]: https://github.com/syntax-tree/hast-util-format/workflows/main/badge.svg

[build]: https://github.com/syntax-tree/hast-util-format/actions

[coverage-badge]: https://img.shields.io/codecov/c/github/syntax-tree/hast-util-format.svg

[coverage]: https://codecov.io/github/syntax-tree/hast-util-format

[downloads-badge]: https://img.shields.io/npm/dm/hast-util-format.svg

[downloads]: https://www.npmjs.com/package/hast-util-format

[size-badge]: https://img.shields.io/badge/dynamic/json?label=minzipped%20size&query=$.size.compressedSize&url=https://deno.bundlejs.com/?q=hast-util-format

[size]: https://bundlejs.com/?q=hast-util-format

[sponsors-badge]: https://opencollective.com/unified/sponsors/badge.svg

[backers-badge]: https://opencollective.com/unified/backers/badge.svg

[collective]: https://opencollective.com/unified

[chat-badge]: https://img.shields.io/badge/chat-discussions-success.svg

[chat]: https://github.com/syntax-tree/unist/discussions

[esm]: https://gist.github.com/sindresorhus/a39789f98801d908bbc7ff3ecc99d99c

[npm]: https://docs.npmjs.com/cli/install

[esmsh]: https://esm.sh

[license]: license

[author]: https://wooorm.com

[contributing]: https://github.com/syntax-tree/.github/blob/main/contributing.md

[support]: https://github.com/syntax-tree/.github/blob/main/support.md

[coc]: https://github.com/syntax-tree/.github/blob/main/code-of-conduct.md

[hast]: https://github.com/hast/hast

[hast-util-minify-whitespace]: https://github.com/rehypejs/rehype-minify/tree/main/packages/hast-util-minify-whitespace

[rehype-format]: https://github.com/rehypejs/rehype-format
