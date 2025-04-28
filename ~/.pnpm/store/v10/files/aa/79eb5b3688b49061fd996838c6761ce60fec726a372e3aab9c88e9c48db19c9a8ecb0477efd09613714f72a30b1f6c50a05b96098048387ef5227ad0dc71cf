import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
export interface NavigationMenuItemProps extends PrimitiveProps {
    /**
     * A unique value that associates the item with an active value when the navigation menu is controlled.
     *
     *  This prop is managed automatically when uncontrolled.
     */
    value?: string;
}
export type NavigationMenuItemContext = {
    value: string;
    contentId: string;
    triggerRef: Ref<HTMLElement | undefined>;
    focusProxyRef: Ref<HTMLElement | undefined>;
    wasEscapeCloseRef: Ref<boolean>;
    onEntryKeyDown: () => void;
    onFocusProxyEnter: (side: 'start' | 'end') => void;
    onContentFocusOutside: () => void;
    onRootContentClose: () => void;
};
export declare const injectNavigationMenuItemContext: <T extends NavigationMenuItemContext | null | undefined = NavigationMenuItemContext>(fallback?: T | undefined) => T extends null ? NavigationMenuItemContext | null : NavigationMenuItemContext, provideNavigationMenuItemContext: (contextValue: NavigationMenuItemContext) => NavigationMenuItemContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuItemProps>, {
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuItemProps>, {
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
