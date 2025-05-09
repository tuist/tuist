import { PrimitiveProps } from '../Primitive';
export interface ToastViewportProps extends PrimitiveProps {
    /**
     * The keys to use as the keyboard shortcut that will move focus to the toast viewport.
     * @defaultValue ['F8']
     */
    hotkey?: string[];
    /**
     * An author-localized label for the toast viewport to provide context for screen reader users
     * when navigating page landmarks. The available `{hotkey}` placeholder will be replaced for you.
     * Alternatively, you can pass in a custom function to generate the label.
     * @defaultValue 'Notifications ({hotkey})'
     */
    label?: string | ((hotkey: string) => string);
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastViewportProps>, {
    hotkey: () => string[];
    label: string;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToastViewportProps>, {
    hotkey: () => string[];
    label: string;
    as: string;
}>>>, {
    label: string | ((hotkey: string) => string);
    as: import('../Primitive').AsTag | import('vue').Component;
    hotkey: string[];
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
