interface Props {
    [key: string]: any;
}
type TupleTypes<T extends any[]> = T[number];
type UnionToIntersection<U> = (U extends any ? (k: U) => void : never) extends (k: infer I) => void ? I : never;
declare function mergeProps<T extends Props>(...args: T[]): UnionToIntersection<TupleTypes<T[]>>;

type NoInfer<T> = [T][T extends any ? 0 : never];
declare function memo<TDeps extends any[], TDepArgs, TResult>(getDeps: (depArgs: TDepArgs) => [...TDeps], fn: (...args: NoInfer<[...TDeps]>) => TResult, opts?: {
    onChange?: (result: TResult) => void;
}): (depArgs: TDepArgs) => TResult;

type Dict = Record<string, any>;
interface ComputedParams<T extends Dict> {
    context: BindableContext<T>;
    event: EventType<T["event"]>;
    prop: PropFn<T>;
    refs: BindableRefs<T>;
    scope: Scope;
    computed: ComputedFn<T>;
}
interface ContextParams<T extends Dict> {
    prop: PropFn<T>;
    bindable: BindableFn;
    scope: Scope;
    getContext: () => BindableContext<T>;
    getComputed: () => ComputedFn<T>;
    getRefs: () => BindableRefs<T>;
    flush: (fn: VoidFunction) => void;
}
interface PropFn<T extends Dict> {
    <K extends keyof T["props"]>(key: K): T["props"][K];
}
interface ComputedFn<T extends Dict> {
    <K extends keyof T["computed"]>(key: K): T["computed"][K];
}
type AnyFunction = () => string | number | boolean | null | undefined;
type TrackFn = (deps: AnyFunction[], fn: VoidFunction) => void;
interface BindableParams<T> {
    defaultValue?: T | undefined;
    value?: T | undefined;
    hash?: (a: T) => string;
    isEqual?: (a: T, b: T | undefined) => boolean;
    onChange?: (value: T, prev: T | undefined) => void;
    debug?: string;
    sync?: boolean;
}
type ValueOrFn<T> = T | ((prev: T) => T);
interface Bindable<T> {
    initial: T | undefined;
    ref: any;
    get: () => T;
    set(value: ValueOrFn<T>): void;
    invoke(nextValue: T, prevValue: T): void;
    hash(value: T): string;
}
interface BindableRefs<T extends Dict> {
    set<K extends keyof T["refs"]>(key: K, value: T["refs"][K]): void;
    get<K extends keyof T["refs"]>(key: K): T["refs"][K];
}
interface BindableContext<T extends Dict> {
    set<K extends keyof T["context"]>(key: K, value: ValueOrFn<T["context"][K]>): void;
    get<K extends keyof T["context"]>(key: K): T["context"][K];
    initial<K extends keyof T["context"]>(key: K): T["context"][K];
    hash<K extends keyof T["context"]>(key: K): string;
}
interface BindableRef<T> {
    get: () => T;
    set: (next: T) => void;
}
interface BindableFn {
    <K>(params: () => BindableParams<K>): Bindable<K>;
    cleanup: (fn: VoidFunction) => void;
    ref: <T>(defaultValue: T) => BindableRef<T>;
}
interface Scope {
    id?: string | undefined;
    ids?: Record<string, any> | undefined;
    getRootNode: () => ShadowRoot | Document | Node;
    getById: <T extends Element = HTMLElement>(id: string) => T | null;
    getActiveElement: () => HTMLElement | null;
    isActiveElement: (elem: HTMLElement | null) => boolean;
    getDoc: () => typeof document;
    getWin: () => typeof window;
}
type EventType<T = any> = T & {
    previousEvent?: T & {
        [key: string]: any;
    };
    src?: string;
    [key: string]: any;
};
type EventObject = EventType<{
    type: string;
}>;
interface Params<T extends Dict> {
    prop: PropFn<T>;
    action: (action: T["action"][]) => void;
    context: BindableContext<T>;
    refs: BindableRefs<T>;
    track: TrackFn;
    flush: (fn: VoidFunction) => void;
    event: EventType<T["event"]> & {
        current: () => EventType<T["event"]>;
        previous: () => EventType<T["event"]>;
    };
    send: (event: EventType<T["event"]>) => void;
    computed: ComputedFn<T>;
    scope: Scope;
    state: Bindable<T["state"]> & {
        matches: (...values: T["state"][]) => boolean;
        hasTag: (tag: T["tag"]) => boolean;
    };
    choose: ChooseFn<T>;
    guard: (key: T["guard"] | GuardFn<T>) => boolean | undefined;
}
type GuardFn<T extends Dict> = (params: Params<T>) => boolean;
interface Transition<T extends Dict> {
    target?: T["state"];
    actions?: T["action"][];
    guard?: T["guard"] | GuardFn<T>;
    reenter?: boolean;
}
type MaybeArray<T> = T | T[];
type ChooseFn<T extends Dict> = (transitions: MaybeArray<Omit<Transition<T>, "target">>) => Transition<T> | undefined;
interface PropsParams<T extends Dict> {
    props: Partial<T["props"]>;
    scope: Scope;
}
interface RefsParams<T extends Dict> {
    prop: PropFn<T>;
    context: BindableContext<T>;
}
type ActionsOrFn<T extends Dict> = T["action"][] | ((params: Params<T>) => T["action"][] | undefined);
type EffectsOrFn<T extends Dict> = T["effect"][] | ((params: Params<T>) => T["effect"][] | undefined);
interface Machine<T extends Dict> {
    debug?: boolean;
    props?: (params: PropsParams<T>) => T["props"];
    context?: (params: ContextParams<T>) => {
        [K in keyof T["context"]]: Bindable<T["context"][K]>;
    };
    computed?: {
        [K in keyof T["computed"]]: (params: ComputedParams<T>) => T["computed"][K];
    };
    initialState: (params: {
        prop: PropFn<T>;
    }) => T["state"];
    entry?: ActionsOrFn<T>;
    exit?: ActionsOrFn<T>;
    effects?: EffectsOrFn<T>;
    refs?: (params: RefsParams<T>) => T["refs"];
    watch?: (params: Params<T>) => void;
    on?: {
        [E in T["event"]["type"]]?: Transition<T> | Array<Transition<T>>;
    };
    states: {
        [K in T["state"]]: {
            tags?: T["tag"][];
            entry?: ActionsOrFn<T>;
            exit?: ActionsOrFn<T>;
            effects?: EffectsOrFn<T>;
            on?: {
                [E in T["event"]["type"]]?: Transition<T> | Array<Transition<T>>;
            };
        };
    };
    implementations?: {
        guards?: {
            [K in T["guard"]]: (params: Params<T>) => boolean;
        };
        actions?: {
            [K in T["action"]]: (params: Params<T>) => void;
        };
        effects?: {
            [K in T["effect"]]: (params: Params<T>) => void | VoidFunction;
        };
    };
}
interface MachineBaseProps {
    id?: string | undefined;
    ids?: Record<string, any> | undefined;
    getRootNode?: (() => ShadowRoot | Document | Node) | undefined;
    [key: string]: any;
}
interface MachineSchema {
    props?: MachineBaseProps;
    context?: Record<string, any>;
    refs?: Record<string, any>;
    computed?: Record<string, any>;
    state?: string;
    tag?: string;
    guard?: string;
    action?: string;
    effect?: string;
    event?: {
        type: string;
    } & Dict;
}
type State<T extends MachineSchema> = Bindable<T["state"]> & {
    hasTag: (tag: T["tag"]) => boolean;
    matches: (...values: T["state"][]) => boolean;
};
type Service<T extends MachineSchema> = {
    getStatus: () => MachineStatus;
    state: State<T> & {
        matches: (...values: T["state"][]) => boolean;
        hasTag: (tag: T["tag"]) => boolean;
    };
    context: BindableContext<T>;
    send: (event: EventType<T["event"]>) => void;
    prop: PropFn<T>;
    scope: Scope;
    computed: ComputedFn<T>;
    refs: BindableRefs<T>;
    event: EventType<T["event"]> & {
        current: () => EventType<T["event"]>;
        previous: () => EventType<T["event"]>;
    };
};
declare enum MachineStatus {
    NotStarted = "Not Started",
    Started = "Started",
    Stopped = "Stopped"
}
declare const INIT_STATE = "__init__";

