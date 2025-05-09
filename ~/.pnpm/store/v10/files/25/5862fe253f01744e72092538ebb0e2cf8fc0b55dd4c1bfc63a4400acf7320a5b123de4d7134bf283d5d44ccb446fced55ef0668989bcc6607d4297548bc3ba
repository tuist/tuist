import { Ref } from 'vue';
import { Direction } from './utils';
export interface MenuContext {
    open: Ref<boolean>;
    onOpenChange: (open: boolean) => void;
    content: Ref<HTMLElement | undefined>;
    onContentChange: (content: HTMLElement | undefined) => void;
}
export interface MenuRootContext {
    onClose: () => void;
    dir: Ref<Direction>;
    isUsingKeyboardRef: Ref<boolean>;
    modal: Ref<boolean>;
}
export interface MenuProps {
    /** The controlled open state of the menu. Can be used as `v-model:open`. */
    open?: boolean;
    /**
     * The reading direction of the combobox when applicable.
     *
     * If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode.
     */
    dir?: Direction;
    /**
     * The modality of the dropdown menu.
     *
     * When set to `true`, interaction with outside elements will be disabled and only menu content will be visible to screen readers.
     */
    modal?: boolean;
}
export type MenuEmits = {
    'update:open': [payload: boolean];
};
export declare const injectMenuContext: <T extends MenuContext | null | undefined = MenuContext>(fallback?: T | undefined) => T extends null ? MenuContext | null : MenuContext, provideMenuContext: (contextValue: MenuContext) => MenuContext;
export declare const injectMenuRootContext: <T extends MenuRootContext | null | undefined = MenuRootContext>(fallback?: T | undefined) => T extends null ? MenuRootContext | null : MenuRootContext, provideMenuRootContext: (contextValue: MenuRootContext) => MenuRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuProps>, {
    open: boolean;
    modal: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (payload: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuProps>, {
    open: boolean;
    modal: boolean;
}>>> & {
    "onUpdate:open"?: ((payload: boolean) => any) | undefined;
}, {
    open: boolean;
    modal: boolean;
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
