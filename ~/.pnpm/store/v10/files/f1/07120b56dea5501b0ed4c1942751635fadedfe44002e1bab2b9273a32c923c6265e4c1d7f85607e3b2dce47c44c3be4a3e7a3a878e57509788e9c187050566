import { PrimitiveProps } from '../Primitive';
export type RadioEmits = {
    'update:checked': [value: boolean];
};
export interface RadioProps extends PrimitiveProps {
    id?: string;
    /** The value given as data when submitted with a `name`. */
    value?: string;
    /** When `true`, prevents the user from interacting with the radio item. */
    disabled?: boolean;
    /** When `true`, indicates that the user must check the radio item before the owning form can be submitted. */
    required?: boolean;
    checked?: boolean;
    name?: string;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<RadioProps>, {
    disabled: boolean;
    checked: undefined;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:checked": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<RadioProps>, {
    disabled: boolean;
    checked: undefined;
    as: string;
}>>> & {
    "onUpdate:checked"?: ((value: boolean) => any) | undefined;
}, {
    disabled: boolean;
    as: import('../Primitive').AsTag | import('vue').Component;
    checked: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current checked state */
        checked: boolean | undefined;
    }) => any;
}> & {
    default: (props: {
        /** Current checked state */
        checked: boolean | undefined;
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
