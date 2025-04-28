import { PrimitiveProps } from '../Primitive';
import { SwipeEvent } from './utils';
export type ToastRootImplEmits = {
    close: [];
    /** Event handler called when the escape key is down. It can be prevented by calling `event.preventDefault`. */
    escapeKeyDown: [event: KeyboardEvent];
    /** Event handler called when the dismiss timer is paused. This occurs when the pointer is moved over the viewport, the viewport is focused or when the window is blurred. */
    pause: [];
    /** Event handler called when the dismiss timer is resumed. This occurs when the pointer is moved away from the viewport, the viewport is blurred or when the window is focused. */
    resume: [];
    /** Event handler called when starting a swipe interaction. It can be prevented by calling `event.preventDefault`. */
    swipeStart: [event: SwipeEvent];
    /** Event handler called during a swipe interaction. It can be prevented by calling `event.preventDefault`. */
    swipeMove: [event: SwipeEvent];
    swipeCancel: [event: SwipeEvent];
    /** Event handler called at the end of a swipe interaction. It can be prevented by calling `event.preventDefault`. */
    swipeEnd: [event: SwipeEvent];
};
export interface ToastRootImplProps extends PrimitiveProps {
    /**
     * Control the sensitivity of the toast for accessibility purposes.
     *
     * For toasts that are the result of a user action, choose `foreground`. Toasts generated from background tasks should use `background`.
     */
    type?: 'foreground' | 'background';
    /**
     * The controlled open state of the dialog. Can be bind as `v-model:open`.
     */
    open?: boolean;
    /**
     * Time in milliseconds that toast should remain visible for. Overrides value
     * given to `ToastProvider`.
     */
    duration?: number;
}
export declare const injectToastRootContext: <T extends {
    onClose: () => void;
} | null | undefined = {
    onClose: () => void;
}>(fallback?: T | undefined) => T extends null ? {
    onClose: () => void;
} | null : {
    onClose: () => void;
}, provideToastRootContext: (contextValue: {
    onClose: () => void;
}) => {
    onClose: () => void;
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastRootImplProps>, {
    open: boolean;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    close: () => void;
    pause: () => void;
    escapeKeyDown: (event: KeyboardEvent) => void;
    resume: () => void;
    swipeStart: (event: SwipeEvent) => void;
    swipeMove: (event: SwipeEvent) => void;
    swipeCancel: (event: SwipeEvent) => void;
    swipeEnd: (event: SwipeEvent) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastRootImplProps>, {
    open: boolean;
    as: string;
}>>> & {
    onClose?: (() => any) | undefined;
    onPause?: (() => any) | undefined;
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onResume?: (() => any) | undefined;
    onSwipeStart?: ((event: SwipeEvent) => any) | undefined;
    onSwipeMove?: ((event: SwipeEvent) => any) | undefined;
    onSwipeCancel?: ((event: SwipeEvent) => any) | undefined;
    onSwipeEnd?: ((event: SwipeEvent) => any) | undefined;
}, {
    as: import('../Primitive').AsTag | import('vue').Component;
    open: boolean;
}, {}>, {
    default?(_: {
        remaining: number;
        duration: number;
    }): any;
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
