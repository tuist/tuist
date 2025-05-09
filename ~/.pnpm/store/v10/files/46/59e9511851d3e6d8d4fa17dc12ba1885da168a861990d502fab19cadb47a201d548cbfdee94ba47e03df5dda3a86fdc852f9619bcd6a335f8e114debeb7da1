import curry from "just-curry-it";


export const map = curry(function* (fn, iter) {
  for (const n of iter) {
    yield fn(n);
  }
});

export const asyncMap = curry(async function* (fn, iter) {
  for await (const n of iter) {
    yield fn(n);
  }
});

export const tap = curry(function* (fn, iter) {
  for (const n of iter) {
    fn(n);
    yield n;
  }
});

export const asyncTap = curry(async function* (fn, iter) {
  for await (const n of iter) {
    await fn(n);
    yield n;
  }
});

export const filter = curry(function* (fn, iter) {
  for (const n of iter) {
    if (fn(n)) {
      yield n;
    }
  }
});

export const asyncFilter = curry(async function* (fn, iter) {
  for await (const n of iter) {
    if (await fn(n)) {
      yield n;
    }
  }
});

export const scan = curry(function* (fn, acc, iter) {
  for (const item of iter) {
    acc = fn(acc, item);
    yield acc;
  }
});

export const asyncScan = curry(async function* (fn, acc, iter) {
  for await (const item of iter) {
    acc = await fn(acc, item);
    yield acc;
  }
});

export const flatten = function* (iter, depth = 1) {
  for (const n of iter) {
    if (depth > 0 && n !== null && typeof n !== "string" && n[Symbol.iterator]) {
      yield* flatten(n, depth - 1);
    } else {
      yield n;
    }
  }
};

export const asyncFlatten = async function* (iter, depth = 1) {
  for await (const n of iter) {
    if (depth > 0 && n !== null && typeof n !== "string" && (n[Symbol.asyncIterator] || n[Symbol.iterator])) {
      yield* asyncFlatten(n, depth - 1);
    } else {
      yield n;
    }
  }
};

export const drop = curry(function* (count, iter) {
  let index = 0;
  for (const item of iter) {
    if (index++ >= count) {
      yield item;
    }
  }
});

export const asyncDrop = curry(async function* (count, iter) {
  let index = 0;
  for await (const item of iter) {
    if (index++ >= count) {
      yield item;
    }
  }
});

export const dropWhile = curry(function* (fn, iter) {
  let dropping = true;
  for (const n of iter) {
    if (dropping) {
      if (fn(n)) {
        continue;
      } else {
        dropping = false;
      }
    }

    yield n;
  }
});

export const asyncDropWhile = curry(async function* (fn, iter) {
  let dropping = true;
  for await (const n of iter) {
    if (dropping) {
      if (await fn(n)) {
        continue;
      } else {
        dropping = false;
      }
    }

    yield n;
  }
});

export const take = curry(function* (count, iter) {
  const iterator = getIterator(iter);

  let current;
  while (count-- > 0 && !(current = iterator.next())?.done) {
    yield current.value;
  }
});

export const asyncTake = curry(async function* (count, iter) {
  const iterator = getAsyncIterator(iter);

  let current;
  while (count-- > 0 && !(current = await iterator.next())?.done) {
    yield current.value;
  }
});

export const takeWhile = curry(function* (fn, iter) {
  for (const n of iter) {
    if (fn(n)) {
      yield n;
    } else {
      break;
    }
  }
});

export const asyncTakeWhile = curry(async function* (fn, iter) {
  for await (const n of iter) {
    if (await fn(n)) {
      yield n;
    } else {
      break;
    }
  }
});

export const head = (iter) => {
  const iterator = getIterator(iter);
  const result = iterator.next();

  return result.done ? undefined : result.value;
};

export const asyncHead = async (iter) => {
  const iterator = getAsyncIterator(iter);
  const result = await iterator.next();

  return result.done ? undefined : result.value;
};

export const range = function* (from, to) {
  // eslint-disable-next-line no-unmodified-loop-condition
  for (let n = from; n < to || to === undefined; n++) {
    yield n;
  }
};

