import { Ref } from 'vue';
interface TooltipProviderContext {
    isOpenDelayed: Ref<boolean>;
    delayDuration: Ref<number>;
    onOpen: () => void;
    onClose: () => void;
    isPointerInTransitRef: Ref<boolean>;
    disableHoverableContent: Ref<boolean>;
    disableClosingTrigger: Ref<boolean>;
    disabled: Ref<boolean>;
    ignoreNonKeyboardFocus: Ref<boolean>;
}
export declare const injectTooltipProviderContext: <T extends TooltipProviderContext | null | undefined = TooltipProviderContext>(fallback?: T | undefined) => T extends null ? TooltipProviderContext | null : TooltipProviderContext, provideTooltipProviderContext: (contextValue: TooltipProviderContext) => TooltipProviderContext;
export interface TooltipProviderProps {
    /**
     * The duration from when the pointer enters the trigger until the tooltip gets opened.
     * @defaultValue 700
     */
    delayDuration?: number;
    /**
     * How much time a user has to enter another trigger without incurring a delay again.
     * @defaultValue 300
     */
    skipDelayDuration?: number;
    /**
     * When `true`, trying to hover the content will result in the tooltip closing as the pointer leaves the trigger.
     * @defaultValue false
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
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<TooltipProviderProps>, {
    delayDuration: number;
    skipDelayDuration: number;
    disableHoverableContent: boolean;
    ignoreNonKeyboardFocus: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<TooltipProviderProps>, {
    delayDuration: number;
    skipDelayDuration: number;
    disableHoverableContent: boolean;
    ignoreNonKeyboardFocus: boolean;
}>>>, {
    delayDuration: number;
    skipDelayDuration: number;
    disableHoverableContent: boolean;
    ignoreNonKeyboardFocus: boolean;
}, {}>, {
    default?(_: {}): any;
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
