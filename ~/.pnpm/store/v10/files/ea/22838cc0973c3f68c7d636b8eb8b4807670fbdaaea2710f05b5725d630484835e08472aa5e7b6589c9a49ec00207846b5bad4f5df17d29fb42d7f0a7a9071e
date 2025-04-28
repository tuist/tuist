type Arrayable<T> = T | T[];
interface PackArrayOptions<T extends Record<string, any>[]> extends PackOptions<T[number]> {
    key?: Arrayable<keyof T[number] | string>;
    value?: Arrayable<keyof T[number] | string>;
}
interface PackOptions<T extends Record<keyof T, any>> {
    key?: Arrayable<keyof T | string>;
    value?: Arrayable<keyof T | string>;
    resolveKey?: (key: keyof T) => string;
}

declare function packArray<T extends Record<string, any>[]>(input: T, options?: PackArrayOptions<T>): Partial<Record<string, any>>;

declare const InternalKeySymbol = "_$key";
declare function packObject<T extends Record<string, any>>(input: T, options?: PackOptions<T>): Partial<T>;

declare function packString<T extends string>(input: T): Record<string, any>;

interface Context {
    key: string;
    value: any;
}
type ResolveFn = (ctx: Context) => string;
interface UnpackArrayOptions {
    key: string | ResolveFn;
    value: string | ResolveFn;
    resolveKeyData?: ResolveFn;
    resolveValueData?: ResolveFn;
}
declare function unpackToArray(input: Record<string, any>, options: UnpackArrayOptions): Record<string, any>[];

interface TransformValueOptions {
    entrySeparator?: string;
    keyValueSeparator?: string;
    wrapValue?: string;
    resolve?: (ctx: {
        key: string;
        value: unknown;
    }) => string | void;
}
declare function unpackToString<T extends Record<keyof T, unknown>>(value: T, options: TransformValueOptions): string;

export { InternalKeySymbol, type TransformValueOptions, type UnpackArrayOptions, packArray, packObject, packString, unpackToArray, unpackToString };
