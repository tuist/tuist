declare function clone<T>(x: T): T;

declare function globalRef<T>(key: string, value: () => T): T;

type AsRef = {
    $$valtioRef: true;
};
type Path = (string | symbol)[];
type Op = [op: "set", path: Path, value: unknown, prevValue: unknown] | [op: "delete", path: Path, prevValue: unknown];
type Snapshot<T> = T;
declare function proxy<T extends object>(initialObject?: T): T;
declare function subscribe<T extends object>(proxyObject: T, callback: (ops: Op[]) => void, notifyInSync?: boolean): () => void;
declare function snapshot<T extends object>(proxyObject: T): T;
declare function ref<T extends object>(obj: T): Ref<T>;
type Ref<T> = T & AsRef;

declare function proxyWithComputed<T extends object, U extends object>(initialObject: T, computedFns: {
    [K in keyof U]: ((snap: Snapshot<T>) => U[K]) | {
        get: (snap: Snapshot<T>) => U[K];
        set?: (state: T, newValue: U[K]) => void;
    };
}): T & U;

export { type Ref, type Snapshot, clone, globalRef, proxy, proxyWithComputed, ref, snapshot, subscribe };
