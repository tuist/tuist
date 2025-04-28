import { PrimitiveProps } from '..';
export interface ListboxFilterProps extends PrimitiveProps {
    /** The controlled value of the filter. Can be binded with with v-model. */
    modelValue?: string;
    /** Focus on element when mounted. */
    autoFocus?: boolean;
}
export type ListboxFilterEmits = {
    'update:modelValue': [string];
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ListboxFilterProps>, {
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (args_0: string) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ListboxFilterProps>, {
    as: string;
}>>> & {
    "onUpdate:modelValue"?: ((args_0: string) => any) | undefined;
}, {
    as: import('../Primitive').AsTag | import('vue').Component;
}, {}>, Readonly<{
    default: (props: {
        /** Current input values */
        modelValue: string | undefined;
    }) => any;
}> & {
    default: (props: {
        /** Current input values */
        modelValue: string | undefined;
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
