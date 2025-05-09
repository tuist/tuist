import { PrimitiveProps } from '../Primitive';
import { Ref } from 'vue';
export interface CollapsibleRootProps extends PrimitiveProps {
    /** The open state of the collapsible when it is initially rendered. <br> Use when you do not need to control its open state. */
    defaultOpen?: boolean;
    /** The controlled open state of the collapsible. Can be binded with `v-model`. */
    open?: boolean;
    /** When `true`, prevents the user from interacting with the collapsible. */
    disabled?: boolean;
}
export type CollapsibleRootEmits = {
    /** Event handler called when the open state of the collapsible changes. */
    'update:open': [value: boolean];
};
interface CollapsibleRootContext {
    contentId: string;
    disabled?: Ref<boolean>;
    open: Ref<boolean>;
    onOpenToggle: () => void;
}
export declare const injectCollapsibleRootContext: <T extends CollapsibleRootContext | null | undefined = CollapsibleRootContext>(fallback?: T | undefined) => T extends null ? CollapsibleRootContext | null : CollapsibleRootContext, provideCollapsibleRootContext: (contextValue: CollapsibleRootContext) => CollapsibleRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<CollapsibleRootProps>, {
    open: undefined;
    defaultOpen: boolean;
}>, {
    open: Ref<boolean>;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<CollapsibleRootProps>, {
    open: undefined;
    defaultOpen: boolean;
}>>> & {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
}, {
    defaultOpen: boolean;
    open: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current open state */
        open: boolean;
    }) => any;
}> & {
    default: (props: {
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
