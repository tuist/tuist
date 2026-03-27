// Zag.js does not offer a vanilla JS package, just a reference implementation.
// This file has been adapted for our project structure and was originally taken from their repository.
// Source: https://github.com/chakra-ui/zag/blob/e5ba28a01ccab8afa2f11a82b67031a82e2675f5/examples/vanilla-ts/src/lib/bindable.ts
//
// MIT License
//
// Copyright (c) 2021 Chakra UI
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
import { proxy } from "@zag-js/store";
import { isFunction } from "@zag-js/utils";

export function bindable(props) {
  const initial = props().value ?? props().defaultValue;

  if (props().debug) {
    console.log(`[bindable > ${props().debug}] initial`, initial);
  }

  const eq = props().isEqual ?? Object.is;

  const store = proxy({ value: initial });

  const controlled = () => props().value !== undefined;

  return {
    initial,
    ref: store,
    get() {
      return controlled() ? props().value : store.value;
    },
    set(nextValue) {
      const prev = store.value;
      const next = isFunction(nextValue) ? nextValue(prev) : nextValue;

      if (props().debug) {
        console.log(`[bindable > ${props().debug}] setValue`, { next, prev });
      }

      if (!controlled()) store.value = next;
      if (!eq(next, prev)) {
        props().onChange?.(next, prev);
      }
    },
    invoke(nextValue, prevValue) {
      props().onChange?.(nextValue, prevValue);
    },
    hash(value) {
      return props().hash?.(value) ?? String(value);
    },
  };
}
