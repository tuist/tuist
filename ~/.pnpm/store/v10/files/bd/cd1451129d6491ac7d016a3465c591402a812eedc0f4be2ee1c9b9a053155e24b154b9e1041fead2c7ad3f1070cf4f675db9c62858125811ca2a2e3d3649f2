import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { DataOrientation, Direction } from '../shared/types';
export interface RadioGroupRootProps extends PrimitiveProps {
    /** The controlled value of the radio item to check. Can be binded as `v-model`. */
    modelValue?: string;
    /**
     * The value of the radio item that should be checked when initially rendered.
     *
     * Use when you do not need to control the state of the radio items.
     */
    defaultValue?: string;
    /** When `true`, prevents the user from interacting with radio items. */
    disabled?: boolean;
    /** The name of the group. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    /** When `true`, indicates that the user must check a radio item before the owning form can be submitted. */
    required?: boolean;
    /** The orientation of the component. */
    orientation?: DataOrientation;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** When `true`, keyboard navigation will loop from last item to first, and vice versa. */
    loop?: boolean;
}
export type RadioGroupRootEmits = {
    /** Event handler called when the radio group value changes */
    'update:modelValue': [payload: string];
};
interface RadioGroupRootContext {
    modelValue?: Readonly<Ref<string | undefined>>;
    changeModelValue: (value?: string) => void;
    disabled: Ref<boolean>;
    loop: Ref<boolean>;
    orientation: Ref<DataOrientation | undefined>;
    name?: string;
    required: Ref<boolean>;
}
export declare const injectRadioGroupRootContext: <T extends RadioGroupRootContext | null | undefined = RadioGroupRootContext>(fallback?: T | undefined) => T extends null ? RadioGroupRootContext | null : RadioGroupRootContext, provideRadioGroupRootContext: (contextValue: RadioGroupRootContext) => RadioGroupRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<RadioGroupRootProps>, {
    disabled: boolean;
    required: boolean;
    orientation: undefined;
    loop: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (payload: string) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<RadioGroupRootProps>, {
    disabled: boolean;
    required: boolean;
    orientation: undefined;
    loop: boolean;
}>>> & {
    "onUpdate:modelValue"?: ((payload: string) => any) | undefined;
}, {
    disabled: boolean;
    loop: boolean;
    required: boolean;
    orientation: DataOrientation;
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
