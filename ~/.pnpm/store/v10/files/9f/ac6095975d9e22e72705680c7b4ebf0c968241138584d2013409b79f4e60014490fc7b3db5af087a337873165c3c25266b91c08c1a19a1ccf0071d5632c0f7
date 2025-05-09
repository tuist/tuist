import { PrimitiveProps } from '../Primitive';
export interface AspectRatioProps extends PrimitiveProps {
    /**
     * The desired ratio. Eg: 16/9
     * @defaultValue 1
     */
    ratio?: number;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<AspectRatioProps>, {
    ratio: number;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<AspectRatioProps>, {
    ratio: number;
}>>>, {
    ratio: number;
}, {}>, Readonly<{
    default: (props: {
        /** Current aspect ratio (in %) */
        aspect: number;
    }) => any;
}> & {
    default: (props: {
        /** Current aspect ratio (in %) */
        aspect: number;
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
