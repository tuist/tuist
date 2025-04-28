export const map: (
  <A, B>(fn: Mapper<A, B>, iterator: Iterable<A>) => Generator<B>
) & (
  <A, B>(fn: Mapper<A, B>) => (iterator: Iterable<A>) => Generator<B>
);
export type Mapper<A, B> = (item: A) => B;

export const asyncMap: (
  <A, B>(fn: AsyncMapper<A, B>, iterator: Iterable<A> | AsyncIterable<A>) => AsyncGenerator<B>
) & (
  <A, B>(fn: AsyncMapper<A, B>) => (iterator: Iterable<A> | AsyncIterable<A>) => AsyncGenerator<B>
);
export type AsyncMapper<A, B> = (item: A) => Promise<B> | B;

export const tap: (
  <A>(fn: Tapper<A>, iterator: Iterable<A>) => Generator<A>
) & (
  <A>(fn: Tapper<A>) => (iterator: Iterable<A>) => Generator<A>
);
export type Tapper<A> = (item: A) => void | Promise<void>;

export const asyncTap: (
  <A>(fn: Tapper<A>, iterator: AsyncIterable<A>) => AsyncGenerator<A>
) & (
  <A>(fn: Tapper<A>) => (iterator: AsyncIterable<A>) => AsyncGenerator<A>
);

export const filter: (
  <A>(fn: Predicate<A>, iterator: Iterable<A>) => Generator<A>
) & (
  <A>(fn: Predicate<A>) => (iterator: Iterable<A>) => Generator<A>
);
export type Predicate<A> = (item: A) => boolean;

export const asyncFilter: (
  <A>(fn: AsyncPredicate<A>, iterator: Iterable<A> | AsyncIterable<A>) => AsyncGenerator<A>
) & (
  <A>(fn: AsyncPredicate<A>) => (iterator: Iterable<A> | AsyncIterable<A>) => AsyncGenerator<A>
);
export type AsyncPredicate<A> = (item: A) => Promise<boolean> | boolean;

export const scan: (
  <A, B>(fn: Reducer<A, B>, acc: B, iter: Iterable<A>) => Generator<B>
) & (
  <A, B>(fn: Reducer<A, B>, acc: B) => (iter: Iterable<A>) => Generator<B>
);

export const asyncScan: (
  <A, B>(fn: AsyncReducer<A, B>, acc: B, iter: Iterable<A> | AsyncIterable<A>) => AsyncGenerator<B>
) & (
  <A, B>(fn: AsyncReducer<A, B>, acc: B) => (iter: Iterable<A> | AsyncIterable<A>) => AsyncGenerator<B>
);

export const flatten: <A>(iterator: NestedIterable<A>, depth?: number) => Generator<A | NestedIterable<A>>;
export type NestedIterable<A> = Iterable<A | NestedIterable<A>>;

export const asyncFlatten: <A>(iterator: NestedAsyncIterable<A>, depth?: number) => AsyncGenerator<A | NestedIterable<A> | NestedAsyncIterable<A>>;
export type NestedAsyncIterable<A> = AsyncIterable<A | NestedAsyncIterable<A> | NestedIterable<A>>;

export const drop: (
  <A>(count: number, iterator: Iterable<A>) => Generator<A>
) & (
  <A>(count: number) => (iterator: Iterable<A>) => Generator<A>
);

export const asyncDrop: (
  <A>(count: number, iterator: AsyncIterable<A>) => AsyncGenerator<A>
) & (
  <A>(count: number) => (iterator: AsyncIterable<A>) => AsyncGenerator<A>
);

export const dropWhile: (
  <A>(fn: Predicate<A>, iterator: Iterable<A>) => Generator<A>
) & (
  <A>(fn: Predicate<A>) => (iterator: Iterable<A>) => Generator<A>
);

export const asyncDropWhile: (
  <A>(fn: AsyncPredicate<A>, iterator: AsyncIterable<A>) => AsyncGenerator<A>
) & (
  <A>(fn: AsyncPredicate<A>) => (iterator: AsyncIterable<A>) => AsyncGenerator<A>
);

export const take: (
  <A>(count: number, iterator: Iterable<A>) => Generator<A>
) & (
  <A>(count: number) => (iterator: Iterable<A>) => Generator<A>
);

export const asyncTake: (
  <A>(count: number, iterator: AsyncIterable<A>) => AsyncGenerator<A>
) & (
  <A>(count: number) => (iterator: AsyncIterable<A>) => AsyncGenerator<A>
);

export const takeWhile: (
  <A>(fn: Predicate<A>, iterator: Iterable<A>) => Generator<A>
) & (
  <A>(fn: Predicate<A>) => (iterator: Iterable<A>) => Generator<A>
);

