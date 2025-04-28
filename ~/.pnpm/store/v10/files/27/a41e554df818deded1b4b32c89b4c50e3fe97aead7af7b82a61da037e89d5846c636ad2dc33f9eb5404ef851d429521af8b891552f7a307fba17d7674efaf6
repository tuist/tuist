import { DismissableLayerEmits, DismissableLayerProps } from '../DismissableLayer';
export type DialogContentImplEmits = DismissableLayerEmits & {
    /**
     * Event handler called when auto-focusing on open.
     * Can be prevented.
     */
    openAutoFocus: [event: Event];
    /**
     * Event handler called when auto-focusing on close.
     * Can be prevented.
     */
    closeAutoFocus: [event: Event];
};
export interface DialogContentImplProps extends DismissableLayerProps {
    /**
     * Used to force mounting when more control is needed. Useful when
     * controlling transntion with Vue native transition or other animation libraries.
     */
    forceMount?: boolean;
    /**
     * When `true`, focus cannot escape the `Content` via keyboard,
     * pointer, or a programmatic focus.
     * @defaultValue false
     */
    trapFocus?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<DialogContentImplProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent) => void;
    focusOutside: (event: import('../DismissableLayer').FocusOutsideEvent) => void;
    interactOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => void;
    openAutoFocus: (event: Event) => void;
    closeAutoFocus: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<DialogContentImplProps>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent) => any) | undefined;
    onFocusOutside?: ((event: import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onInteractOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onOpenAutoFocus?: ((event: Event) => any) | undefined;
    onCloseAutoFocus?: ((event: Event) => any) | undefined;
}, {}, {}>, {
    default?(_: {}): any;
}>;
export default _default;
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
