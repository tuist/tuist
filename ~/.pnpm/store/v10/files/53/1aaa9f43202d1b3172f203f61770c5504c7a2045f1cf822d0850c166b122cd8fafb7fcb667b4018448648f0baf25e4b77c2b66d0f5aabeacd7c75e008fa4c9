import { ComputedRef, Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
export type ProgressRootEmits = {
    /** Event handler called when the progress value changes */
    'update:modelValue': [value: string[] | undefined];
    /** Event handler called when the max value changes */
    'update:max': [value: number];
};
export interface ProgressRootProps extends PrimitiveProps {
    /** The progress value. Can be bind as `v-model`. */
    modelValue?: number | null;
    /** The maximum progress value. */
    max?: number;
    /**
     * A function to get the accessible label text representing the current value in a human-readable format.
     *
     *  If not provided, the value label will be read as the numeric value as a percentage of the max value.
     */
    getValueLabel?: (value: number, max: number) => string;
}
interface ProgressRootContext {
    modelValue?: Readonly<Ref<ProgressRootProps['modelValue']>>;
    max: Readonly<Ref<number>>;
    progressState: ComputedRef<ProgressState>;
}
export declare const injectProgressRootContext: <T extends ProgressRootContext | null | undefined = ProgressRootContext>(fallback?: T | undefined) => T extends null ? ProgressRootContext | null : ProgressRootContext, provideProgressRootContext: (contextValue: ProgressRootContext) => ProgressRootContext;
export type ProgressState = 'indeterminate' | 'loading' | 'complete';
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ProgressRootProps>, {
    max: number;
    getValueLabel: (value: number, max: number) => string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (value: string[] | undefined) => void;
    "update:max": (value: number) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ProgressRootProps>, {
    max: number;
    getValueLabel: (value: number, max: number) => string;
}>>> & {
    "onUpdate:modelValue"?: ((value: string[] | undefined) => any) | undefined;
    "onUpdate:max"?: ((value: number) => any) | undefined;
}, {
    max: number;
    getValueLabel: (value: number, max: number) => string;
}, {}>, Readonly<{
    default: (props: {
        /** Current input values */
        modelValue: number | null | undefined;
    }) => any;
}> & {
    default: (props: {
        /** Current input values */
        modelValue: number | null | undefined;
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
