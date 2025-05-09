import { Ref } from 'vue';
export interface MenubarMenuProps {
    /**
     * A unique value that associates the item with an active value when the navigation menu is controlled.
     *
     * This prop is managed automatically when uncontrolled.
     */
    value?: string;
}
type MenubarMenuContext = {
    value: string;
    triggerId: string;
    triggerElement: Ref<HTMLElement | undefined>;
    contentId: string;
    wasKeyboardTriggerOpenRef: Ref<boolean>;
};
export declare const injectMenubarMenuContext: <T extends MenubarMenuContext | null | undefined = MenubarMenuContext>(fallback?: T | undefined) => T extends null ? MenubarMenuContext | null : MenubarMenuContext, provideMenubarMenuContext: (contextValue: MenubarMenuContext) => MenubarMenuContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<MenubarMenuProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<MenubarMenuProps>>>, {}, {}>, {
    default?(_: {}): any;
}>;
export default _default;
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
