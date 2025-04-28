import { Ref, VNode } from 'vue';
import { Direction } from '../shared/types';
export interface SelectRootProps {
    /** The controlled open state of the Select. Can be bind as `v-model:open`. */
    open?: boolean;
    /** The open state of the select when it is initially rendered. Use when you do not need to control its open state. */
    defaultOpen?: boolean;
    /** The value of the select when initially rendered. Use when you do not need to control the state of the Select */
    defaultValue?: string;
    /** The controlled value of the Select. Can be bind as `v-model`. */
    modelValue?: string;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** The name of the Select. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    /** Native html input `autocomplete` attribute. */
    autocomplete?: string;
    /** When `true`, prevents the user from interacting with Select */
    disabled?: boolean;
    /** When `true`, indicates that the user must select a value before the owning form can be submitted. */
    required?: boolean;
}
export type SelectRootEmits = {
    /** Event handler called when the value changes. */
    'update:modelValue': [value: string];
    /** Event handler called when the open state of the context menu changes. */
    'update:open': [value: boolean];
};
export interface SelectRootContext {
    triggerElement: Ref<HTMLElement | undefined>;
    onTriggerChange: (node: HTMLElement | undefined) => void;
    valueElement: Ref<HTMLElement | undefined>;
    onValueElementChange: (node: HTMLElement) => void;
    valueElementHasChildren: Ref<boolean>;
    onValueElementHasChildrenChange: (hasChildren: boolean) => void;
    contentId: string;
    modelValue?: Ref<string>;
    onValueChange: (value: string) => void;
    open: Ref<boolean>;
    required?: Ref<boolean>;
    onOpenChange: (open: boolean) => void;
    dir: Ref<Direction>;
    triggerPointerDownPosRef: Ref<{
        x: number;
        y: number;
    } | null>;
    disabled?: Ref<boolean>;
}
export declare const injectSelectRootContext: <T extends SelectRootContext | null | undefined = SelectRootContext>(fallback?: T | undefined) => T extends null ? SelectRootContext | null : SelectRootContext, provideSelectRootContext: (contextValue: SelectRootContext) => SelectRootContext;
export interface SelectNativeOptionsContext {
    onNativeOptionAdd: (option: VNode) => void;
    onNativeOptionRemove: (option: VNode) => void;
}
export declare const injectSelectNativeOptionsContext: <T extends SelectNativeOptionsContext | null | undefined = SelectNativeOptionsContext>(fallback?: T | undefined) => T extends null ? SelectNativeOptionsContext | null : SelectNativeOptionsContext, provideSelectNativeOptionsContext: (contextValue: SelectNativeOptionsContext) => SelectNativeOptionsContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SelectRootProps>, {
    defaultValue: string;
    modelValue: undefined;
    open: undefined;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
    "update:modelValue": (value: string) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SelectRootProps>, {
    defaultValue: string;
    modelValue: undefined;
    open: undefined;
}>>> & {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
    "onUpdate:modelValue"?: ((value: string) => any) | undefined;
}, {
    defaultValue: string;
    open: boolean;
    modelValue: string;
}, {}>, Readonly<{
    default: (props: {
        /** Current input values */
        modelValue: string;
        /** Current open state */
        open: boolean;
    }) => any;
}> & {
    default: (props: {
        /** Current input values */
        modelValue: string;
        /** Current open state */
        open: boolean;
    }) => any;
}>;
export default _default;
type __VLS_WithDefaults<P, D> = {
    [K in keyof Pick<P, keyof P>]: K extends keyof D ? __VLS_PrettifyLocal<P[K] & {
        default: D[K];
    }> : P[K];
};
type __VLS_NonUndefinedable<T> = T extends undefined ? never : T;
type __VLS_TypePropsToOption<T> = {
    [K in keyof T]-?: {} extends Pick<T, K> ? {
        type: import('vue').PropType<__VLS_NonUndefinedable<T[K]>>;
    } : {
        type: import('vue').PropType<T[K]>;
        required: true;
    };
};
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