declare function createGuards<T extends MachineSchema>(): {
    and: (...guards: Array<GuardFn<T> | T["guard"]>) => (params: any) => boolean;
    or: (...guards: Array<GuardFn<T> | T["guard"]>) => (params: any) => boolean;
    not: (guard: GuardFn<T> | T["guard"]) => (params: any) => boolean;
};
declare function createMachine<T extends MachineSchema>(config: Machine<T>): Machine<T>;
declare function setup<T extends MachineSchema>(): {
    guards: {
        and: (...guards: (T["guard"] | GuardFn<T>)[]) => (params: any) => boolean;
        or: (...guards: (T["guard"] | GuardFn<T>)[]) => (params: any) => boolean;
        not: (guard: T["guard"] | GuardFn<T>) => (params: any) => boolean;
    };
    createMachine: (config: Machine<T>) => Machine<T>;
    choose: (transitions: Transition<T> | Transition<T>[]) => ({ choose }: Params<T>) => T["action"][] | undefined;
};

declare function createScope(props: Pick<Scope, "id" | "ids" | "getRootNode">): {
    getRootNode: () => Document | ShadowRoot;
    getDoc: () => Document;
    getWin: () => Window & typeof globalThis;
    getActiveElement: () => HTMLElement | null;
    isActiveElement: (elem: HTMLElement | null) => boolean;
    getById: <T extends Element = HTMLElement>(id: string) => T | null;
    id?: string | undefined | undefined;
    ids?: Record<string, any> | undefined;
};

export { type ActionsOrFn, type Bindable, type BindableContext, type BindableFn, type BindableParams, type BindableRefs, type ChooseFn, type ComputedFn, type EffectsOrFn, type EventObject, type GuardFn, INIT_STATE, type Machine, type MachineSchema, MachineStatus, type Params, type PropFn, type Scope, type Service, type Transition, type ValueOrFn, createGuards, createMachine, createScope, memo, mergeProps, setup };
