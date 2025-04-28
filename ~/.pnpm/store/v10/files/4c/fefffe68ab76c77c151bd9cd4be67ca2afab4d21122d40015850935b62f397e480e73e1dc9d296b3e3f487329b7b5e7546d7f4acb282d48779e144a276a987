declare function toArray<T>(v: T | T[] | undefined | null): T[];
declare const fromLength: (length: number) => number[];
declare const first: <T>(v: T[]) => T | undefined;
declare const last: <T>(v: T[]) => T | undefined;
declare const isEmpty: <T>(v: T[]) => boolean;
declare const has: <T>(v: T[], t: any) => boolean;
declare const add: <T>(v: T[], ...items: T[]) => T[];
declare const remove: <T>(v: T[], ...items: T[]) => T[];
declare const removeAt: <T>(v: T[], i: number) => T[];
declare const insertAt: <T>(v: T[], i: number, ...items: T[]) => T[];
declare const uniq: <T>(v: T[]) => T[];
declare const addOrRemove: <T>(v: T[], item: T) => T[];
declare function clear<T>(v: T[]): T[];
type IndexOptions = {
    step?: number;
    loop?: boolean;
};
declare function nextIndex<T>(v: T[], idx: number, opts?: IndexOptions): number;
declare function next<T>(v: T[], idx: number, opts?: IndexOptions): T | undefined;
declare function prevIndex<T>(v: T[], idx: number, opts?: IndexOptions): number;
declare function prev<T>(v: T[], index: number, opts?: IndexOptions): T | undefined;
declare const chunk: <T>(v: T[], size: number) => T[][];
declare function flatArray<T>(arr: T[]): T[];

declare const isEqual: (a: any, b: any) => boolean;

type MaybeFunction<T> = T | (() => T);
type Nullable<T> = T | null | undefined;
declare const runIfFn: <T>(v: T | undefined, ...a: T extends (...a: any[]) => void ? Parameters<T> : never) => T extends (...a: any[]) => void ? NonNullable<ReturnType<T>> : NonNullable<T>;
declare const cast: <T>(v: unknown) => T;
declare const identity: (v: VoidFunction) => void;
declare const noop: () => void;
declare const callAll: <T extends (...a: any[]) => void>(...fns: (T | null | undefined)[]) => (...a: Parameters<T>) => void;
declare const uuid: () => string;
declare function match<V extends string | number = string, R = unknown>(key: V, record: Record<V, R | ((...args: any[]) => R)>, ...args: any[]): R;
declare const tryCatch: <R>(fn: () => R, fallback: () => R) => R;
declare function throttle<T extends (...args: any[]) => void>(fn: T, wait?: number): T;

type AnyFunction = (...args: any[]) => any;
declare const isDev: () => boolean;
declare const isArray: (v: any) => v is any[];
declare const isBoolean: (v: any) => v is boolean;
declare const isObjectLike: (v: any) => v is Record<string, any>;
declare const isObject: (v: any) => v is Record<string, any>;
declare const isNumber: (v: any) => v is number;
declare const isString: (v: any) => v is string;
declare const isFunction: (v: any) => v is AnyFunction;
declare const isNull: (v: any) => v is null | undefined;
declare const hasProp: <T extends string>(obj: any, prop: T) => obj is Record<T, any>;
declare const isPlainObject: (v: any) => boolean;

