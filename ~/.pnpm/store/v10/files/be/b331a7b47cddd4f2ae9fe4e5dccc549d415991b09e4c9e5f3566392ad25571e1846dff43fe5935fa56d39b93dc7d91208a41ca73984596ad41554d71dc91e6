# rehype-sanitize

[![Build][build-badge]][build]
[![Coverage][coverage-badge]][coverage]
[![Downloads][downloads-badge]][downloads]
[![Size][size-badge]][size]
[![Sponsors][sponsors-badge]][collective]
[![Backers][backers-badge]][collective]
[![Chat][chat-badge]][chat]

**[rehype][]** plugin to sanitize HTML.

## Contents

*   [What is this?](#what-is-this)
*   [When should I use this?](#when-should-i-use-this)
*   [Install](#install)
*   [Use](#use)
*   [API](#api)
    *   [`defaultSchema`](#defaultschema)
    *   [`unified().use(rehypeSanitize[, schema])`](#unifieduserehypesanitize-schema)
    *   [`Options`](#options)
*   [Example](#example)
    *   [Example: headings (DOM clobbering)](#example-headings-dom-clobbering)
    *   [Example: math](#example-math)
    *   [Example: syntax highlighting](#example-syntax-highlighting)
*   [Types](#types)
*   [Compatibility](#compatibility)
*   [Security](#security)
*   [Related](#related)
*   [Contribute](#contribute)
*   [License](#license)

## What is this?

This package is a [unified][] ([rehype][]) plugin to make sure HTML is safe.
It drops anything that isn’t explicitly allowed by a schema (defaulting to how
`github.com` works).

**unified** is a project that transforms content with abstract syntax trees
(ASTs).
**rehype** adds support for HTML to unified.
**hast** is the HTML AST that rehype uses.
This is a rehype plugin that transforms hast.

## When should I use this?

It’s recommended to sanitize your HTML any time you do not completely trust
authors or the plugins being used.

This plugin is built on [`hast-util-sanitize`][hast-util-sanitize], which cleans
[hast][] syntax trees.
rehype focusses on making it easier to transform content by abstracting such
internals away.

## Install

This package is [ESM only][esm].
In Node.js (version 16+), install with [npm][]:

```sh
npm install rehype-sanitize
```

In Deno with [`esm.sh`][esmsh]:

```js
import rehypeSanitize from 'https://esm.sh/rehype-sanitize@6'
```

In browsers with [`esm.sh`][esmsh]:

```html
<script type="module">
  import rehypeSanitize from 'https://esm.sh/rehype-sanitize@6?bundle'
</script>
```

## Use

Say we have the following file `index.html`:

```html
<div onmouseover="alert('alpha')">
  <a href="jAva script:alert('bravo')">delta</a>
  <img src="x" onerror="alert('charlie')">
  <iframe src="javascript:alert('delta')"></iframe>
  <math>
    <mi xlink:href="data:x,<script>alert('echo')</script>"></mi>
  </math>
</div>
<script>
require('child_process').spawn('echo', ['hack!']);
</script>
```

…and our module `example.js` looks as follows:

```js
import rehypeParse from 'rehype-parse'
import rehypeSanitize from 'rehype-sanitize'
import rehypeStringify from 'rehype-stringify'
import {read} from 'to-vfile'
import {unified} from 'unified'

const file = await unified()
  .use(rehypeParse, {fragment: true})
  .use(rehypeSanitize)
  .use(rehypeStringify)
  .process(await read('index.html'))

console.log(String(file))
```

Now running `node example.js` yields:

```html
<div>
  <a>delta</a>
  <img src="x">




</div>
```

## API

This package exports the identifier [`defaultSchema`][api-default-schema].
The default export is [`rehypeSanitize`][api-rehype-sanitize].

### `defaultSchema`

Default schema ([`Options`][api-options]).

Follows GitHub style sanitation.

### `unified().use(rehypeSanitize[, schema])`

Sanitize HTML.

###### Parameters

*   `options` ([`Options`][api-options], optional)
    — configuration

###### Returns

Transform ([`Transformer`][unified-transformer]).

### `Options`

Schema that defines what nodes and properties are allowed (TypeScript type).

This option is a bit advanced as it requires knowledge of syntax trees, so see
the docs for [`Schema` in `hast-util-sanitize`][hast-util-sanitize-schema].

## Example

### Example: headings (DOM clobbering)

DOM clobbering is an attack in which malicious HTML confuses an application by
naming elements, through `id` or `name` attributes, such that they overshadow
presumed properties in `window` (the global scope in browsers).
DOM clobbering often occurs when user content is used to generate heading IDs.
To illustrate, say we have this `browser.js` file:

```js
console.log(current)
```

And our module `example.js` contains:

```js
/**
 * @typedef {import('hast').Root} Root
 */

import fs from 'node:fs/promises'
import rehypeParse from 'rehype-parse'
import rehypeStringify from 'rehype-stringify'
import {unified} from 'unified'

const browser = String(await fs.readFile('browser.js'))
const document = `<a name="old"></a>
<h1 id="current">Current</h1>
${`<p>${'Lorem ipsum dolor sit amet. '.repeat(20)}</p>\n`.repeat(20)}
<p>Link to <a href="#current">current</a>, link to <a href="#old">old</a>.`

const file = await unified()
  .use(rehypeParse, {fragment: true})
  .use(function () {
    /**
     * @param {Root} tree
     */
    return function (tree) {
      tree.children.push({
        type: 'element',
        tagName: 'script',
        properties: {type: 'module'},
        children: [{type: 'text', value: browser}]
      })
    }
  })
  .use(rehypeStringify)
  .process(document)

await fs.writeFile('output.html', String(file))
```

This code processes HTML, inlines our browser script into it, and writes it out.
The input HTML models how markdown often looks on platforms like GitHub, which
allow heading IDs to be generated from their text and embedded HTML (including
`<a name="old"></a>`, which can be used to create anchors for renamed headings
to prevent links from breaking).
The generated HTML looks like:

```html
<a name="old"></a>
<h1 id="current">Current</h1>
<p>Lorem ipsum dolor sit amet.<!--…--></p>
<p>Link to <a href="#current">current</a>, link to <a href="#old">old</a>.</p>
<script type="module">console.log(current)</script>
```

When you run this code locally and open the generated `output.html`, you can
observe that the links at the bottom work, but also that the `<h1>` element
is printed to the console (the clobbering).

`rehype-sanitize` solves the clobbering by prefixing every `id` and `name`
attribute with `'user-content-'`.
Changing `example.js`:

```diff
@@ -15,6 +15,7 @@ ${`<p>${'Lorem ipsum dolor sit amet. '.repeat(20)}</p>\n`.repeat(20)}

   const file = await unified()
     .use(rehypeParse, {fragment: true})
+    .use(rehypeSanitize)
     .use(function () {
       /**
        * @param {Root} tree
```

Now yields:

```diff
-<a name="old"></a>
-<h1 id="current">Current</h1>
+<a name="user-content-old"></a>
+<h1 id="user-content-current">Current</h1>
```

This introduces another problem as the links are now broken.
It could perhaps be solved by changing all links, but that would make the links
rather ugly, and we’d need to track what IDs we have outside of the user content
on our pages too.
Alternatively, and what arguably looks better, we could rewrite pretty links to
their safe but ugly prefixed elements.
This is what GitHub does.
Replace `browser.js` with the following:

```js
/// <reference lib="dom" />
/* eslint-env browser */

// Page load (you could wrap this in a DOM ready if the script is loaded early).
hashchange()

// When URL changes.
window.addEventListener('hashchange', hashchange)

// When on the URL already, perhaps after scrolling, and clicking again, which
// doesn’t emit `hashchange`.
document.addEventListener(
  'click',
  function (event) {
    if (
      event.target &&
      event.target instanceof HTMLAnchorElement &&
      event.target.href === location.href &&
      location.hash.length > 1
    ) {
      setImmediate(function () {
        if (!event.defaultPrevented) {
          hashchange()
        }
      })
    }
  },
  false
)

function hashchange() {
  /** @type {string | undefined} */
  let hash

  try {
    hash = decodeURIComponent(location.hash.slice(1)).toLowerCase()
  } catch {
    return
  }

  const name = 'user-content-' + hash
  const target =
    document.getElementById(name) || document.getElementsByName(name)[0]

  if (target) {
    setImmediate(function () {
      target.scrollIntoView()
    })
  }
}
```

### Example: math

Math can be enabled in rehype by using the plugins
[`rehype-katex`][rehype-katex] or [`rehype-mathjax`][rehype-mathjax].
The operate on `span`s and `div`s with certain classes and inject complex markup
and of inline styles, most of which this plugin will remove.
Say our module `example.js` contains:

```js
import rehypeKatex from 'rehype-katex'
import rehypeParse from 'rehype-parse'
import rehypeSanitize from 'rehype-sanitize'
import rehypeStringify from 'rehype-stringify'
import {unified} from 'unified'

const file = await unified()
  .use(rehypeParse, {fragment: true})
  .use(rehypeKatex)
  .use(rehypeSanitize)
  .use(rehypeStringify)
  .process('<span class="math math-inline">L</span>')

console.log(String(file))
```

Running that yields:

```html
<span><span><span>LL</span><span aria-hidden="true"><span><span></span><span>L</span></span></span></span></span>
```

It is possible to pass a schema which allows MathML and inline styles, but it
would be complex, and allows *all* inline styles, which is unsafe.
Alternatively, and arguably better, would be to *first* sanitize the HTML,
allowing only the specific classes that `rehype-katex` and `rehype-mathjax` use,
and *then* using those plugins:

```diff
@@ -1,7 +1,7 @@
 import rehypeKatex from 'rehype-katex'
 import rehypeParse from 'rehype-parse'
-import rehypeSanitize from 'rehype-sanitize'
+import rehypeSanitize, {defaultSchema} from 'rehype-sanitize'
 import rehypeStringify from 'rehype-stringify'
 import {unified} from 'unified'

 main()
@@ -9,8 +9,21 @@ main()
 const file = await unified()
   .use(rehypeParse, {fragment: true})
+  .use(rehypeSanitize, {
+    ...defaultSchema,
+    attributes: {
+      ...defaultSchema.attributes,
+      div: [
+        ...(defaultSchema.attributes.div || []),
+        ['className', 'math', 'math-display']
+      ],
+      span: [
+        ...(defaultSchema.attributes.span || []),
+        ['className', 'math', 'math-inline']
+      ]
+    }
+  })
   .use(rehypeKatex)
-  .use(rehypeSanitize)
   .use(rehypeStringify)
   .process('<span class="math math-inline">L</span>')
```

### Example: syntax highlighting

Highlighting, for example with [`rehype-highlight`][rehype-highlight], can be
solved similar to how math is solved (see previous example).
That is, use `rehype-sanitize` and allow the classes needed for highlighting,
and highlight afterwards:

```js
import rehypeHighlight from 'rehype-highlight'
import rehypeParse from 'rehype-parse'
import rehypeSanitize, {defaultSchema} from 'rehype-sanitize'
import rehypeStringify from 'rehype-stringify'
import {unified} from 'unified'

const file = await unified()
  .use(rehypeParse, {fragment: true})
  .use(rehypeSanitize, {
    ...defaultSchema,
    attributes: {
      ...defaultSchema.attributes,
      code: [
        ...(defaultSchema.attributes.code || []),
        // List of all allowed languages:
        ['className', 'language-js', 'language-css', 'language-md']
      ]
    }
  })
  .use(rehypeHighlight, {subset: false})
  .use(rehypeStringify)
  .process('<pre><code className="language-js">console.log(1)</code></pre>')

console.log(String(file))
```

Alternatively, it’s possible to make highlighting safe by allowing all the
classes used on tokens.
Modifying the above code like so:

```diff
 const file = await unified()
   .use(rehypeParse, {fragment: true})
+  .use(rehypeHighlight, {subset: false})
   .use(rehypeSanitize, {
     ...defaultSchema,
     attributes: {
       ...defaultSchema.attributes,
-      code: [
-        ...(defaultSchema.attributes.code || []),
-        // List of all allowed languages:
-        ['className', 'hljs', 'language-js', 'language-css', 'language-md']
+      span: [
+        ...(defaultSchema.attributes.span || []),
+        // List of all allowed tokens:
+        ['className', 'hljs-addition', 'hljs-attr', 'hljs-attribute', 'hljs-built_in', 'hljs-bullet', 'hljs-char', 'hljs-code', 'hljs-comment', 'hljs-deletion', 'hljs-doctag', 'hljs-emphasis', 'hljs-formula', 'hljs-keyword', 'hljs-link', 'hljs-literal', 'hljs-meta', 'hljs-name', 'hljs-number', 'hljs-operator', 'hljs-params', 'hljs-property', 'hljs-punctuation', 'hljs-quote', 'hljs-regexp', 'hljs-section', 'hljs-selector-attr', 'hljs-selector-class', 'hljs-selector-id', 'hljs-selector-pseudo', 'hljs-selector-tag', 'hljs-string', 'hljs-strong', 'hljs-subst', 'hljs-symbol', 'hljs-tag', 'hljs-template-tag', 'hljs-template-variable', 'hljs-title', 'hljs-type', 'hljs-variable'
+          ]
       ]
     }
   })
-  .use(rehypeHighlight, {subset: false})
   .use(rehypeStringify)
   .process('<pre><code className="language-js">console.log(1)</code></pre>')
```

## Types

This package is fully typed with [TypeScript][].
It exports the additional type [`Options`][api-options].

## Compatibility

Projects maintained by the unified collective are compatible with maintained
versions of Node.js.

When we cut a new major release, we drop support for unmaintained versions of
Node.
This means we try to keep the current release line, `rehype-sanitize@^6`,
compatible with Node.js 16.

This plugin works with `rehype-parse` version 3+, `rehype-stringify` version 3+,
`rehype` version 5+, and `unified` version 6+.

## Security

The defaults are safe but improper use of `rehype-sanitize` can open you up to a
[cross-site scripting (XSS)][xss] attack.

Use `rehype-sanitize` after the last unsafe thing: everything after
`rehype-sanitize` could be unsafe (but is fine if you do trust it).

## Related

*   [`hast-util-sanitize`](https://github.com/syntax-tree/hast-util-sanitize)
    — utility to sanitize [hast][]
*   [`rehype-format`](https://github.com/rehypejs/rehype-format)
    — format HTML
*   [`rehype-minify`](https://github.com/rehypejs/rehype-minify)
    — minify HTML

## Contribute

See [`contributing.md`][contributing] in [`rehypejs/.github`][health] for ways
to get started.
See [`support.md`][support] for ways to get help.

This project has a [code of conduct][coc].
By interacting with this repository, organization, or community you agree to
abide by its terms.

## License

[MIT][license] © [Titus Wormer][author]

<!-- Definitions -->

[build-badge]: https://github.com/rehypejs/rehype-sanitize/workflows/main/badge.svg

[build]: https://github.com/rehypejs/rehype-sanitize/actions

[coverage-badge]: https://img.shields.io/codecov/c/github/rehypejs/rehype-sanitize.svg

[coverage]: https://codecov.io/github/rehypejs/rehype-sanitize

[downloads-badge]: https://img.shields.io/npm/dm/rehype-sanitize.svg

[downloads]: https://www.npmjs.com/package/rehype-sanitize

[size-badge]: https://img.shields.io/bundlejs/size/rehype-sanitize

[size]: https://bundlejs.com/?q=rehype-sanitize

[sponsors-badge]: https://opencollective.com/unified/sponsors/badge.svg

[backers-badge]: https://opencollective.com/unified/backers/badge.svg

[collective]: https://opencollective.com/unified

[chat-badge]: https://img.shields.io/badge/chat-discussions-success.svg

[chat]: https://github.com/rehypejs/rehype/discussions

[esm]: https://gist.github.com/sindresorhus/a39789f98801d908bbc7ff3ecc99d99c

[esmsh]: https://esm.sh

[npm]: https://docs.npmjs.com/cli/install

[health]: https://github.com/rehypejs/.github

[contributing]: https://github.com/rehypejs/.github/blob/HEAD/contributing.md

[support]: https://github.com/rehypejs/.github/blob/HEAD/support.md

[coc]: https://github.com/rehypejs/.github/blob/HEAD/code-of-conduct.md

[license]: license

[author]: https://wooorm.com

[xss]: https://en.wikipedia.org/wiki/Cross-site_scripting

[typescript]: https://www.typescriptlang.org

[hast]: https://github.com/syntax-tree/hast

[hast-util-sanitize]: https://github.com/syntax-tree/hast-util-sanitize

[hast-util-sanitize-schema]: https://github.com/syntax-tree/hast-util-sanitize#schema

[rehype]: https://github.com/rehypejs/rehype

[rehype-katex]: https://github.com/remarkjs/remark-math/tree/main/packages/rehype-katex

[rehype-mathjax]: https://github.com/remarkjs/remark-math/tree/main/packages/rehype-mathjax

[rehype-highlight]: https://github.com/rehypejs/rehype-highlight

[unified]: https://github.com/unifiedjs/unified

[unified-transformer]: https://github.com/unifiedjs/unified?tab=readme-ov-file#transformer

[api-default-schema]: #defaultschema

[api-options]: #options

[api-rehype-sanitize]: #unifieduserehypesanitize-schema
