import { PrimitiveProps } from '../Primitive';
import { HTMLAttributes, Ref } from 'vue';
export interface NumberFieldRootProps extends PrimitiveProps {
    defaultValue?: number;
    modelValue?: number;
    /** The smallest value allowed for the input. */
    min?: number;
    /** The largest value allowed for the input. */
    max?: number;
    /** The amount that the input value changes with each increment or decrement "tick". */
    step?: number;
    /** Formatting options for the value displayed in the number field. This also affects what characters are allowed to be typed by the user. */
    formatOptions?: Intl.NumberFormatOptions;
    /** The locale to use for formatting dates */
    locale?: string;
    /** When `true`, prevents the user from interacting with the Number Field. */
    disabled?: boolean;
    /** When `true`, indicates that the user must set the value before the owning form can be submitted. */
    required?: boolean;
    /** The name of the number field. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    /** Id of the element */
    id?: string;
}
export type NumberFieldRootEmits = {
    'update:modelValue': [val: number];
};
interface NumberFieldRootContext {
    modelValue: Ref<number>;
    handleIncrease: (multiplier?: number) => void;
    handleDecrease: (multiplier?: number) => void;
    handleMinMaxValue: (type: 'min' | 'max') => void;
    inputEl: Ref<HTMLInputElement | undefined>;
    onInputElement: (el: HTMLInputElement) => void;
    inputMode: Ref<HTMLAttributes['inputmode']>;
    textValue: Ref<string>;
    validate: (val: string) => boolean;
    applyInputValue: (val: string) => void;
    disabled: Ref<boolean>;
    max: Ref<number | undefined>;
    min: Ref<number | undefined>;
    isDecreaseDisabled: Ref<boolean>;
    isIncreaseDisabled: Ref<boolean>;
    id: Ref<string | undefined>;
}
export declare const injectNumberFieldRootContext: <T extends NumberFieldRootContext | null | undefined = NumberFieldRootContext>(fallback?: T | undefined) => T extends null ? NumberFieldRootContext | null : NumberFieldRootContext, provideNumberFieldRootContext: (contextValue: NumberFieldRootContext) => NumberFieldRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<NumberFieldRootProps>, {
    as: string;
    defaultValue: undefined;
    locale: string;
    step: number;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (val: number) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<NumberFieldRootProps>, {
    as: string;
    defaultValue: undefined;
    locale: string;
    step: number;
}>>> & {
    "onUpdate:modelValue"?: ((val: number) => any) | undefined;
}, {
    defaultValue: number;
    locale: string;
    as: import('../Primitive').AsTag | import('vue').Component;
    step: number;
}, {}>, {
    default?(_: {
        modelValue: number;
        textValue: string;
    }): any;
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
