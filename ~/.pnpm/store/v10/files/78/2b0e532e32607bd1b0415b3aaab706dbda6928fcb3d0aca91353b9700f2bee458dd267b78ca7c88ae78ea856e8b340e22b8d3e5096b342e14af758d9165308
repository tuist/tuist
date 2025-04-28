import { PrimitiveProps } from '../Primitive';
import { Ref } from 'vue';
import { CheckedState } from './utils';
export interface CheckboxRootProps extends PrimitiveProps {
    /** The checked state of the checkbox when it is initially rendered. Use when you do not need to control its checked state. */
    defaultChecked?: boolean;
    /** The controlled checked state of the checkbox. Can be binded with v-model. */
    checked?: boolean | 'indeterminate';
    /** When `true`, prevents the user from interacting with the checkbox */
    disabled?: boolean;
    /** When `true`, indicates that the user must check the checkbox before the owning form can be submitted. */
    required?: boolean;
    /** The name of the checkbox. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    /**
     * The value given as data when submitted with a `name`.
     *  @defaultValue "on"
     */
    value?: string;
    /** Id of the element */
    id?: string;
}
export type CheckboxRootEmits = {
    /** Event handler called when the checked state of the checkbox changes. */
    'update:checked': [value: boolean];
};
interface CheckboxRootContext {
    disabled: Ref<boolean>;
    state: Ref<CheckedState>;
}
export declare const injectCheckboxRootContext: <T extends CheckboxRootContext | null | undefined = CheckboxRootContext>(fallback?: T | undefined) => T extends null ? CheckboxRootContext | null : CheckboxRootContext, provideCheckboxRootContext: (contextValue: CheckboxRootContext) => CheckboxRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<CheckboxRootProps>, {
    checked: undefined;
    value: string;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:checked": (value: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<CheckboxRootProps>, {
    checked: undefined;
    value: string;
    as: string;
}>>> & {
    "onUpdate:checked"?: ((value: boolean) => any) | undefined;
}, {
    value: string;
    as: import('../Primitive').AsTag | import('vue').Component;
    checked: boolean | "indeterminate";
}, {}>, Readonly<{
    default: (props: {
        /** Current checked state */
        checked: CheckedState;
    }) => any;
}> & {
    default: (props: {
        /** Current checked state */
        checked: CheckedState;
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
