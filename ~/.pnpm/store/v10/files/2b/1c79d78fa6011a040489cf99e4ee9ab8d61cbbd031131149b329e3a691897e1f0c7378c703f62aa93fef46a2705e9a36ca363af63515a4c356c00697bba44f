import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { DataOrientation, Direction } from '../shared/types';
export interface SliderRootProps extends PrimitiveProps {
    name?: string;
    /** The value of the slider when initially rendered. Use when you do not need to control the state of the slider. */
    defaultValue?: number[];
    /** The controlled value of the slider. Can be bind as `v-model`. */
    modelValue?: number[];
    /** When `true`, prevents the user from interacting with the slider. */
    disabled?: boolean;
    /** The orientation of the slider. */
    orientation?: DataOrientation;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** Whether the slider is visually inverted. */
    inverted?: boolean;
    /** The minimum value for the range. */
    min?: number;
    /** The maximum value for the range. */
    max?: number;
    /** The stepping interval. */
    step?: number;
    /** The minimum permitted steps between multiple thumbs. */
    minStepsBetweenThumbs?: number;
}
export type SliderRootEmits = {
    /**
     * Event handler called when the slider value changes
     */
    'update:modelValue': [payload: number[] | undefined];
    /**
     * Event handler called when the value changes at the end of an interaction.
     *
     * Useful when you only need to capture a final value e.g. to update a backend service.
     */
    'valueCommit': [payload: number[]];
};
export interface SliderRootContext {
    orientation: Ref<DataOrientation>;
    disabled: Ref<boolean>;
    min: Ref<number>;
    max: Ref<number>;
    modelValue?: Readonly<Ref<number[] | undefined>>;
    valueIndexToChangeRef: Ref<number>;
    thumbElements: Ref<HTMLElement[]>;
}
export declare const injectSliderRootContext: <T extends SliderRootContext | null | undefined = SliderRootContext>(fallback?: T | undefined) => T extends null ? SliderRootContext | null : SliderRootContext, provideSliderRootContext: (contextValue: SliderRootContext) => SliderRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SliderRootProps>, {
    min: number;
    max: number;
    step: number;
    orientation: string;
    disabled: boolean;
    minStepsBetweenThumbs: number;
    defaultValue: () => number[];
    inverted: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (payload: number[] | undefined) => void;
    valueCommit: (payload: number[]) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SliderRootProps>, {
    min: number;
    max: number;
    step: number;
    orientation: string;
    disabled: boolean;
    minStepsBetweenThumbs: number;
    defaultValue: () => number[];
    inverted: boolean;
}>>> & {
    "onUpdate:modelValue"?: ((payload: number[] | undefined) => any) | undefined;
    onValueCommit?: ((payload: number[]) => any) | undefined;
}, {
    defaultValue: number[];
    disabled: boolean;
    orientation: DataOrientation;
    step: number;
    max: number;
    min: number;
    inverted: boolean;
    minStepsBetweenThumbs: number;
}, {}>, Readonly<{
    default: (props: {
        /** Current slider values */
        modelValue: number[];
    }) => any;
}> & {
    default: (props: {
        /** Current slider values */
        modelValue: number[];
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
