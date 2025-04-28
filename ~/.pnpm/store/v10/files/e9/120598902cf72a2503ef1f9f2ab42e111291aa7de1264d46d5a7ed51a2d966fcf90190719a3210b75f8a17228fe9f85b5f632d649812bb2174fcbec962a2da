[![npm](https://img.shields.io/npm/v/ts-deepmerge)](https://www.npmjs.com/package/ts-deepmerge)

TypeScript Deep Merge
=====================

A deep merge function that automatically infers the return type based on your input,
without mutating the source objects.

Objects and arrays will be merged, but values such as numbers and strings will be overwritten.

All merging/overwriting occurs in the order of the arguments you provide the function with.

Both ESM and CommonJS are supported by this package.


Usage
-----
```typescript jsx
import { merge } from "ts-deepmerge";

const obj1 = {
  a: {
    a: 1
  }
};

const obj2 = {
  b: {
    a: 2,
    b: 2
  }
};

const obj3 = {
  a: {
    b: 3
  },
  b: {
    b: 3,
    c: 3
  },
  c: 3
};

const result = merge(obj1, obj2, obj3);
```

The value of the above `result` is:
```json
{
  "a": {
    "a": 1,
    "b": 3
  },
  "b": {
    "a": 2,
    "b": 3,
    "c": 3
  },
  "c": 3
}
```

### With options

If you would like to provide options to change the merge behaviour, you can use the `.withOptions` method:
```typescript
import { merge } from "ts-deepmerge";

const obj1 = {
  array: ["A"],
};

const obj2 = {
  array: ["B"],
}

const result = merge.withOptions(
  { mergeArrays: false },
  obj1,
  obj2
);
```

The value of the above `result` is:
```json
{
  "array": ["B"]
}
```

All options have JSDoc descriptions [in its source](/src/index.ts#L87).


### When working with generic declared types/interfaces

There's currently a limitation with the inferred return type that `ts-deepmerge` offers, where it's
unable to take the order of the objects/properties into consideration due to the nature of accepting
an infinite number of objects to merge as args and what TypeScript currently offers to infer the types.
The primary use case for the inferred return type is for basic object primitives, to offer something
more useful as the return type, which does work for a lot of cases.

If you're working with generic declared types though, this can cause the inferred return type to not align
with what you may expect, as it currently detects every possible value and combines them as a union type.
When working with declared types, and you know what the final type will align to, simply use the `as` keyword
as shown in the example below:
```typescript
interface IObj {
  a: string;
  b: string;
}

const obj1: IObj = { a: "1", b: "2", };
const obj2: Partial<IObj> = { a: "1" };

const result = merge(obj1, obj2) as IObj;
```

More context can be found in [this issue](https://github.com/voodoocreation/ts-deepmerge/issues/30).
