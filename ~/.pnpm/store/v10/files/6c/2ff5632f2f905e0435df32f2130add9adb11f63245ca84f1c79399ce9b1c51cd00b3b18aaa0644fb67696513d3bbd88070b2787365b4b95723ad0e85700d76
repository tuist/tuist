# hast-util-sanitize

[![Build][build-badge]][build]
[![Coverage][coverage-badge]][coverage]
[![Downloads][downloads-badge]][downloads]
[![Size][size-badge]][size]
[![Sponsors][sponsors-badge]][collective]
[![Backers][backers-badge]][collective]
[![Chat][chat-badge]][chat]

[hast][] utility to make trees safe.

## Contents

* [What is this?](#what-is-this)
* [When should I use this?](#when-should-i-use-this)
* [Install](#install)
* [Use](#use)
* [API](#api)
  * [`defaultSchema`](#defaultschema)
  * [`sanitize(tree[, options])`](#sanitizetree-options)
  * [`Schema`](#schema)
* [Types](#types)
* [Compatibility](#compatibility)
* [Security](#security)
* [Related](#related)
* [Contribute](#contribute)
* [License](#license)

## What is this?

This package is a utility that can make a tree that potentially contains
dangerous user content safe for use.
It defaults to what GitHub does to clean unsafe markup, but you can change that.

## When should I use this?

This package is needed whenever you deal with potentially dangerous user
content.

The plugin [`rehype-sanitize`][rehype-sanitize] wraps this utility to also
sanitize HTML at a higher-level (easier) abstraction.

## Install

This package is [ESM only][esm].
In Node.js (version 16+), install with [npm][]:

```sh
npm install hast-util-sanitize
```

In Deno with [`esm.sh`][esmsh]:

```js
import {sanitize} from 'https://esm.sh/hast-util-sanitize@5'
```

In browsers with [`esm.sh`][esmsh]:

```html
<script type="module">
  import {sanitize} from 'https://esm.sh/hast-util-sanitize@5?bundle'
</script>
```

## Use

```js
import {h} from 'hastscript'
import {sanitize} from 'hast-util-sanitize'
import {toHtml} from 'hast-util-to-html'
import {u} from 'unist-builder'

const unsafe = h('div', {onmouseover: 'alert("alpha")'}, [
  h(
    'a',
    {href: 'jAva script:alert("bravo")', onclick: 'alert("charlie")'},
    'delta'
  ),
  u('text', '\n'),
  h('script', 'alert("charlie")'),
  u('text', '\n'),
  h('img', {src: 'x', onerror: 'alert("delta")'}),
  u('text', '\n'),
  h('iframe', {src: 'javascript:alert("echo")'}),
  u('text', '\n'),
  h('math', h('mi', {'xlink:href': 'data:x,<script>alert("foxtrot")</script>'}))
])

const safe = sanitize(unsafe)

console.log(toHtml(unsafe))
console.log(toHtml(safe))
```

Unsafe:

```html
<div onmouseover="alert(&#x22;alpha&#x22;)"><a href="jAva script:alert(&#x22;bravo&#x22;)" onclick="alert(&#x22;charlie&#x22;)">delta</a>
<script>alert("charlie")</script>
<img src="x" onerror="alert(&#x22;delta&#x22;)">
<iframe src="javascript:alert(&#x22;echo&#x22;)"></iframe>
<math><mi xlink:href="data:x,<script>alert(&#x22;foxtrot&#x22;)</script>"></mi></math></div>
```

Safe:

```html
<div><a>delta</a>

<img src="x">

</div>
```

## API

This package exports the identifiers [`defaultSchema`][api-default-schema] and
[`sanitize`][api-sanitize].
There is no default export.

### `defaultSchema`

Default schema ([`Schema`][api-schema]).

Follows [GitHub][] style sanitation.

### `sanitize(tree[, options])`

Sanitize a tree.

###### Parameters

* `tree` ([`Node`][node])
  — unsafe tree
* `options` ([`Schema`][api-schema], default:
  [`defaultSchema`][api-default-schema])
  — configuration

###### Returns

New, safe tree ([`Node`][node]).

### `Schema`

Schema that defines what nodes and properties are allowed.

The default schema is [`defaultSchema`][api-default-schema], which follows how
GitHub cleans.
If any top-level key is missing in the given schema, the corresponding
value of the default schema is used.

To extend the standard schema with a few changes, clone `defaultSchema`
like so:

```js
import deepmerge from 'deepmerge'
import {h} from 'hastscript'
import {defaultSchema, sanitize} from 'hast-util-sanitize'

// This allows `className` on all elements.
const schema = deepmerge(defaultSchema, {attributes: {'*': ['className']}})

const tree = sanitize(h('div', {className: ['foo']}), schema)

// `tree` still has `className`.
console.log(tree)
// {
//   type: 'element',
//   tagName: 'div',
//   properties: {className: ['foo']},
//   children: []
// }
```

##### Fields

###### `allowComments`

Whether to allow comment nodes (`boolean`, default: `false`).

For example:

```js
allowComments: true
```

###### `allowDoctypes`

Whether to allow doctype nodes (`boolean`, default: `false`).

For example:

```js
allowDoctypes: true
```

###### `ancestors`

Map of tag names to a list of tag names which are required ancestors
(`Record<string, Array<string>>`, default: `defaultSchema.ancestors`).

Elements with these tag names will be ignored if they occur outside of one
of their allowed parents.

For example:

```js
ancestors: {
  tbody: ['table'],
  // …
  tr: ['table']
}
```

###### `attributes`

Map of tag names to allowed [property names][name]
(`Record<string, Array<[string, ...Array<RegExp | boolean | number | string>] | string>`,
default: `defaultSchema.attributes`).

The special key `'*'` as a tag name defines property names allowed on all
elements.

The special value `'data*'` as a property name can be used to allow all `data`
properties.

For example:

```js
attributes: {
  a: [
    'ariaDescribedBy', 'ariaLabel', 'ariaLabelledBy', /* … */, 'href'
  ],
  // …
  '*': [
    'abbr',
    'accept',
    'acceptCharset',
    // …
    'vAlign',
    'value',
    'width'
  ]
}
```

Instead of a single string in the array, which allows any property value for
the field, you can use an array to allow several values.
For example, `input: ['type']` allows `type` set to any value on `input`s.
But `input: [['type', 'checkbox', 'radio']]` allows `type` when set to
`'checkbox'` or `'radio'`.

You can use regexes, so for example `span: [['className', /^hljs-/]]` allows
any class that starts with `hljs-` on `span`s.

When comma- or space-separated values are used (such as `className`), each
value in is checked individually.
For example, to allow certain classes on `span`s for syntax highlighting, use
`span: [['className', 'number', 'operator', 'token']]`.
This will allow `'number'`, `'operator'`, and `'token'` classes, but drop
others.

###### `clobber`

List of [*property names*][name] that clobber (`Array<string>`, default:
`defaultSchema.clobber`).

For example:

```js
clobber: ['ariaDescribedBy', 'ariaLabelledBy', 'id', 'name']
```

###### `clobberPrefix`

Prefix to use before clobbering properties (`string`, default:
`defaultSchema.clobberPrefix`).

For example:

```js
clobberPrefix: 'user-content-'
```

###### `protocols`

Map of [*property names*][name] to allowed protocols
(`Record<string, Array<string>>`, default: `defaultSchema.protocols`).

This defines URLs that are always allowed to have local URLs (relative to
the current website, such as `this`, `#this`, `/this`, or `?this`), and
only allowed to have remote URLs (such as `https://example.com`) if they
use a known protocol.

For example:

```js
protocols: {
  cite: ['http', 'https'],
  // …
  src: ['http', 'https']
}
```

###### `required`

Map of tag names to required [*property names*][name] with a default value
(`Record<string, Record<string, unknown>>`, default: `defaultSchema.required`).

This defines properties that must be set.
If a field does not exist (after the element was made safe), these will be
added with the given value.

For example:

```js
required: {
  input: {disabled: true, type: 'checkbox'}
}
```

> 👉 **Note**: properties are first checked based on `schema.attributes`,
> then on `schema.required`.
> That means properties could be removed by `attributes` and then added
> again with `required`.

###### `strip`

List of tag names to strip from the tree (`Array<string>`, default:
`defaultSchema.strip`).

By default, unsafe elements (those not in `schema.tagNames`) are replaced by
what they contain.
This option can drop their contents.

For example:

```js
strip: ['script']
```

###### `tagNames`

List of allowed tag names (`Array<string>`, default: `defaultSchema.tagNames`).

For example:

```js
tagNames: [
  'a',
  'b',
  // …
  'ul',
  'var'
]
```

## Types

This package is fully typed with [TypeScript][].
It exports the additional type [`Schema`][api-schema].

## Compatibility

Projects maintained by the unified collective are compatible with maintained
versions of Node.js.

When we cut a new major release, we drop support for unmaintained versions of
Node.
This means we try to keep the current release line, `hast-util-sanitize@^5`,
compatible with Node.js 16.

## Security

By default, `hast-util-sanitize` will make everything safe to use.
Assuming you understand that certain attributes (including a limited set of
classes) can be generated by users, and you write your CSS (and JS)
accordingly.
When used incorrectly, deviating from the defaults can open you up to a
[cross-site scripting (XSS)][xss] attack.

Use `hast-util-sanitize` after the last unsafe thing: everything after it could
be unsafe (but is fine if you do trust it).

## Related

* [`rehype-sanitize`](https://github.com/rehypejs/rehype-sanitize)
  — rehype plugin

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

[build-badge]: https://github.com/syntax-tree/hast-util-sanitize/workflows/main/badge.svg

[build]: https://github.com/syntax-tree/hast-util-sanitize/actions

[coverage-badge]: https://img.shields.io/codecov/c/github/syntax-tree/hast-util-sanitize.svg

[coverage]: https://codecov.io/github/syntax-tree/hast-util-sanitize

[downloads-badge]: https://img.shields.io/npm/dm/hast-util-sanitize.svg

[downloads]: https://www.npmjs.com/package/hast-util-sanitize

[size-badge]: https://img.shields.io/badge/dynamic/json?label=minzipped%20size&query=$.size.compressedSize&url=https://deno.bundlejs.com/?q=hast-util-sanitize

[size]: https://bundlejs.com/?q=hast-util-sanitize

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

[hast]: https://github.com/syntax-tree/hast

[node]: https://github.com/syntax-tree/hast#nodes

[name]: https://github.com/syntax-tree/hast#propertyname

[github]: https://github.com/gjtorikian/html-pipeline/blob/a2e02ac/lib/html_pipeline/sanitization_filter.rb

[xss]: https://en.wikipedia.org/wiki/Cross-site_scripting

[rehype-sanitize]: https://github.com/rehypejs/rehype-sanitize

[api-default-schema]: #defaultschema

[api-sanitize]: #sanitizetree-options

[api-schema]: #schema
