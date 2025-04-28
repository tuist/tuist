import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
export declare const injectStepperItemContext: <T extends StepperItemContext | null | undefined = StepperItemContext>(fallback?: T | undefined) => T extends null ? StepperItemContext | null : StepperItemContext, provideStepperItemContext: (contextValue: StepperItemContext) => StepperItemContext;
export type StepperState = 'completed' | 'active' | 'inactive';
export interface StepperItemContext {
    titleId: string;
    descriptionId: string;
    step: Ref<number>;
    state: Ref<StepperState>;
    disabled: Ref<boolean>;
    isFocusable: Ref<boolean>;
}
export interface StepperItemProps extends PrimitiveProps {
    /** A unique value that associates the stepper item with an index */
    step: number;
    /** When `true`, prevents the user from interacting with the step. */
    disabled?: boolean;
    /** Shows whether the step is completed. */
    completed?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<StepperItemProps>, {
    completed: boolean;
    disabled: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<StepperItemProps>, {
    completed: boolean;
    disabled: boolean;
}>>>, {
    disabled: boolean;
    completed: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** The current state of the stepper item */
        state: StepperState;
    }) => any;
}> & {
    default: (props: {
        /** The current state of the stepper item */
        state: StepperState;
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
