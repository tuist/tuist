/**
Like [`Object.keys()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/keys) but also includes [symbols](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Symbol)

@example
```
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
*/
export default function getOwnEnumerableKeys(object: object): Array<string | symbol>; // eslint-disable-line @typescript-eslint/ban-types
