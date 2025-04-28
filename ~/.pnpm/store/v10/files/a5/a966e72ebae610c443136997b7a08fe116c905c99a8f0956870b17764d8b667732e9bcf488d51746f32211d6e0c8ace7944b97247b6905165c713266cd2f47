import { type PropType, type Ref } from 'vue';
type Containers = (() => Iterable<HTMLElement>) | Ref<Set<Ref<HTMLElement | null>>>;
declare enum Features {
    /** No features enabled for the focus trap. */
    None = 1,
    /** Ensure that we move focus initially into the container. */
    InitialFocus = 2,
    /** Ensure that pressing `Tab` and `Shift+Tab` is trapped within the container. */
    TabLock = 4,
    /** Ensure that programmatically moving focus outside of the container is disallowed. */
    FocusLock = 8,
    /** Ensure that we restore the focus when unmounting the focus trap. */
    RestoreFocus = 16,
    /** Enable all features. */
    All = 30
}
export declare let FocusTrap: {
    new (...args: any[]): {
        $: import("vue").ComponentInternalInstance;
        $data: {};
        $props: Partial<{
            features: Features;
            as: string | Record<string, any>;
            initialFocus: HTMLElement | null;
            containers: Containers;
        }> & Omit<Readonly<import("vue").ExtractPropTypes<{
            as: {
                type: (ObjectConstructor | StringConstructor)[];
                default: string;
            };
            initialFocus: {
                type: PropType<HTMLElement | null>;
                default: null;
            };
            features: {
                type: PropType<Features>;
                default: Features;
            };
            containers: {
                type: PropType<Containers>;
                default: Ref<Set<unknown>>;
            };
        }>> & import("vue").VNodeProps & import("vue").AllowedComponentProps & import("vue").ComponentCustomProps, "features" | "as" | "initialFocus" | "containers">;
        $attrs: {
            [x: string]: unknown;
        };
        $refs: {
            [x: string]: unknown;
        };
        $slots: Readonly<{
            [name: string]: import("vue").Slot | undefined;
        }>;
        $root: import("vue").ComponentPublicInstance<{}, {}, {}, {}, {}, {}, {}, {}, false, import("vue").ComponentOptionsBase<any, any, any, any, any, any, any, any, any, {}>> | null;
        $parent: import("vue").ComponentPublicInstance<{}, {}, {}, {}, {}, {}, {}, {}, false, import("vue").ComponentOptionsBase<any, any, any, any, any, any, any, any, any, {}>> | null;
        $emit: (event: string, ...args: any[]) => void;
        $el: any;
        $options: import("vue").ComponentOptionsBase<Readonly<import("vue").ExtractPropTypes<{
            as: {
                type: (ObjectConstructor | StringConstructor)[];
                default: string;
            };
            initialFocus: {
                type: PropType<HTMLElement | null>;
                default: null;
            };
            features: {
                type: PropType<Features>;
                default: Features;
            };
            containers: {
                type: PropType<Containers>;
                default: Ref<Set<unknown>>;
            };
        }>>, () => import("vue").VNode<import("vue").RendererNode, import("vue").RendererElement, {
            [key: string]: any;
        }>, unknown, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, Record<string, any>, string, {
            features: Features;
            as: string | Record<string, any>;
            initialFocus: HTMLElement | null;
            containers: Containers;
        }> & {
            beforeCreate?: ((() => void) | (() => void)[]) | undefined;
            created?: ((() => void) | (() => void)[]) | undefined;
            beforeMount?: ((() => void) | (() => void)[]) | undefined;
            mounted?: ((() => void) | (() => void)[]) | undefined;
            beforeUpdate?: ((() => void) | (() => void)[]) | undefined;
            updated?: ((() => void) | (() => void)[]) | undefined;
            activated?: ((() => void) | (() => void)[]) | undefined;
            deactivated?: ((() => void) | (() => void)[]) | undefined;
            beforeDestroy?: ((() => void) | (() => void)[]) | undefined;
            beforeUnmount?: ((() => void) | (() => void)[]) | undefined;
            destroyed?: ((() => void) | (() => void)[]) | undefined;
            unmounted?: ((() => void) | (() => void)[]) | undefined;
            renderTracked?: (((e: import("vue").DebuggerEvent) => void) | ((e: import("vue").DebuggerEvent) => void)[]) | undefined;
            renderTriggered?: (((e: import("vue").DebuggerEvent) => void) | ((e: import("vue").DebuggerEvent) => void)[]) | undefined;
            errorCaptured?: (((err: unknown, instance: import("vue").ComponentPublicInstance<{}, {}, {}, {}, {}, {}, {}, {}, false, import("vue").ComponentOptionsBase<any, any, any, any, any, any, any, any, any, {}>> | null, info: string) => boolean | void) | ((err: unknown, instance: import("vue").ComponentPublicInstance<{}, {}, {}, {}, {}, {}, {}, {}, false, import("vue").ComponentOptionsBase<any, any, any, any, any, any, any, any, any, {}>> | null, info: string) => boolean | void)[]) | undefined;
        };
        $forceUpdate: () => void;
        $nextTick: typeof import("vue").nextTick;
        $watch(source: string | Function, cb: Function, options?: import("vue").WatchOptions<boolean> | undefined): import("vue").WatchStopHandle;
    } & Readonly<import("vue").ExtractPropTypes<{
        as: {
            type: (ObjectConstructor | StringConstructor)[];
            default: string;
        };
        initialFocus: {
            type: PropType<HTMLElement | null>;
            default: null;
        };
        features: {
            type: PropType<Features>;
            default: Features;
        };
        containers: {
            type: PropType<Containers>;
            default: Ref<Set<unknown>>;
        };
    }>> & import("vue").ShallowUnwrapRef<() => import("vue").VNode<import("vue").RendererNode, import("vue").RendererElement, {
        [key: string]: any;
    }>> & {} & {} & import("vue").ComponentCustomProperties;
    __isFragment?: undefined;
    __isTeleport?: undefined;
    __isSuspense?: undefined;
} & import("vue").ComponentOptionsBase<Readonly<import("vue").ExtractPropTypes<{
    as: {
        type: (ObjectConstructor | StringConstructor)[];
        default: string;
    };
    initialFocus: {
        type: PropType<HTMLElement | null>;
        default: null;
    };
    features: {
        type: PropType<Features>;
        default: Features;
    };
    containers: {
        type: PropType<Containers>;
        default: Ref<Set<unknown>>;
    };
}>>, () => import("vue").VNode<import("vue").RendererNode, import("vue").RendererElement, {
    [key: string]: any;
}>, unknown, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, Record<string, any>, string, {
    features: Features;
    as: string | Record<string, any>;
    initialFocus: HTMLElement | null;
    containers: Containers;
}> & import("vue").VNodeProps & import("vue").AllowedComponentProps & import("vue").ComponentCustomProps & {
    features: typeof Features;
};
export {};
