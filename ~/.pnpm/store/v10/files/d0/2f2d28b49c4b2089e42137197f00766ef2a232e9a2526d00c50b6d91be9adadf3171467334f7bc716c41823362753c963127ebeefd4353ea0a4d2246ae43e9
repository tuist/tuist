import { PrimitiveProps } from '../Primitive';
import { FocusOutsideEvent, PointerDownOutsideEvent } from './utils';
export interface DismissableLayerProps extends PrimitiveProps {
    /**
     * When `true`, hover/focus/click interactions will be disabled on elements outside
     * the `DismissableLayer`. Users will need to click twice on outside elements to
     * interact with them: once to close the `DismissableLayer`, and again to trigger the element.
     */
    disableOutsidePointerEvents?: boolean;
}
export type DismissableLayerEmits = {
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
    /**
     * Event handler called when the focus moves outside of the `DismissableLayer`.
     * Can be prevented.
     */
    focusOutside: [event: FocusOutsideEvent];
    /**
     * Event handler called when an interaction happens outside the `DismissableLayer`.
     * Specifically, when a `pointerdown` event happens outside or focus moves outside of it.
     * Can be prevented.
     */
    interactOutside: [event: PointerDownOutsideEvent | FocusOutsideEvent];
};
export type DismissableLayerPrivateEmits = DismissableLayerEmits & {
    /**
     * Handler called when the `DismissableLayer` should be dismissed
     */
    dismiss: [];
};
export declare const context: {
    layersRoot: Set<HTMLElement> & Omit<Set<HTMLElement>, keyof Set<any>>;
    layersWithOutsidePointerEventsDisabled: Set<HTMLElement> & Omit<Set<HTMLElement>, keyof Set<any>>;
    branches: Set<HTMLElement> & Omit<Set<HTMLElement>, keyof Set<any>>;
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<DismissableLayerProps>, {
    disableOutsidePointerEvents: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: PointerDownOutsideEvent) => void;
    focusOutside: (event: FocusOutsideEvent) => void;
    interactOutside: (event: PointerDownOutsideEvent | FocusOutsideEvent) => void;
    dismiss: () => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<DismissableLayerProps>, {
    disableOutsidePointerEvents: boolean;
}>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: PointerDownOutsideEvent) => any) | undefined;
    onFocusOutside?: ((event: FocusOutsideEvent) => any) | undefined;
    onInteractOutside?: ((event: PointerDownOutsideEvent | FocusOutsideEvent) => any) | undefined;
    onDismiss?: (() => any) | undefined;
}, {
    disableOutsidePointerEvents: boolean;
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
