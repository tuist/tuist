import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
export interface SwitchRootProps extends PrimitiveProps {
    /** The state of the switch when it is initially rendered. Use when you do not need to control its state. */
    defaultChecked?: boolean;
    /** The controlled state of the switch. Can be bind as `v-model:checked`. */
    checked?: boolean;
    /** When `true`, prevents the user from interacting with the switch. */
    disabled?: boolean;
    /** When `true`, indicates that the user must check the switch before the owning form can be submitted. */
    required?: boolean;
    /** The name of the switch. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    id?: string;
    /** The value given as data when submitted with a `name`. */
    value?: string;
}
export type SwitchRootEmits = {
    /** Event handler called when the checked state of the switch changes. */
    'update:checked': [payload: boolean];
};
export interface SwitchRootContext {
    checked?: Ref<boolean>;
    toggleCheck: () => void;
    disabled: Ref<boolean>;
}
export declare const injectSwitchRootContext: <T extends SwitchRootContext | null | undefined = SwitchRootContext>(fallback?: T | undefined) => T extends null ? SwitchRootContext | null : SwitchRootContext, provideSwitchRootContext: (contextValue: SwitchRootContext) => SwitchRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SwitchRootProps>, {
    as: string;
    checked: undefined;
    value: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:checked": (payload: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SwitchRootProps>, {
    as: string;
    checked: undefined;
    value: string;
}>>> & {
    "onUpdate:checked"?: ((payload: boolean) => any) | undefined;
}, {
    value: string;
    as: import('../Primitive').AsTag | import('vue').Component;
    checked: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current checked state */
        checked: boolean;
    }) => any;
}> & {
    default: (props: {
        /** Current checked state */
        checked: boolean;
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