export const empty = function* () {}; // eslint-disable-line no-empty-function
export const asyncEmpty = async function* () {}; // eslint-disable-line no-empty-function

export const zip = function* (iter1, iter2) {
  for (const item1 of iter1) {
    yield [item1, iter2.next().value];
  }
};

export const asyncZip = async function* (iter1, iter2) {
  for await (const item1 of iter1) {
    yield [item1, (await iter2.next()).value];
  }
};

export const concat = function* (...iters) {
  for (const iter of iters) {
    yield* iter;
  }
};

export const asyncConcat = async function* (...iters) {
  for (const iter of iters) {
    yield* iter;
  }
};

export const reduce = curry((fn, acc, iter) => {
  for (const item of iter) {
    acc = fn(acc, item);
  }

  return acc;
});

export const asyncReduce = curry(async (fn, acc, iter) => {
  for await (const item of iter) {
    acc = await fn(acc, item);
  }

  return acc;
});

export const every = curry((fn, iter) => {
  for (const item of iter) {
    if (!fn(item)) {
      return false;
    }
  }

  return true;
});

export const asyncEvery = curry(async (fn, iter) => {
  for await (const item of iter) {
    if (!await fn(item)) {
      return false;
    }
  }

  return true;
});

export const some = curry((fn, iter) => {
  for (const item of iter) {
    if (fn(item)) {
      return true;
    }
  }

  return false;
});

export const asyncSome = curry(async (fn, iter) => {
  for await (const item of iter) {
    if (await fn(item)) {
      return true;
    }
  }

  return false;
});

export const find = curry((fn, iter) => {
  for (const item of iter) {
    if (fn(item)) {
      return item;
    }
  }
});

export const asyncFind = curry(async (fn, iter) => {
  for await (const item of iter) {
    if (await fn(item)) {
      return item;
    }
  }
});

export const count = (iter) => reduce((count) => count + 1, 0, iter);
export const asyncCount = (iter) => asyncReduce((count) => count + 1, 0, iter);

export const collectArray = (iter) => [...iter];
export const asyncCollectArray = async (iter) => {
  const result = [];
  for await (const item of iter) {
    result.push(item);
  }

  return result;
};

export const collectSet = (iter) => {
  const result = new Set();
  for (const item of iter) {
    result.add(item);
  }

  return result;
};

export const asyncCollectSet = async (iter) => {
  const result = new Set();
  for await (const item of iter) {
    result.add(item);
  }

  return result;
};

export const collectMap = (iter) => {
  const result = new Map();
  for (const [key, value] of iter) {
    result.set(key, value);
  }

  return result;
};

export const asyncCollectMap = async (iter) => {
  const result = new Map();
  for await (const [key, value] of iter) {
    result.set(key, value);
  }

  return result;
};

export const collectObject = (iter) => {
  const result = Object.create(null);
  for (const [key, value] of iter) {
    result[key] = value;
  }

  return result;
};

export const asyncCollectObject = async (iter) => {
  const result = Object.create(null);
  for await (const [key, value] of iter) {
    result[key] = value;
  }

  return result;
};

export const join = curry((separator, iter) => {
  let result = head(iter) || "";

  for (const n of iter) {
    result += separator + n;
  }

  return result;
});

export const asyncJoin = curry(async (separator, iter) => {
  let result = await asyncHead(iter) || "";

  for await (const n of iter) {
    result += separator + n;
  }

  return result;
});

const getIterator = (iter) => {
  if (typeof iter?.[Symbol.iterator] === "function") {
    return iter[Symbol.iterator]();
  } else {
    throw TypeError("`iter` is not iterable");
  }
};

const getAsyncIterator = (iter) => {
  if (typeof iter?.[Symbol.asyncIterator] === "function") {
    return iter[Symbol.asyncIterator]();
  } else if (typeof iter?.[Symbol.iterator] === "function") {
    return iter[Symbol.iterator]();
  } else {
    throw TypeError("`iter` is not iterable");
  }
};

export const pipe = (acc, ...fns) => reduce((acc, fn) => fn(acc), acc, fns);
