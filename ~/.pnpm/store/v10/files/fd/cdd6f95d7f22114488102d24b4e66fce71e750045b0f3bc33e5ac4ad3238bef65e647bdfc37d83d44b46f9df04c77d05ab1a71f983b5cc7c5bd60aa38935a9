import { PrimitiveProps } from '../Primitive';
import { EventHook } from '@vueuse/core';
import { Ref } from 'vue';
import { useSelectionBehavior } from '../shared';
import { Direction } from '../shared/types';
export interface TreeRootProps<T = Record<string, any>, U extends Record<string, any> = Record<string, any>> extends PrimitiveProps {
    /** The controlled value of the tree. Can be binded with with `v-model`. */
    modelValue?: U | U[];
    /** The value of the tree when initially rendered. Use when you do not need to control the state of the tree */
    defaultValue?: U | U[];
    /** List of items */
    items?: T[];
    /** The controlled value of the expanded item. Can be binded with with `v-model`. */
    expanded?: string[];
    /** The value of the expanded tree when initially rendered. Use when you do not need to control the state of the expanded tree */
    defaultExpanded?: string[];
    /** This function is passed the index of each item and should return a unique key for that item */
    getKey: (val: T) => string;
    /** This function is passed the index of each item and should return a list of children for that item */
    getChildren?: (val: T) => T[] | undefined;
    /** How multiple selection should behave in the collection. */
    selectionBehavior?: 'toggle' | 'replace';
    /** Whether multiple options can be selected or not.  */
    multiple?: boolean;
    /** The reading direction of the listbox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** When `true`, prevents the user from interacting with tree  */
    disabled?: boolean;
    /** When `true`, selecting parent will select the descendants. */
    propagateSelect?: boolean;
}
export type TreeRootEmits<T = Record<string, any>> = {
    'update:modelValue': [val: T];
    'update:expanded': [val: string[]];
};
interface TreeRootContext<T = Record<string, any>> {
    modelValue: Ref<T | T[]>;
    selectedKeys: Ref<string[]>;
    onSelect: (val: T) => void;
    expanded: Ref<string[]>;
    onToggle: (val: T) => void;
    items: Ref<T[]>;
    expandedItems: Ref<T[]>;
    getKey: (val: T) => string;
    getChildren: (val: T) => T[] | undefined;
    multiple: Ref<boolean>;
    disabled: Ref<boolean>;
    dir: Ref<Direction>;
    propagateSelect: Ref<boolean>;
    isVirtual: Ref<boolean>;
    virtualKeydownHook: EventHook<KeyboardEvent>;
    handleMultipleReplace: ReturnType<typeof useSelectionBehavior>['handleMultipleReplace'];
}
export type FlattenedItem<T> = {
    _id: string;
    index: number;
    value: T;
    level: number;
    hasChildren: boolean;
    parentItem?: T;
    bind: {
        value: T;
        level: number;
        [key: string]: any;
    };
};
export declare const injectTreeRootContext: <T extends TreeRootContext<any> | null | undefined = TreeRootContext<any>>(fallback?: T | undefined) => T extends null ? TreeRootContext<any> | null : TreeRootContext<any>, provideTreeRootContext: (contextValue: TreeRootContext<any>) => TreeRootContext<any>;
declare const _default: <T extends Record<string, any>, U extends Record<string, any>>(__VLS_props: {
    "onUpdate:modelValue"?: ((val: U) => any) | undefined;
    "onUpdate:expanded"?: ((val: string[]) => any) | undefined;
    modelValue?: U | U[] | undefined;
    defaultValue?: U | U[] | undefined;
    items?: T[] | undefined;
    expanded?: string[] | undefined;
    defaultExpanded?: string[] | undefined;
    getKey: (val: T) => string;
    getChildren?: ((val: T) => T[] | undefined) | undefined;
    selectionBehavior?: "replace" | "toggle" | undefined;
    multiple?: boolean | undefined;
    dir?: Direction | undefined;
    disabled?: boolean | undefined;
    propagateSelect?: boolean | undefined;
    asChild?: boolean | undefined;
    as?: import('../Primitive').AsTag | import('vue').Component | undefined;
} & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps, __VLS_ctx?: {
    slots: Readonly<{
        default: (props: {
            flattenItems: FlattenedItem<T>[];
            modelValue: U | U[];
            expanded: string[];
        }) => any;
    }> & {
        default: (props: {
            flattenItems: FlattenedItem<T>[];
            modelValue: U | U[];
            expanded: string[];
        }) => any;
    };
    attrs: any;
    emit: ((evt: "update:modelValue", val: U) => void) & ((evt: "update:expanded", val: string[]) => void);
} | undefined, __VLS_expose?: ((exposed: import('vue').ShallowUnwrapRef<{}>) => void) | undefined, __VLS_setup?: Promise<{
    props: {
        "onUpdate:modelValue"?: ((val: U) => any) | undefined;
        "onUpdate:expanded"?: ((val: string[]) => any) | undefined;
        modelValue?: U | U[] | undefined;
        defaultValue?: U | U[] | undefined;
        items?: T[] | undefined;
        expanded?: string[] | undefined;
        defaultExpanded?: string[] | undefined;
        getKey: (val: T) => string;
        getChildren?: ((val: T) => T[] | undefined) | undefined;
        selectionBehavior?: "replace" | "toggle" | undefined;
        multiple?: boolean | undefined;
        dir?: Direction | undefined;
        disabled?: boolean | undefined;
        propagateSelect?: boolean | undefined;
        asChild?: boolean | undefined;
        as?: import('../Primitive').AsTag | import('vue').Component | undefined;
    } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
    expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
    attrs: any;
    slots: Readonly<{
        default: (props: {
            flattenItems: FlattenedItem<T>[];
            modelValue: U | U[];
            expanded: string[];
        }) => any;
    }> & {
        default: (props: {
            flattenItems: FlattenedItem<T>[];
            modelValue: U | U[];
            expanded: string[];
        }) => any;
    };
    emit: ((evt: "update:modelValue", val: U) => void) & ((evt: "update:expanded", val: string[]) => void);
}>) => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}> & {
    __ctx?: {
        props: {
            "onUpdate:modelValue"?: ((val: U) => any) | undefined;
            "onUpdate:expanded"?: ((val: string[]) => any) | undefined;
            modelValue?: U | U[] | undefined;
            defaultValue?: U | U[] | undefined;
            items?: T[] | undefined;
            expanded?: string[] | undefined;
            defaultExpanded?: string[] | undefined;
            getKey: (val: T) => string;
            getChildren?: ((val: T) => T[] | undefined) | undefined;
            selectionBehavior?: "replace" | "toggle" | undefined;
            multiple?: boolean | undefined;
            dir?: Direction | undefined;
            disabled?: boolean | undefined;
            propagateSelect?: boolean | undefined;
            asChild?: boolean | undefined;
            as?: import('../Primitive').AsTag | import('vue').Component | undefined;
        } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
        expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
        attrs: any;
        slots: Readonly<{
            default: (props: {
                flattenItems: FlattenedItem<T>[];
                modelValue: U | U[];
                expanded: string[];
            }) => any;
        }> & {
            default: (props: {
                flattenItems: FlattenedItem<T>[];
                modelValue: U | U[];
                expanded: string[];
            }) => any;
        };
        emit: ((evt: "update:modelValue", val: U) => void) & ((evt: "update:expanded", val: string[]) => void);
    } | undefined;
};
export default _default;
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
