import { Ref } from 'vue';
export interface PopoverRootProps {
    /**
     * The open state of the popover when it is initially rendered. Use when you do not need to control its open state.
     */
    defaultOpen?: boolean;
    /**
     * The controlled open state of the popover.
     */
    open?: boolean;
    /**
     * The modality of the popover. When set to true, interaction with outside elements will be disabled and only popover content will be visible to screen readers.
     *
     * @defaultValue false
     */
    modal?: boolean;
}
export type PopoverRootEmits = {
    /**
     * Event handler called when the open state of the popover changes.
     */
    'update:open': [value: boolean];
};
export interface PopoverRootContext {
    triggerElement: Ref<HTMLElement | undefined>;
    contentId: string;
    open: Ref<boolean>;
    modal: Ref<boolean>;
    onOpenChange: (value: boolean) => void;
    onOpenToggle: () => void;
    hasCustomAnchor: Ref<boolean>;
}
export declare const injectPopoverRootContext: <T extends PopoverRootContext | null | undefined = PopoverRootContext>(fallback?: T | undefined) => T extends null ? PopoverRootContext | null : PopoverRootContext, providePopoverRootContext: (contextValue: PopoverRootContext) => PopoverRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<PopoverRootProps>, {
    defaultOpen: boolean;
    open: undefined;
    modal: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<PopoverRootProps>, {
    defaultOpen: boolean;
    open: undefined;
    modal: boolean;
}>>> & {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
}, {
    defaultOpen: boolean;
    open: boolean;
    modal: boolean;
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
