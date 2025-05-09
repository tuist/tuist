import { Ref } from 'vue';
import { MenuGroupProps } from './MenuGroup';
interface MenuRadioGroupContext {
    modelValue: Ref<string>;
    onValueChange: (payload: string) => void;
}
export interface MenuRadioGroupProps extends MenuGroupProps {
    /** The value of the selected item in the group. */
    modelValue?: string;
}
export type MenuRadioGroupEmits = {
    /** Event handler called when the value changes. */
    'update:modelValue': [payload: string];
};
export declare const injectMenuRadioGroupContext: <T extends MenuRadioGroupContext | null | undefined = MenuRadioGroupContext>(fallback?: T | undefined) => T extends null ? MenuRadioGroupContext | null : MenuRadioGroupContext, provideMenuRadioGroupContext: (contextValue: MenuRadioGroupContext) => MenuRadioGroupContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuRadioGroupProps>, {
    modelValue: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (payload: string) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuRadioGroupProps>, {
    modelValue: string;
}>>> & {
    "onUpdate:modelValue"?: ((payload: string) => any) | undefined;
}, {
    modelValue: string;
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
