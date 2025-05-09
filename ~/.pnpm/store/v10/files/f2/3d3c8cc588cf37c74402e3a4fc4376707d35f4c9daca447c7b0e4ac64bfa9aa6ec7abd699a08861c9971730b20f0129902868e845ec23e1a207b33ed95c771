import { PrimitiveProps } from '../Primitive';
export type NavigationMenuLinkEmits = {
    /**
     * Event handler called when the user selects a link (via mouse or keyboard).
     *
     * Calling `event.preventDefault` in this handler will prevent the navigation menu from closing when selecting that link.
     */
    select: [payload: CustomEvent<{
        originalEvent: Event;
    }>];
};
export interface NavigationMenuLinkProps extends PrimitiveProps {
    /** Used to identify the link as the currently active page. */
    active?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuLinkProps>, {
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    select: (payload: CustomEvent<{
        originalEvent: Event;
    }>) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuLinkProps>, {
    as: string;
}>>> & {
    onSelect?: ((payload: CustomEvent<{
        originalEvent: Event;
    }>) => any) | undefined;
}, {
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
