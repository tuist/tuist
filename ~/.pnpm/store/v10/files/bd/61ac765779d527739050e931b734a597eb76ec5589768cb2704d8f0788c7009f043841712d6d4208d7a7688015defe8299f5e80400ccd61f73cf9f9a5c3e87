import { Ref } from 'vue';
import { MenuContext } from './MenuRoot';
export interface MenuSubContext {
    contentId: string;
    triggerId: string;
    trigger: Ref<HTMLElement | undefined>;
    onTriggerChange: (trigger: HTMLElement | undefined) => void;
    parentMenuContext?: MenuContext;
}
export declare const injectMenuSubContext: <T extends MenuSubContext | null | undefined = MenuSubContext>(fallback?: T | undefined) => T extends null ? MenuSubContext | null : MenuSubContext, provideMenuSubContext: (contextValue: MenuSubContext) => MenuSubContext;
export interface MenuSubProps {
    /** The controlled open state of the menu. Can be used as `v-model:open`. */
    open?: boolean;
}
export type MenuSubEmits = {
    /** Event handler called when the open state of the submenu changes. */
    'update:open': [payload: boolean];
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuSubProps>, {
    open: undefined;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (payload: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuSubProps>, {
    open: undefined;
}>>> & {
    "onUpdate:open"?: ((payload: boolean) => any) | undefined;
}, {
    open: boolean;
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
