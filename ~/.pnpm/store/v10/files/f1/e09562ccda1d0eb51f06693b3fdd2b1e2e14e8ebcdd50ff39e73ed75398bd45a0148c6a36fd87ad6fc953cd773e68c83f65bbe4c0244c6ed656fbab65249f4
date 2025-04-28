import { ToastRootImplEmits, ToastRootImplProps } from './ToastRootImpl';
export type ToastRootEmits = Omit<ToastRootImplEmits, 'close'> & {
    /** Event handler called when the open state changes */
    'update:open': [value: boolean];
};
export interface ToastRootProps extends ToastRootImplProps {
    /** The open state of the dialog when it is initially rendered. Use when you do not need to control its open state. */
    defaultOpen?: boolean;
    /**
     * Used to force mounting when more control is needed. Useful when
     * controlling animation with Vue animation libraries.
     */
    forceMount?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastRootProps>, {
    type: string;
    open: undefined;
    defaultOpen: boolean;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    pause: () => void;
    "update:open": (value: boolean) => void;
    escapeKeyDown: (event: KeyboardEvent) => void;
    resume: () => void;
    swipeStart: (event: import('./utils').SwipeEvent) => void;
    swipeMove: (event: import('./utils').SwipeEvent) => void;
    swipeCancel: (event: import('./utils').SwipeEvent) => void;
    swipeEnd: (event: import('./utils').SwipeEvent) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastRootProps>, {
    type: string;
    open: undefined;
    defaultOpen: boolean;
    as: string;
}>>> & {
    onPause?: (() => any) | undefined;
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onResume?: (() => any) | undefined;
    onSwipeStart?: ((event: import('./utils').SwipeEvent) => any) | undefined;
    onSwipeMove?: ((event: import('./utils').SwipeEvent) => any) | undefined;
    onSwipeCancel?: ((event: import('./utils').SwipeEvent) => any) | undefined;
    onSwipeEnd?: ((event: import('./utils').SwipeEvent) => any) | undefined;
}, {
    type: "background" | "foreground";
    as: import('../Primitive').AsTag | import('vue').Component;
    defaultOpen: boolean;
    open: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current open state */
        open: boolean;
        /** Remaining time (in ms) */
        remaining: number;
        /** Total time the toast will remain visible for (in ms) */
        duration: number;
    }) => any;
}> & {
    default: (props: {
        /** Current open state */
        open: boolean;
        /** Remaining time (in ms) */
        remaining: number;
        /** Total time the toast will remain visible for (in ms) */
        duration: number;
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
