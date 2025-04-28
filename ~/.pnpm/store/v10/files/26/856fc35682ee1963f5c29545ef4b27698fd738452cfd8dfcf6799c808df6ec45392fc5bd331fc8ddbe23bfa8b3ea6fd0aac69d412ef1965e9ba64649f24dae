import { Ref } from 'vue';
import { Direction } from '../shared/types';
import { MenuEmits, MenuProps } from '../Menu';
export interface DropdownMenuRootProps extends MenuProps {
    /** The open state of the dropdown menu when it is initially rendered. Use when you do not need to control its open state. */
    defaultOpen?: boolean;
}
export type DropdownMenuRootEmits = MenuEmits;
export interface DropdownMenuRootContext {
    open: Readonly<Ref<boolean>>;
    onOpenChange: (open: boolean) => void;
    onOpenToggle: () => void;
    triggerId: string;
    triggerElement: Ref<HTMLElement | undefined>;
    contentId: string;
    modal: Ref<boolean>;
    dir: Ref<Direction>;
}
export declare const injectDropdownMenuRootContext: <T extends DropdownMenuRootContext | null | undefined = DropdownMenuRootContext>(fallback?: T | undefined) => T extends null ? DropdownMenuRootContext | null : DropdownMenuRootContext, provideDropdownMenuRootContext: (contextValue: DropdownMenuRootContext) => DropdownMenuRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<DropdownMenuRootProps>, {
    modal: boolean;
    open: undefined;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (payload: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<DropdownMenuRootProps>, {
    modal: boolean;
    open: undefined;
}>>> & {
    "onUpdate:open"?: ((payload: boolean) => any) | undefined;
}, {
    open: boolean;
    modal: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current open state */
        open: boolean;
    }) => any;
}> & {
    default: (props: {
        /** Current open state */
        open: boolean;
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
