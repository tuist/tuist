type TAllKeys<T> = T extends any ? keyof T : never;
type TIndexValue<T, K extends PropertyKey, D = never> = T extends any ? K extends keyof T ? T[K] : D : never;
type TPartialKeys<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>> extends infer O ? {
    [P in keyof O]: O[P];
} : never;
type TFunction = (...a: any[]) => any;
type TPrimitives = string | number | boolean | bigint | symbol | Date | TFunction;
type TMerged<T> = [T] extends [Array<any>] ? {
    [K in keyof T]: TMerged<T[K]>;
} : [T] extends [TPrimitives] ? T : [T] extends [object] ? TPartialKeys<{
    [K in TAllKeys<T>]: TMerged<TIndexValue<T, K>>;
}, never> : T;
interface IObject {
    [key: string]: any;
}
export declare const merge: {
    <T extends IObject[]>(...objects: T): TMerged<T[number]>;
    options: IOptions;
    withOptions<T extends IObject[]>(options: Partial<IOptions>, ...objects: T): TMerged<T[number]>;
};
interface IOptions {
    /**
     * When `true`, values explicitly provided as `undefined` will override existing values, though properties that are simply omitted won't affect anything.
     * When `false`, values explicitly provided as `undefined` won't override existing values.
     *
     * Default: `true`
     */
    allowUndefinedOverrides: boolean;
    /**
     * When `true` it will merge array properties.
     * When `false` it will replace array properties with the last instance entirely instead of merging their contents.
     *
     * Default: `true`
     */
    mergeArrays: boolean;
    /**
     * When `true` it will ensure there are no duplicate array items.
     * When `false` it will allow duplicates when merging arrays.
     *
     * Default: `true`
     */
    uniqueArrayItems: boolean;
}
export {};
