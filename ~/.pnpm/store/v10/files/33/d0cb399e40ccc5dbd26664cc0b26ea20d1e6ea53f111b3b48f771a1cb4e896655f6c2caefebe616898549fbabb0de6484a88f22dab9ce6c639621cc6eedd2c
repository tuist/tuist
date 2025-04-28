<div align="center">

![Microdiff Logo](https://raw.githubusercontent.com/AsyncBanana/microdiff/master/Logo.svg)

Microdiff is a tiny (<1kb), fast, zero dependency object and array comparison library. It is significantly faster than most other deep comparison libraries, and has full TypeScript support.

> 💡 I recommend reading this blog post:
>
> **[Building the fastest object and array differ](https://byteofdev.com/posts/microdiff/)** for an explanation of how Microdiff achieves its size and speed.

![Minizipped Size (from Bundlephobia)](https://img.shields.io/bundlephobia/minzip/microdiff?style=flat-square) ![License](https://img.shields.io/npm/l/microdiff?style=flat-square) ![dependency Count](https://img.shields.io/badge/dependencies-0-green?style=flat-square)

</div>

# Features

- 🚀 More than double the speed of other object diff libraries
- 📦 Extremely lightweight, <1kb minified
- 🌎 Supports Deno, Node, Bun, the web, and even service workers. Also comes with built-in Typescript types
- 🔰 Very easy to use, having just a single `diff()` function
- 📅 Full support for objects like `new Date()` and `new RegExp()`

# Get started

First, install Microdiff

```
npm i microdiff
```

If you are using Deno, you can import it from Deno.land with the link `https://deno.land/x/microdiff@VERSION/index.ts` (remember to change `@VERSION` to the version you want to use).

After you install it, import it and run it on two objects.

```js
import diff from "microdiff";

const obj1 = {
	originalProperty: true,
};
const obj2 = {
	originalProperty: true,
	newProperty: "new",
};

console.log(diff(obj1, obj2));
// [{type: "CREATE", path: ["newProperty"], value: "new"}]
```

If you are using CommonJS, you can import it like this:

```js
const diff = require("microdiff").default;
```

There are three different types of changes: `CREATE`, `REMOVE`, and `CHANGE`.
The `path` property gives a path to the property in the new object (or the old object in the case of `REMOVE`).
Each element in the paths is a key to the next property a level deeper until you get to the property changed, and it is a string or a number, depending on whether the object is an Array or Object (Objects with number keys will still be strings).
The `value` property exists in types `CREATE` and `CHANGE`, and it contains the value of the property added/changed/deleted.
The `oldValue` property exists in the type `CHANGE` and `REMOVE`, and it contains the old value of the property.

# Cycles support

By default, Microdiff supports cyclical references, but if you are sure that the object has no cycles like parsed JSON, you can disable cycles using the `cyclesFix` option.

```js
diff(obj1, obj2, { cyclesFix: false });
```

# Benchmarks

```
Geometric mean of time per operation relative to Microdiff (no cycles) (100%==equal time, lower is better)
microdiff (no cycles): 100%
microdiff: 149%
deep-diff: 197%
deep-object-diff: 288%
jsDiff: 1565%
```

These results are from a suite of benchmarks matching real world use cases of multiple open-source repos using various diffing algorithm, running under Node 22.12.0 on a Ryzen 7950x clocked at ~4.30 GHz. The benchmarks are run through [mitata](https://github.com/evanwashere/mitata) to minimize random variation and time most accurately. You can view the full benchmark code in [bench.js](https://github.com/AsyncBanana/microdiff/blob/master/bench.js) and the benchmarks themselves at [benchmarks/applied](https://github.com/AsyncBanana/microdiff/tree/master/benchmarks/applied).

Of course, [these benchmarks should be taken with a grain of salt](https://byteofdev.com/posts/javascript-benchmarking-mess/) due to the inherent errors present in benchmarking JavaScript, but if you want to run them on your own computer in your own runtime/setup, run `bench.js`.

# Contributing

Thanks for helping the project out! Contributing is pretty simple. Fork the repository (if you need more information on how to do this, check out [this GitHub guide](https://docs.github.com/en/get-started/quickstart/contributing-to-projects)), clone it to your computer, and start programming! To compile the program, run `npm run build` (replace `npm` with `pnpm` or `yarn` if you are using one of those). This will create CommonJS and ESM modules in `/dist`.

To benchmark microdiff, you can run `npm run bench`. This will automatically build Microdiff and run a benchmarking program comparing microdiff to other common diffing libraries.

Finally, Microdiff has an extensive test suite which you should take advantage of. To make sure everything is working correctly, you can run `npm run test`. `npm run test` builds the project and then runs the entire test suite on the new version. If you are fixing a bug, be sure to add a test for that.
Also, make sure you read the [Code of Conduct](https://github.com/AsyncBanana/microdiff/blob/master/CODE_OF_CONDUCT.md) before contributing.
