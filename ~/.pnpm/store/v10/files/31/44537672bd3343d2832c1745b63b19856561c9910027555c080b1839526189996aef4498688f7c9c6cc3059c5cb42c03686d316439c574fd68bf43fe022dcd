import { CheckedState } from './utils';
import { MenuItemEmits, MenuItemProps } from './MenuItem';
export type MenuCheckboxItemEmits = MenuItemEmits & {
    /** Event handler called when the checked state changes. */
    'update:checked': [payload: boolean];
};
export interface MenuCheckboxItemProps extends MenuItemProps {
    /** The controlled checked state of the item. Can be used as `v-model:checked`. */
    checked?: CheckedState;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuCheckboxItemProps>, {
    checked: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    select: (event: Event) => void;
    "update:checked": (payload: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuCheckboxItemProps>, {
    checked: boolean;
}>>> & {
    onSelect?: ((event: Event) => any) | undefined;
    "onUpdate:checked"?: ((payload: boolean) => any) | undefined;
}, {
    checked: CheckedState;
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
