<h1 align='center'>packrup</h1>

<p align="center">
<a href='https://github.com/harlan-zw/packrup/actions/workflows/test.yml'>
</a>
<a href="https://www.npmjs.com/package/packrup" target="__blank"><img src="https://img.shields.io/npm/v/packrup?style=flat&colorA=002438&colorB=28CF8D" alt="NPM version"></a>
<a href="https://www.npmjs.com/package/packrup" target="__blank"><img alt="NPM Downloads" src="https://img.shields.io/npm/dm/packrup?flat&colorA=002438&colorB=28CF8D"></a>
<a href="https://github.com/harlan-zw/packrup" target="__blank"><img alt="GitHub stars" src="https://img.shields.io/github/stars/harlan-zw/packrup?flat&colorA=002438&colorB=28CF8D"></a>
</p>

<p align="center">
Simple utils to pack (and unpack) arrays and strings to a flat object.
</p>

<p align="center">
<table>
<tbody>
<td align="center">
<img width="800" height="0" /><br>
<i>Status:</i> Stable</b> <br>
<sup> Please report any issues 🐛</sup><br>
<sub>Made possible by my <a href="https://github.com/sponsors/harlan-zw">Sponsor Program 💖</a><br> Follow me <a href="https://twitter.com/harlan_zw">@harlan_zw</a> 🐦 • Join <a href="https://discord.gg/275MBUBvgP">Discord</a> for help</sub><br>
<img width="800" height="0" />
</td>
</tbody>
</table>
</p>

## Background

The [zhead](https://github.com/harlan-zw/zhead) package provides a flat-object style API for HTML `<meta>` tags,
to make this happen we need to pack and unpack arrays and strings to a flat object.

For example, the following object:

```json
{
  "viewport": {
    "content": {
      "width": "device-width",
      "initial-scale": "1"
    }
  }
}
```

Can be packed to the below (and vice versa):

```html
<meta name="viewport" content="width=device-width, initial-scale=1">
```

For an example see [useSeoMeta](https://github.com/unjs/unhead/blob/main/packages/shared/src/meta.ts).

## Features

- Pack arrays, objects and strings to a flat object
- Handles duplicates with `key`
- Supports nested key selections with `dot.notation`
- 🌳 Composable, tree-shakable and tiny (< 1kb, see [export-size-report](https://github.com/harlan-zw/packrup/blob/main/export-size-report.json))

## Help Wanted

These utils were meant to be fully typed, but I struggled with the implementation. If you want a fun TypeScript challenge
then please open a PR :).

## Installation

```bash
npm install --save-dev packrup

# Using yarn
yarn add --dev packrup
```

## API

### packArray

**Arguments**

- _input_ - `array`

  The array to pack

- _options_ -  `{ key: string | string[], value: string | string[] }`

  The options to use to resolve the key and value.
  By default, will choose first 2 keys of an object.

```ts
import { packArray } from 'packrup'

packArray([
  { 'http-equiv': 'content-security-policy', 'content': 'content-src none' }
])

// {
//    'content-security-policy': 'content-src none',
// }
```

### packObject

**Arguments**

- _input_ - `object`

  The record to pack.

- _options_ -  `{ key: string | string[], value: string | string[] }`

  The options to use to resolve the key and value.
  By default, will choose first 2 keys of an object.

```ts
import { packObject } from 'packrup'

packObject({
  image: {
    src: {
      '1x': 'https://example.com/image.png',
      '2x': 'https://example.com/image@2x.png'
    },
    alt: 'Example Image'
  },
}, {
  key: 'image.src.1x',
  value: 'image.alt'
})

// {
//   "https://example.com/image.png": "Example Image",
// }
```

### packString

```ts
import { packString } from 'packrup'

const head = packString('src="https://example.com/image.jpg" width="800" height="600"')
// {
//   "height": "600",
//   "src": "https://example.com/image.jpg",
//   "width": "800",
// }
```

### unpackToArray

**Arguments**

- _input_ - `array`

  The array to pack

- _options_ -  `{ key: string | string[], value: string | string[] }`

  The options to use to resolve the key and value.
  By default, will choose first 2 keys of an object.

```ts
import { unpackToArray } from 'packrup'

unpackToArray({
  'content-security-policy': 'content-src none',
}, { key: 'http-equiv', value: 'content' })
```

### unpackToString

**Arguments**

- _input_ - `object`

  The record to unpack to a string.

- _options_

```ts
export interface TransformValueOptions {
  entrySeparator?: string
  keyValueSeparator?: string
  wrapValue?: string
  resolve?: (ctx: { key: string, value: unknown }) => string | void
}
```

```ts
import { unpackToString } from 'packrup'

unpackToString({
  'noindex': true,
  'nofollow': true,
  'max-snippet': 20,
  'maxi-image-preview': 'large',
}, {
  resolve({ key, value }) {
    if (typeof value === 'boolean')
      return `${key}`
  },
  keyValueSeparator: ':',
  entrySeparator: ', ',
})

// "noindex, nofollow, max-snippet:20, maxi-image-preview:large"
```

## Sponsors

<p align="center">
  <a href="https://raw.githubusercontent.com/harlan-zw/static/main/sponsors.svg">
    <img src='https://raw.githubusercontent.com/harlan-zw/static/main/sponsors.svg'/>
  </a>
</p>

## License

MIT License © 2022-PRESENT [Harlan Wilton](https://github.com/harlan-zw)
