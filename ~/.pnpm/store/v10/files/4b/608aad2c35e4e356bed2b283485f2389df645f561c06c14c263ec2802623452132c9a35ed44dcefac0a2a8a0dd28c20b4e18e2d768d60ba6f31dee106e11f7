import { ComputedRef, Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Direction } from '../shared/types';
export type PinInputRootEmits = {
    'update:modelValue': [value: string[]];
    'complete': [value: string[]];
};
export interface PinInputRootProps extends PrimitiveProps {
    /** The controlled checked state of the pin input. Can be binded as `v-model`. */
    modelValue?: string[];
    /** The default value of the pin inputs when it is initially rendered. Use when you do not need to control its checked state. */
    defaultValue?: string[];
    /** The placeholder character to use for empty pin-inputs. */
    placeholder?: string;
    /** When `true`, pin inputs will be treated as password. */
    mask?: boolean;
    /** When `true`, mobile devices will autodetect the OTP from messages or clipboard, and enable the autocomplete field. */
    otp?: boolean;
    /** Input type for the inputs. */
    type?: 'text' | 'number';
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** The name of the pin input. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    /** When `true`, prevents the user from interacting with the pin input */
    disabled?: boolean;
    /** When `true`, indicates that the user must check the pin input before the owning form can be submitted. */
    required?: boolean;
    /** Id of the element */
    id?: string;
}
export interface PinInputRootContext {
    modelValue: Ref<string[]>;
    mask: Ref<boolean>;
    otp: Ref<boolean>;
    placeholder: Ref<string>;
    type: Ref<PinInputRootProps['type']>;
    dir: Ref<Direction>;
    disabled: Ref<boolean>;
    isCompleted: ComputedRef<boolean>;
    inputElements?: Ref<Set<HTMLInputElement>>;
    onInputElementChange: (el: HTMLInputElement) => void;
}
export declare const injectPinInputRootContext: <T extends PinInputRootContext | null | undefined = PinInputRootContext>(fallback?: T | undefined) => T extends null ? PinInputRootContext | null : PinInputRootContext, providePinInputRootContext: (contextValue: PinInputRootContext) => PinInputRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<PinInputRootProps>, {
    placeholder: string;
    type: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (value: string[]) => void;
    complete: (value: string[]) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<PinInputRootProps>, {
    placeholder: string;
    type: string;
}>>> & {
    "onUpdate:modelValue"?: ((value: string[]) => any) | undefined;
    onComplete?: ((value: string[]) => any) | undefined;
}, {
    type: "number" | "text";
    placeholder: string;
}, {}>, Readonly<{
    default: (props: {
        /** Current input values */
        modelValue: string[];
    }) => any;
}> & {
    default: (props: {
        /** Current input values */
        modelValue: string[];
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
