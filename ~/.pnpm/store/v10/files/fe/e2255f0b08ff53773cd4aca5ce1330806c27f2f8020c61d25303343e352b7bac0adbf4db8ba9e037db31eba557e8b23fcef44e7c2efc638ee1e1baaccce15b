# get-own-enumerable-keys

> Like [`Object.keys()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/keys) but also includes [symbols](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Symbol)

`Object.keys()` returns the own enumerable keys of an object except symbols (for legacy reasons). This package includes symbols too.

Use [`Reflect.ownKeys()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Reflect/ownKeys) if you also want non-enumerable keys.

## Install

```sh
npm install get-own-enumerable-keys
```

## Usage

```js
import getOwnEnumerableKeys from 'get-own-enumerable-keys';

const symbol = Symbol('x');

const object = {
	foo: true,
	[symbol]: true,
};

Object.keys(object);
// ['foo']

getOwnEnumerableKeys(object);
//=> ['foo', Symbol('x')]
```
