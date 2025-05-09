import { Ref } from 'vue';
export interface TooltipRootProps {
    /**
     * The open state of the tooltip when it is initially rendered.
     * Use when you do not need to control its open state.
     */
    defaultOpen?: boolean;
    /**
     * The controlled open state of the tooltip.
     */
    open?: boolean;
    /**
     * Override the duration given to the `Provider` to customise
     * the open delay for a specific tooltip.
     *
     * @defaultValue 700
     */
    delayDuration?: number;
    /**
     * Prevents Tooltip.Content from remaining open when hovering.
     * Disabling this has accessibility consequences. Inherits
     * from Tooltip.Provider.
     */
    disableHoverableContent?: boolean;
    /**
     * When `true`, clicking on trigger will not close the content.
     * @defaultValue false
     */
    disableClosingTrigger?: boolean;
    /**
     * When `true`, disable tooltip
     * @defaultValue false
     */
    disabled?: boolean;
    /**
     * Prevent the tooltip from opening if the focus did not come from
     * the keyboard by matching against the `:focus-visible` selector.
     * This is useful if you want to avoid opening it when switching
     * browser tabs or closing a dialog.
     * @defaultValue false
     */
    ignoreNonKeyboardFocus?: boolean;
}
export type TooltipRootEmits = {
    /** Event handler called when the open state of the tooltip changes. */
    'update:open': [value: boolean];
};
export interface TooltipContext {
    contentId: string;
    open: Ref<boolean>;
    stateAttribute: Ref<'closed' | 'delayed-open' | 'instant-open'>;
    trigger: Ref<HTMLElement | undefined>;
    onTriggerChange: (trigger: HTMLElement | undefined) => void;
    onTriggerEnter: () => void;
    onTriggerLeave: () => void;
    onOpen: () => void;
    onClose: () => void;
    disableHoverableContent: Ref<boolean>;
    disableClosingTrigger: Ref<boolean>;
    disabled: Ref<boolean>;
    ignoreNonKeyboardFocus: Ref<boolean>;
}
export declare const injectTooltipRootContext: <T extends TooltipContext | null | undefined = TooltipContext>(fallback?: T | undefined) => T extends null ? TooltipContext | null : TooltipContext, provideTooltipRootContext: (contextValue: TooltipContext) => TooltipContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<TooltipRootProps>, {
    defaultOpen: boolean;
    open: undefined;
    delayDuration: undefined;
    disableHoverableContent: undefined;
    disableClosingTrigger: undefined;
    disabled: undefined;
    ignoreNonKeyboardFocus: undefined;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<TooltipRootProps>, {
    defaultOpen: boolean;
    open: undefined;
    delayDuration: undefined;
    disableHoverableContent: undefined;
    disableClosingTrigger: undefined;
    disabled: undefined;
    ignoreNonKeyboardFocus: undefined;
}>>> & {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
}, {
    disabled: boolean;
    defaultOpen: boolean;
    open: boolean;
    delayDuration: number;
    disableHoverableContent: boolean;
    disableClosingTrigger: boolean;
    ignoreNonKeyboardFocus: boolean;
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