declare const isNaN: (v: number) => boolean;
declare const nan: (v: number) => number;
declare const mod: (v: number, m: number) => number;
declare const wrap: (v: number, vmax: number) => number;
declare const getMinValueAtIndex: (i: number, v: number[], vmin: number) => number;
declare const getMaxValueAtIndex: (i: number, v: number[], vmax: number) => number;
declare const isValueAtMax: (v: number, vmax: number) => boolean;
declare const isValueAtMin: (v: number, vmin: number) => boolean;
declare const isValueWithinRange: (v: number, vmin: number, vmax: number) => boolean;
declare const roundValue: (v: number, vmin: number, step: number) => number;
declare const clampValue: (v: number, vmin: number, vmax: number) => number;
declare const clampPercent: (v: number) => number;
declare const getValuePercent: (v: number, vmin: number, vmax: number) => number;
declare const getPercentValue: (p: number, vmin: number, vmax: number, step: number) => number;
declare const roundToStepPrecision: (v: number, step: number) => number;
declare const roundToDpr: (v: number, dpr: unknown) => number;
declare const snapValueToStep: (v: number, vmin: number | undefined, vmax: number | undefined, step: number) => number;
declare const setValueAtIndex: <T>(vs: T[], i: number, v: T) => T[];
interface RangeContext {
    min: number;
    max: number;
    step: number;
    values: number[];
}
declare function getValueSetterAtIndex(index: number, ctx: RangeContext): (value: number) => number[];
declare function getNextStepValue(index: number, ctx: RangeContext): number[];
declare function getPreviousStepValue(index: number, ctx: RangeContext): number[];
declare const getClosestValueIndex: (vs: number[], t: number) => number;
declare const getClosestValue: (vs: number[], t: number) => number;
declare const getValueRanges: (vs: number[], vmin: number, vmax: number, gap: number) => {
    min: number;
    max: number;
    value: number;
}[];
declare const getValueTransformer: (va: number[], vb: number[]) => (v: number) => number;
declare const toFixedNumber: (v: number, d?: number, b?: number) => number;
declare const incrementValue: (v: number, s: number) => number;
declare const decrementValue: (v: number, s: number) => number;
declare const toPx: (v: number | undefined) => string | undefined;

declare function compact<T extends Record<string, unknown> | undefined>(obj: T): T;
declare const json: (v: any) => any;
declare function pick<T extends Record<string, any>, K extends keyof T>(obj: T, keys: K[]): Pick<T, K>;
type Dict = Record<string, any>;
declare function splitProps<T extends Dict>(props: T, keys: (keyof T)[]): Dict[];
declare const createSplitProps: <T extends Dict>(keys: (keyof T)[]) => <Props extends T>(props: Props) => [T, Omit<Props, keyof T>];
declare function omit<T extends Record<string, any>>(obj: T, keys: string[]): Omit<T, string | number>;

interface RafIntervalOptions {
    startMs: number;
    deltaMs: number;
}
declare function setRafInterval(callback: (options: RafIntervalOptions) => void, interval: number): () => void;
declare function setRafTimeout(callback: () => void, delay: number): () => void;

declare function warn(m: string): void;
declare function warn(c: boolean, m: string): void;
declare function invariant(m: string): void;
declare function invariant(c: boolean, m: string): void;
declare function ensure<T>(c: T | null | undefined, m: () => string): asserts c is T;
type RequiredBy<T, K extends keyof T> = Omit<T, K> & Required<Pick<T, K>>;
declare function ensureProps<T, K extends keyof T>(props: T, keys: K[], scope?: string): asserts props is T & RequiredBy<T, K>;

export { type IndexOptions, type MaybeFunction, type Nullable, type RafIntervalOptions, add, addOrRemove, callAll, cast, chunk, clampPercent, clampValue, clear, compact, createSplitProps, decrementValue, ensure, ensureProps, first, flatArray, fromLength, getClosestValue, getClosestValueIndex, getMaxValueAtIndex, getMinValueAtIndex, getNextStepValue, getPercentValue, getPreviousStepValue, getValuePercent, getValueRanges, getValueSetterAtIndex, getValueTransformer, has, hasProp, identity, incrementValue, insertAt, invariant, isArray, isBoolean, isDev, isEmpty, isEqual, isFunction, isNaN, isNull, isNumber, isObject, isObjectLike, isPlainObject, isString, isValueAtMax, isValueAtMin, isValueWithinRange, json, last, match, mod, nan, next, nextIndex, noop, omit, pick, prev, prevIndex, remove, removeAt, roundToDpr, roundToStepPrecision, roundValue, runIfFn, setRafInterval, setRafTimeout, setValueAtIndex, snapValueToStep, splitProps, throttle, toArray, toFixedNumber, toPx, tryCatch, uniq, uuid, warn, wrap };
