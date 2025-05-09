import { Ref } from 'vue';
import { Direction } from '../shared/types';
import { MenuEmits, MenuProps } from '../Menu';
type ContextMenuRootContext = {
    open: Ref<boolean>;
    onOpenChange: (open: boolean) => void;
    modal: Ref<boolean>;
    dir: Ref<Direction>;
};
export interface ContextMenuRootProps extends Omit<MenuProps, 'open'> {
}
export type ContextMenuRootEmits = MenuEmits;
export declare const injectContextMenuRootContext: <T extends ContextMenuRootContext | null | undefined = ContextMenuRootContext>(fallback?: T | undefined) => T extends null ? ContextMenuRootContext | null : ContextMenuRootContext, provideContextMenuRootContext: (contextValue: ContextMenuRootContext) => ContextMenuRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ContextMenuRootProps>, {
    modal: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:open": (payload: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ContextMenuRootProps>, {
    modal: boolean;
}>>> & {
    "onUpdate:open"?: ((payload: boolean) => any) | undefined;
}, {
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
