import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { CheckedState } from './utils';
interface MenuItemIndicatorContext {
    checked: Ref<CheckedState>;
}
export interface MenuItemIndicatorProps extends PrimitiveProps {
    /**
     * Used to force mounting when more control is needed. Useful when
     * controlling animation with Vue animation libraries.
     */
    forceMount?: boolean;
}
export declare const injectMenuItemIndicatorContext: <T extends MenuItemIndicatorContext | null | undefined = MenuItemIndicatorContext>(fallback?: T | undefined) => T extends null ? MenuItemIndicatorContext | null : MenuItemIndicatorContext, provideMenuItemIndicatorContext: (contextValue: MenuItemIndicatorContext) => MenuItemIndicatorContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuItemIndicatorProps>, {
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuItemIndicatorProps>, {
    as: string;
}>>>, {
    as: import('../Primitive').AsTag | import('vue').Component;
}, {}>, {
    default?(_: {}): any;
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
