import { EventHook } from '@vueuse/core';
import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { AcceptableValue, DataOrientation, Direction } from '../shared/types';
type ListboxRootContext<T> = {
    modelValue: Ref<T | Array<T> | undefined>;
    onValueChange: (val: T) => void;
    multiple: Ref<boolean>;
    orientation: Ref<DataOrientation>;
    dir: Ref<Direction>;
    disabled: Ref<boolean>;
    highlightOnHover: Ref<boolean>;
    highlightedElement: Ref<HTMLElement | null>;
    isVirtual: Ref<boolean>;
    virtualFocusHook: EventHook<Event | null>;
    virtualKeydownHook: EventHook<KeyboardEvent>;
    by?: string | ((a: T, b: T) => boolean);
    firstValue?: Ref<T | undefined>;
    selectionBehavior?: Ref<'toggle' | 'replace'>;
    focusable: Ref<boolean>;
    onLeave: (event: Event) => void;
    onEnter: (event: Event) => void;
    onChangeHighlight: (el: HTMLElement) => void;
    onKeydownNavigation: (event: KeyboardEvent) => void;
    onKeydownEnter: (event: KeyboardEvent) => void;
    onKeydownTypeAhead: (event: KeyboardEvent) => void;
};
export declare const injectListboxRootContext: <T extends ListboxRootContext<AcceptableValue> | null | undefined = ListboxRootContext<AcceptableValue>>(fallback?: T | undefined) => T extends null ? ListboxRootContext<AcceptableValue> | null : ListboxRootContext<AcceptableValue>, provideListboxRootContext: (contextValue: ListboxRootContext<AcceptableValue>) => ListboxRootContext<AcceptableValue>;
export interface ListboxRootProps<T = AcceptableValue> extends PrimitiveProps {
    /** The controlled value of the listbox. Can be binded with with `v-model`. */
    modelValue?: T | Array<T>;
    /** The value of the listbox when initially rendered. Use when you do not need to control the state of the Listbox */
    defaultValue?: T | Array<T>;
    /** Whether multiple options can be selected or not. */
    multiple?: boolean;
    /** The orientation of the listbox. <br>Mainly so arrow navigation is done accordingly (left & right vs. up & down) */
    orientation?: DataOrientation;
    /** The reading direction of the listbox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** When `true`, prevents the user from interacting with listbox */
    disabled?: boolean;
    /**
     * How multiple selection should behave in the collection.
     * @defaultValue 'toggle'
     */
    selectionBehavior?: 'toggle' | 'replace';
    /** When `true`, hover over item will trigger highlight */
    highlightOnHover?: boolean;
    /** Use this to compare objects by a particular field, or pass your own comparison function for complete control over how objects are compared. */
    by?: string | ((a: T, b: T) => boolean);
    /** The name of the listbox. Submitted with its owning form as part of a name/value pair. */
    name?: string;
}
export type ListboxRootEmits<T = AcceptableValue> = {
    /** Event handler called when the value changes. */
    'update:modelValue': [value: T];
    /** Event handler when highlighted element changes. */
    'highlight': [payload: {
        ref: HTMLElement;
        value: T;
    } | undefined];
    /** Event handler called when container is being focused. Can be prevented. */
    'entryFocus': [event: CustomEvent];
    /** Event handler called when the mouse leave the container */
    'leave': [event: Event];
};
declare const _default: <T extends AcceptableValue = AcceptableValue>(__VLS_props: {
    "onUpdate:modelValue"?: ((value: AcceptableValue) => any) | undefined;
    onEntryFocus?: ((event: CustomEvent<any>) => any) | undefined;
    onHighlight?: ((payload: {
        ref: HTMLElement;
        value: AcceptableValue;
    } | undefined) => any) | undefined;
    onLeave?: ((event: Event) => any) | undefined;
    modelValue?: AcceptableValue | AcceptableValue[] | undefined;
    defaultValue?: AcceptableValue | AcceptableValue[] | undefined;
    multiple?: boolean | undefined;
    orientation?: DataOrientation | undefined;
    dir?: Direction | undefined;
    disabled?: boolean | undefined;
    selectionBehavior?: "replace" | "toggle" | undefined;
    highlightOnHover?: boolean | undefined;
    by?: string | ((a: AcceptableValue, b: AcceptableValue) => boolean) | undefined;
    name?: string | undefined;
    asChild?: boolean | undefined;
    as?: import('../Primitive').AsTag | import('vue').Component | undefined;
} & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps, __VLS_ctx?: {
    slots: Readonly<{
        default: (props: {
            /** Current active value */
            modelValue: T | T[] | undefined;
        }) => any;
    }> & {
        default: (props: {
            /** Current active value */
            modelValue: T | T[] | undefined;
        }) => any;
    };
    attrs: any;
    emit: ((evt: "leave", event: Event) => void) & ((evt: "update:modelValue", value: AcceptableValue) => void) & ((evt: "highlight", payload: {
        ref: HTMLElement;
        value: AcceptableValue;
    } | undefined) => void) & ((evt: "entryFocus", event: CustomEvent<any>) => void);
} | undefined, __VLS_expose?: ((exposed: import('vue').ShallowUnwrapRef<{}>) => void) | undefined, __VLS_setup?: Promise<{
    props: {
        "onUpdate:modelValue"?: ((value: AcceptableValue) => any) | undefined;
        onEntryFocus?: ((event: CustomEvent<any>) => any) | undefined;
        onHighlight?: ((payload: {
            ref: HTMLElement;
            value: AcceptableValue;
        } | undefined) => any) | undefined;
        onLeave?: ((event: Event) => any) | undefined;
        modelValue?: AcceptableValue | AcceptableValue[] | undefined;
        defaultValue?: AcceptableValue | AcceptableValue[] | undefined;
        multiple?: boolean | undefined;
        orientation?: DataOrientation | undefined;
        dir?: Direction | undefined;
        disabled?: boolean | undefined;
        selectionBehavior?: "replace" | "toggle" | undefined;
        highlightOnHover?: boolean | undefined;
        by?: string | ((a: AcceptableValue, b: AcceptableValue) => boolean) | undefined;
        name?: string | undefined;
        asChild?: boolean | undefined;
        as?: import('../Primitive').AsTag | import('vue').Component | undefined;
    } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
    expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
    attrs: any;
    slots: Readonly<{
        default: (props: {
            /** Current active value */
            modelValue: T | T[] | undefined;
        }) => any;
    }> & {
        default: (props: {
            /** Current active value */
            modelValue: T | T[] | undefined;
        }) => any;
    };
    emit: ((evt: "leave", event: Event) => void) & ((evt: "update:modelValue", value: AcceptableValue) => void) & ((evt: "highlight", payload: {
        ref: HTMLElement;
        value: AcceptableValue;
    } | undefined) => void) & ((evt: "entryFocus", event: CustomEvent<any>) => void);
}>) => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}> & {
    __ctx?: {
        props: {
            "onUpdate:modelValue"?: ((value: AcceptableValue) => any) | undefined;
            onEntryFocus?: ((event: CustomEvent<any>) => any) | undefined;
            onHighlight?: ((payload: {
                ref: HTMLElement;
                value: AcceptableValue;
            } | undefined) => any) | undefined;
            onLeave?: ((event: Event) => any) | undefined;
            modelValue?: AcceptableValue | AcceptableValue[] | undefined;
            defaultValue?: AcceptableValue | AcceptableValue[] | undefined;
            multiple?: boolean | undefined;
            orientation?: DataOrientation | undefined;
            dir?: Direction | undefined;
            disabled?: boolean | undefined;
            selectionBehavior?: "replace" | "toggle" | undefined;
            highlightOnHover?: boolean | undefined;
            by?: string | ((a: AcceptableValue, b: AcceptableValue) => boolean) | undefined;
            name?: string | undefined;
            asChild?: boolean | undefined;
            as?: import('../Primitive').AsTag | import('vue').Component | undefined;
        } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
        expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
        attrs: any;
        slots: Readonly<{
            default: (props: {
                /** Current active value */
                modelValue: T | T[] | undefined;
            }) => any;
        }> & {
            default: (props: {
                /** Current active value */
                modelValue: T | T[] | undefined;
            }) => any;
        };
        emit: ((evt: "leave", event: Event) => void) & ((evt: "update:modelValue", value: AcceptableValue) => void) & ((evt: "highlight", payload: {
            ref: HTMLElement;
            value: AcceptableValue;
        } | undefined) => void) & ((evt: "entryFocus", event: CustomEvent<any>) => void);
    } | undefined;
};
export default _default;
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
