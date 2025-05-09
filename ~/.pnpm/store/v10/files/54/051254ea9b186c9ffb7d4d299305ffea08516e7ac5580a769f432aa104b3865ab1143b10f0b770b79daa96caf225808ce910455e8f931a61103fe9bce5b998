import { Ref } from 'vue';
import { DismissableLayerEmits, DismissableLayerProps } from '../DismissableLayer';
import { PopperContentProps } from '../Popper';
export type ComboboxContentImplEmits = DismissableLayerEmits;
export interface ComboboxContentImplProps extends PopperContentProps, DismissableLayerProps {
    /**
     * The positioning mode to use, <br>
     * `inline` is the default and you can control the position using CSS. <br>
     * `popper` positions content in the same way as our other primitives, for example `Popover` or `DropdownMenu`.
     */
    position?: 'inline' | 'popper';
    /** The document.body will be lock, and scrolling will be disabled. */
    bodyLock?: boolean;
    /**
     * Allow component to be dismissableLayer.
     * @deprecated (Will be removed in version 2.0, use `Listbox` instead)
     */
    dismissable?: boolean;
}
export declare const injectComboboxContentContext: <T extends {
    position: Ref<'inline' | 'popper'>;
} | null | undefined = {
    position: Ref<'inline' | 'popper'>;
}>(fallback?: T | undefined) => T extends null ? {
    position: Ref<'inline' | 'popper'>;
} | null : {
    position: Ref<'inline' | 'popper'>;
}, provideComboboxContentContext: (contextValue: {
    position: Ref<'inline' | 'popper'>;
}) => {
    position: Ref<'inline' | 'popper'>;
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ComboboxContentImplProps>, {
    position: string;
    dismissable: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent) => void;
    focusOutside: (event: import('../DismissableLayer').FocusOutsideEvent) => void;
    interactOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ComboboxContentImplProps>, {
    position: string;
    dismissable: boolean;
}>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent) => any) | undefined;
    onFocusOutside?: ((event: import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onInteractOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
}, {
    position: "inline" | "popper";
    dismissable: boolean;
}, {}>, {
    default?(_: {}): any;
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
