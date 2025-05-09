import { MenuContentEmits, MenuContentProps } from '../Menu';
export type MenubarContentEmits = MenuContentEmits;
export interface MenubarContentProps extends MenuContentProps {
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenubarContentProps>, {
    align: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent) => void;
    focusOutside: (event: import('../DismissableLayer').FocusOutsideEvent) => void;
    interactOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => void;
    closeAutoFocus: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenubarContentProps>, {
    align: string;
}>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent) => any) | undefined;
    onFocusOutside?: ((event: import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onInteractOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onCloseAutoFocus?: ((event: Event) => any) | undefined;
}, {
    align: "center" | "end" | "start";
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
