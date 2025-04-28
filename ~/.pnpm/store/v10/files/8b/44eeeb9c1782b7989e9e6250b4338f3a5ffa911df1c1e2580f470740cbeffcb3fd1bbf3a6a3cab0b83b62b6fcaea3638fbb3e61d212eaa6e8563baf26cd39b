import { Orientation } from './utils';
import { PrimitiveProps } from '../Primitive';
export type NavigationMenuSubEmits = {
    /** Event handler called when the value changes. */
    'update:modelValue': [value: string];
};
export interface NavigationMenuSubProps extends PrimitiveProps {
    /** The controlled value of the sub menu item to activate. Can be used as `v-model`. */
    modelValue?: string;
    /**
     * The value of the menu item that should be active when initially rendered.
     *
     * Use when you do not need to control the value state.
     */
    defaultValue?: string;
    /** The orientation of the menu. */
    orientation?: Orientation;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuSubProps>, {
    orientation: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (value: string) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuSubProps>, {
    orientation: string;
}>>> & {
    "onUpdate:modelValue"?: ((value: string) => any) | undefined;
}, {
    orientation: Orientation;
}, {}>, Readonly<{
    default: (props: {
        /** Current input values */
        modelValue: string;
    }) => any;
}> & {
    default: (props: {
        /** Current input values */
        modelValue: string;
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
