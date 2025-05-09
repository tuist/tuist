import { Ref } from 'vue';
export interface HoverCardRootProps {
    /** The open state of the hover card when it is initially rendered. Use when you do not need to control its open state. */
    defaultOpen?: false;
    /** The controlled open state of the hover card. Can be binded as `v-model:open`. */
    open?: boolean;
    /** The duration from when the mouse enters the trigger until the hover card opens. */
    openDelay?: number;
    /** The duration from when the mouse leaves the trigger or content until the hover card closes. */
    closeDelay?: number;
}
export type HoverCardRootEmits = {
    /** Event handler called when the open state of the hover card changes. */
    'update:open': [value: boolean];
};
export interface HoverCardRootContext {
    open: Ref<boolean>;
    onOpenChange: (open: boolean) => void;
    onOpen: () => void;
    onClose: () => void;
    onDismiss: () => void;
    hasSelectionRef: Ref<boolean>;
    isPointerDownOnContentRef: Ref<boolean>;
    isPointerInTransitRef: Ref<boolean>;
    triggerElement: Ref<HTMLElement | undefined>;
}
export declare const injectHoverCardRootContext: <T extends HoverCardRootContext | null | undefined = HoverCardRootContext>(fallback?: T | undefined) => T extends null ? HoverCardRootContext | null : HoverCardRootContext, provideHoverCardRootContext: (contextValue: HoverCardRootContext) => HoverCardRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<HoverCardRootProps>, {
    defaultOpen: boolean;
    open: undefined;
    openDelay: number;
    closeDelay: number;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<HoverCardRootProps>, {
    defaultOpen: boolean;
    open: undefined;
    openDelay: number;
    closeDelay: number;
}>>> & {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
}, {
    defaultOpen: false;
    open: boolean;
    openDelay: number;
    closeDelay: number;
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
