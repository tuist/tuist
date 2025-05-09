import { Ref } from 'vue';
export interface DialogRootProps {
    /** The controlled open state of the dialog. Can be binded as `v-model:open`. */
    open?: boolean;
    /** The open state of the dialog when it is initially rendered. Use when you do not need to control its open state. */
    defaultOpen?: boolean;
    /**
     * The modality of the dialog When set to `true`, <br>
     * interaction with outside elements will be disabled and only dialog content will be visible to screen readers.
     */
    modal?: boolean;
}
export type DialogRootEmits = {
    /** Event handler called when the open state of the dialog changes. */
    'update:open': [value: boolean];
};
export interface DialogRootContext {
    open: Readonly<Ref<boolean>>;
    modal: Ref<boolean>;
    openModal: () => void;
    onOpenChange: (value: boolean) => void;
    onOpenToggle: () => void;
    triggerElement: Ref<HTMLElement | undefined>;
    contentElement: Ref<HTMLElement | undefined>;
    contentId: string;
    titleId: string;
    descriptionId: string;
}
export declare const injectDialogRootContext: <T extends DialogRootContext | null | undefined = DialogRootContext>(fallback?: T | undefined) => T extends null ? DialogRootContext | null : DialogRootContext, provideDialogRootContext: (contextValue: DialogRootContext) => DialogRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<DialogRootProps>, {
    open: undefined;
    defaultOpen: boolean;
    modal: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<DialogRootProps>, {
    open: undefined;
    defaultOpen: boolean;
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
