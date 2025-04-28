# JSON Pointer

This is an implementation of RFC-6901 JSON Pointer. JSON Pointer is designed for
referring to data values within a JSON document. It's designed to be URL
friendly so it can be used as a URL fragment that points to a specific part of
the JSON document.

## Installation

Includes support for node.js (ES Modules, TypeScript) and browsers.

```bash
npm install @hyperjump/json-pointer
```

## Usage

```javascript
import * as JsonPointer from "@hyperjump/json-pointer";

const value = {
  "foo": {
    "bar": 42
  }
};

// Construct pointers
const fooPointer = JsonPointer.append("foo", JsonPointer.nil); // "/foo"
const fooBarPointer = JsonPointer.append(fooPointer, "bar"); // "/foo/bar"

// Get a value from a pointer
const getFooBar = JsonPointer.get(fooBarPointer);
getFooBar(value); // 42

// Set a value from a pointer
// New value is returned without modifying the original
const setFooBar = JsonPointer.set(fooBarPointer);
setFooBar(value, 33); // { "foo": { "bar": 33 } }

// Assign a value from a pointer
// The original value is changed and no value is returned
const assignFooBar = JsonPointer.assign(fooBarPointer);
assignFooBar(value, 33); // { "foo": { "bar": 33 } }

// Unset a value from a pointer
// New value is returned without modifying the original
const unsetFooBar = JsonPointer.unset(fooBarPointer);
setFooBar(value); // { "foo": {} }

// Delete a value from a pointer
// The original value is changed and no value is returned
const deleteFooBar = JsonPointer.remove(fooBarPointer);
deleteFooBar(value); // { "foo": {} }
```

## API

* **nil**: ""

    The empty pointer.
* **pointerSegments**: (pointer: string) => Generator\<string>

    An iterator for the segments of a JSON Pointer that handles escaping.
* **append**: (segment: string, pointer: string) => string

    Append a segment to a JSON Pointer.
* **get**: (pointer: string, subject: any) => any

    Use a JSON Pointer to get a value. This function can be curried.
* **set**: (pointer: string, subject: any, value: any) => any

    Immutably set a value using a JSON Pointer. Returns a new version of
    `subject` with the value set. The original `subject` is not changed, but the
    value isn't entirely cloned. Values that aren't changed will point to
    the same value as the original. This function can be curried.
* **assign**: (pointer: string, subject: any, value: any) => void

    Mutate a value using a JSON Pointer. This function can be curried.
* **unset**: (pointer: string, subject: any) => any

    Immutably delete a value using a JSON Pointer. Returns a new version of
    `subject` without the value. The original `subject` is not changed, but the
    value isn't entirely cloned. Values that aren't changed will point to the
    same value as the original. This function can be curried.
* **remove**: (pointer: string, subject: any) => void

    Delete a value using a JSON Pointer. This function can be curried.

## Contributing

### Tests

Run the tests

```bash
npm test
```

Run the tests with a continuous test runner
```bash
npm test -- --watch
```
