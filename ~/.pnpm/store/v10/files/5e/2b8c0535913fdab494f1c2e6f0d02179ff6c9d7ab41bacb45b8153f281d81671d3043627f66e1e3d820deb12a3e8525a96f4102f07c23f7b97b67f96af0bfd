import { PrimitiveProps } from '../Primitive';
export type ToggleEmits = {
    /** Event handler called when the pressed state of the toggle changes. */
    'update:pressed': [value: boolean];
};
export type DataState = 'on' | 'off';
export interface ToggleProps extends PrimitiveProps {
    /**
     * The pressed state of the toggle when it is initially rendered. Use when you do not need to control its open state.
     */
    defaultValue?: boolean;
    /**
     * The controlled pressed state of the toggle. Can be bind as `v-model`.
     */
    pressed?: boolean;
    /**
     * When `true`, prevents the user from interacting with the toggle.
     */
    disabled?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToggleProps>, {
    pressed: undefined;
    disabled: boolean;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:pressed": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToggleProps>, {
    pressed: undefined;
    disabled: boolean;
    as: string;
}>>> & {
    "onUpdate:pressed"?: ((value: boolean) => any) | undefined;
}, {
    disabled: boolean;
    as: import('../Primitive').AsTag | import('vue').Component;
    pressed: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current pressed state */
        pressed: boolean;
    }) => any;
}> & {
    default: (props: {
        /** Current pressed state */
        pressed: boolean;
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