export const asyncTakeWhile: (
  <A>(fn: AsyncPredicate<A>, iterator: AsyncIterable<A>) => AsyncGenerator<A>
) & (
  <A>(fn: AsyncPredicate<A>) => (iterator: AsyncIterable<A>) => AsyncGenerator<A>
);

export const head: <A>(iterator: Iterable<A>) => A | undefined;
export const asyncHead: <A>(iterator: AsyncIterable<A>) => Promise<A | undefined>;

export const range: (from: number, to?: number) => Generator<number>;

export const empty: <A>() => Generator<A>;
export const asyncEmpty: <A>() => AsyncGenerator<A>;

export const zip: <A, B>(iter1: Iterable<A>, iter2: Iterable<B>) => Generator<[A, B]>;
export const asyncZip: <A, B>(iter1: AsyncIterable<A>, iter2: AsyncIterable<B>) => AsyncGenerator<[A, B]>;

export const concat: <A>(...iters: Iterable<A>[]) => Generator<A>;
export const asyncConcat: <A>(...iters: (Iterable<A> | AsyncIterable<A>)[]) => AsyncGenerator<A>;

export const reduce: (
  <A, B>(fn: Reducer<A, B>, acc: B, iter: Iterable<A>) => B
) & (
  <A, B>(fn: Reducer<A, B>, acc: B) => (iter: Iterable<A>) => B
);
export type Reducer<A, B> = (acc: B, item: A) => B;

export const asyncReduce: (
  <A, B>(fn: AsyncReducer<A, B>, acc: B, iter: Iterable<A> | AsyncIterable<A>) => Promise<B>
) & (
  <A, B>(fn: AsyncReducer<A, B>, acc: B) => (iter: Iterable<A> | AsyncIterable<A>) => Promise<B>
);
export type AsyncReducer<A, B> = (acc: B, item: A) => Promise<B> | B;

export const every: (
  <A>(fn: Predicate<A>, iterator: Iterable<A>) => boolean
) & (
  <A>(fn: Predicate<A>) => (iterator: Iterable<A>) => boolean
);

export const asyncEvery: (
  <A>(fn: AsyncPredicate<A>, iterator: Iterable<A> | AsyncIterable<A>) => Promise<boolean>
) & (
  <A>(fn: AsyncPredicate<A>) => (iterator: Iterable<A> | AsyncIterable<A>) => Promise<boolean>
);

export const some: (
  <A>(fn: Predicate<A>, iterator: Iterable<A>) => boolean
) & (
  <A>(fn: Predicate<A>) => (iterator: Iterable<A>) => boolean
);

export const asyncSome: (
  <A>(fn: AsyncPredicate<A>, iterator: Iterable<A> | AsyncIterable<A>) => Promise<boolean>
) & (
  <A>(fn: AsyncPredicate<A>) => (iterator: Iterable<A> | AsyncIterable<A>) => Promise<boolean>
);

export const find: (
  <A>(fn: Predicate<A>, iterator: Iterable<A>) => A
) & (
  <A>(fn: Predicate<A>) => (iterator: Iterable<A>) => A
);

export const asyncFind: (
  <A>(fn: AsyncPredicate<A>, iterator: Iterable<A> | AsyncIterable<A>) => Promise<A>
) & (
  <A>(fn: AsyncPredicate<A>) => (iterator: Iterable<A> | AsyncIterable<A>) => Promise<A>
);

export const count: <A>(iterator: Iterable<A>) => number;
export const asyncCount: <A>(iterator: AsyncIterable<A>) => Promise<number>;

export const collectArray: <A>(iterator: Iterable<A>) => A[];
export const asyncCollectArray: <A>(iterator: AsyncIterable<A>) => Promise<A[]>;

export const collectSet: <A>(iterator: Iterable<A>) => Set<A>;
export const asyncCollectSet: <A>(iterator: AsyncIterable<A>) => Promise<Set<A>>;

export const collectMap: <A, B>(iterator: Iterable<[A, B]>) => Map<A, B>;
export const asyncCollectMap: <A, B>(iterator: AsyncIterable<[A, B]>) => Promise<Map<A, B>>;

export const collectObject: <A>(iterator: Iterable<[string, A]>) => Record<string, A>;
export const asyncCollectObject: <A>(iterator: AsyncIterable<[string, A]>) => Promise<Record<string, A>>;

export const join: (
  (separator: string, iterator: Iterable<string>) => string
) & (
  (separator: string) => (iterator: Iterable<string>) => string
);

export const asyncJoin: (
  (separator: string, iterator: AsyncIterable<string>) => Promise<string>
) & (
  (separator: string) => (iterator: AsyncIterable<string>) => Promise<string>
);

// eslint-disable-next-line @typescript-eslint/ban-types, @typescript-eslint/no-explicit-any
export const pipe: <A>(iterator: Iterable<any> | AsyncIterable<any>, ...fns: Function[]) => A;
