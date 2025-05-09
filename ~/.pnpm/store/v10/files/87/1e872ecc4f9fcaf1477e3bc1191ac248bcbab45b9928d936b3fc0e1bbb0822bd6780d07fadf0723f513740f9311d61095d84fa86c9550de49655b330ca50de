import { Ref } from 'vue';
import { PopperContentProps } from '../Popper';
import { PointerDownOutsideEvent } from '../DismissableLayer';
interface SelectContentContext {
    content?: Ref<HTMLElement | undefined>;
    viewport?: Ref<HTMLElement | undefined>;
    onViewportChange: (node: HTMLElement | undefined) => void;
    itemRefCallback: (node: HTMLElement | undefined, value: string, disabled: boolean) => void;
    selectedItem?: Ref<HTMLElement | undefined>;
    onItemLeave?: () => void;
    itemTextRefCallback: (node: HTMLElement | undefined, value: string, disabled: boolean) => void;
    focusSelectedItem?: () => void;
    selectedItemText?: Ref<HTMLElement | undefined>;
    position?: 'item-aligned' | 'popper';
    isPositioned?: Ref<boolean>;
    searchRef?: Ref<string>;
}
export declare const SelectContentDefaultContextValue: SelectContentContext;
export type SelectContentImplEmits = {
    closeAutoFocus: [event: Event];
    /**
     * Event handler called when the escape key is down.
     * Can be prevented.
     */
    escapeKeyDown: [event: KeyboardEvent];
    /**
     * Event handler called when the a `pointerdown` event happens outside of the `DismissableLayer`.
     * Can be prevented.
     */
    pointerDownOutside: [event: PointerDownOutsideEvent];
};
export interface SelectContentImplProps extends PopperContentProps {
    /**
     *  The positioning mode to use
     *
     *  `item-aligned (default)` - behaves similarly to a native MacOS menu by positioning content relative to the active item. <br>
     *  `popper` - positions content in the same way as our other primitives, for example `Popover` or `DropdownMenu`.
     */
    position?: 'item-aligned' | 'popper';
    /**
     * The document.body will be lock, and scrolling will be disabled.
     *
     * @defaultValue true
     */
    bodyLock?: boolean;
}
export declare const injectSelectContentContext: <T extends SelectContentContext | null | undefined = SelectContentContext>(fallback?: T | undefined) => T extends null ? SelectContentContext | null : SelectContentContext, provideSelectContentContext: (contextValue: SelectContentContext) => SelectContentContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SelectContentImplProps>, {
    align: string;
    position: string;
    bodyLock: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: PointerDownOutsideEvent) => void;
    closeAutoFocus: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SelectContentImplProps>, {
    align: string;
    position: string;
    bodyLock: boolean;
}>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: PointerDownOutsideEvent) => any) | undefined;
    onCloseAutoFocus?: ((event: Event) => any) | undefined;
}, {
    align: "center" | "end" | "start";
    position: "popper" | "item-aligned";
    bodyLock: boolean;
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
