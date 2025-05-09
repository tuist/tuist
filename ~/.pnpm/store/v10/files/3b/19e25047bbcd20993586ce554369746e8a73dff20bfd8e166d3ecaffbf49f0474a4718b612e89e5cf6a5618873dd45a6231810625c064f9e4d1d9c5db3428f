import { DataOrientation } from '../types';
import { PrimitiveProps } from '../../Primitive';
export interface BaseSeparatorProps extends PrimitiveProps {
    /**
     * Orientation of the component.
     *
     * Either `vertical` or `horizontal`. Defaults to `horizontal`.
     */
    orientation?: DataOrientation;
    /**
     * Whether or not the component is purely decorative. <br>When `true`, accessibility-related attributes
     * are updated so that that the rendered element is removed from the accessibility tree.
     */
    decorative?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<BaseSeparatorProps>, {
    orientation: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<BaseSeparatorProps>, {
    orientation: string;
}>>>, {
    orientation: DataOrientation;
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
