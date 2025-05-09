import { Ref } from 'vue';
import { SwipeDirection } from './utils';
type ToastProviderContext = {
    label: Ref<string>;
    duration: Ref<number>;
    swipeDirection: Ref<SwipeDirection>;
    swipeThreshold: Ref<number>;
    toastCount: Ref<number>;
    viewport: Ref<HTMLElement | undefined>;
    onViewportChange: (viewport: HTMLElement) => void;
    onToastAdd: () => void;
    onToastRemove: () => void;
    isFocusedToastEscapeKeyDownRef: Ref<boolean>;
    isClosePausedRef: Ref<boolean>;
};
export interface ToastProviderProps {
    /**
     * An author-localized label for each toast. Used to help screen reader users
     * associate the interruption with a toast.
     * @defaultValue 'Notification'
     */
    label?: string;
    /**
     * Time in milliseconds that each toast should remain visible for.
     * @defaultValue 5000
     */
    duration?: number;
    /**
     * Direction of pointer swipe that should close the toast.
     * @defaultValue 'right'
     */
    swipeDirection?: SwipeDirection;
    /**
     * Distance in pixels that the swipe must pass before a close is triggered.
     * @defaultValue 50
     */
    swipeThreshold?: number;
}
export declare const injectToastProviderContext: <T extends ToastProviderContext | null | undefined = ToastProviderContext>(fallback?: T | undefined) => T extends null ? ToastProviderContext | null : ToastProviderContext, provideToastProviderContext: (contextValue: ToastProviderContext) => ToastProviderContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastProviderProps>, {
    label: string;
    duration: number;
    swipeDirection: string;
    swipeThreshold: number;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastProviderProps>, {
    label: string;
    duration: number;
    swipeDirection: string;
    swipeThreshold: number;
}>>>, {
    label: string;
    duration: number;
    swipeDirection: SwipeDirection;
    swipeThreshold: number;
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
