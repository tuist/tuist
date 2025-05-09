import { PopperContentProps } from '../Popper';
import { DismissableLayerEmits, DismissableLayerProps } from '../DismissableLayer';
import { FocusScopeProps } from '../FocusScope';
export type PopoverContentImplEmits = DismissableLayerEmits & {
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
export interface PopoverContentImplProps extends PopperContentProps, DismissableLayerProps {
    /**
     * Whether focus should be trapped within the `MenuContent`
     * @defaultValue false
     */
    trapFocus?: FocusScopeProps['trapped'];
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<PopoverContentImplProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent) => void;
    focusOutside: (event: import('../DismissableLayer').FocusOutsideEvent) => void;
    interactOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => void;
    openAutoFocus: (event: Event) => void;
    closeAutoFocus: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<PopoverContentImplProps>>> & {
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
