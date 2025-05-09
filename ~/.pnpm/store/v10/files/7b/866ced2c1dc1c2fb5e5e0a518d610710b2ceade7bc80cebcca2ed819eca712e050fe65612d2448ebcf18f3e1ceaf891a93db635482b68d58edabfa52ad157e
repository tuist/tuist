# json-stringify-deterministic

![Last version](https://img.shields.io/github/tag/Kikobeats/json-stringify-deterministic.svg?style=flat-square)
[![Coverage Status](https://img.shields.io/coveralls/Kikobeats/json-stringify-deterministic.svg?style=flat-square)](https://coveralls.io/github/Kikobeats/json-stringify-deterministic)
[![NPM Status](https://img.shields.io/npm/dm/json-stringify-deterministic.svg?style=flat-square)](https://www.npmjs.org/package/json-stringify-deterministic)

> Deterministic version of `JSON.stringify()`, so you can get a consistent hash from stringified results.

Similar to [json-stable-stringify](https://github.com/substack/json-stable-stringify) *but*:

- No Dependencies. Minimal as possible.
- Better cycles detection.
- Support serialization for object without `.toJSON` (such as `RegExp`).
- Provides built-in TypeScript declarations.

## Install

```bash
npm install json-stringify-deterministic --save
```

## Usage

```js
const stringify = require('json-stringify-deterministic')
const obj = { c: 8, b: [{ z: 6, y: 5, x: 4 }, 7], a: 3 }

console.log(stringify(obj))
// => {"a":3,"b":[{"x":4,"y":5,"z":6},7],"c":8}
```

## API

### stringify(&lt;obj&gt;, [opts])

#### obj

*Required*<br>
Type: `object`

The input `object` to be serialized.

#### opts

##### opts.stringify

Type: `function`
Default: `JSON.stringify`

Determinate how to stringify primitives values.

##### opts.cycles

Type: `boolean`
Default: `false`

Determinate how to resolve cycles.

Under `true`, when a cycle is detected, `[Circular]` will be inserted in the node.

##### opts.compare

Type: `function`

Custom comparison function for object keys.

Your function `opts.compare` is called with these parameters:

``` js
opts.cmp({ key: akey, value: avalue }, { key: bkey, value: bvalue })
```

For example, to sort on the object key names in reverse order you could write:

``` js
const stringify = require('json-stringify-deterministic')

const obj = { c: 8, b: [{z: 6,y: 5,x: 4}, 7], a: 3 }
const objSerializer = stringify(obj, function (a, b) {
  return a.key < b.key ? 1 : -1
})

console.log(objSerializer)
// => {"c":8,"b":[{"z":6,"y":5,"x":4},7],"a":3}
```

Or if you wanted to sort on the object values in reverse order, you could write:

```js
const stringify = require('json-stringify-deterministic')

const obj = { d: 6, c: 5, b: [{ z: 3, y: 2, x: 1 }, 9], a: 10 }
const objtSerializer = stringify(obj, function (a, b) {
  return a.value < b.value ? 1 : -1
})

console.log(objtSerializer)
// => {"d":6,"c":5,"b":[{"z":3,"y":2,"x":1},9],"a":10}
```

##### opts.space

Type: `string`<br>
Default: `''`

If you specify `opts.space`, it will indent the output for pretty-printing.

Valid values are strings (e.g. `{space: \t}`). For example:

```js
const stringify = require('json-stringify-deterministic')

const obj = { b: 1, a: { foo: 'bar', and: [1, 2, 3] } }
const objSerializer = stringify(obj, { space: '  ' })
console.log(objSerializer)
// => {
//   "a": {
//     "and": [
//       1,
//       2,
//       3
//     ],
//     "foo": "bar"
//   },
//   "b": 1
// }
```

##### opts.replacer

Type: `function`<br>

The replacer parameter is a function `opts.replacer(key, value)` that behaves
the same as the replacer
[from the core JSON object](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Using_native_JSON#The_replacer_parameter).

## Related

- [sort-keys-recursive](https://github.com/Kikobeats/sort-keys-recursive): Sort the keys of an array/object recursively.

## License

MIT © [Kiko Beats](https://github.com/Kikobeats).
