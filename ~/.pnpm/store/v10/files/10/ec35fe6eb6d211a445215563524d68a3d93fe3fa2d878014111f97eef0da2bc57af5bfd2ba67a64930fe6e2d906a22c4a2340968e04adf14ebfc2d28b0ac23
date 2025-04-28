import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
export interface ScrollAreaScrollbarProps extends PrimitiveProps {
    /** The orientation of the scrollbar */
    orientation?: 'vertical' | 'horizontal';
    /**
     * Used to force mounting when more control is needed. Useful when
     * controlling animation with Vue animation libraries.
     */
    forceMount?: boolean;
}
export interface ScrollAreaScollbarContext {
    as: Ref<PrimitiveProps['as']>;
    orientation: Ref<'vertical' | 'horizontal'>;
    forceMount?: Ref<boolean>;
    isHorizontal: Ref<boolean>;
    asChild: Ref<boolean>;
}
export declare const injectScrollAreaScrollbarContext: <T extends ScrollAreaScollbarContext | null | undefined = ScrollAreaScollbarContext>(fallback?: T | undefined) => T extends null ? ScrollAreaScollbarContext | null : ScrollAreaScollbarContext, provideScrollAreaScrollbarContext: (contextValue: ScrollAreaScollbarContext) => ScrollAreaScollbarContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ScrollAreaScrollbarProps>, {
    orientation: string;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ScrollAreaScrollbarProps>, {
    orientation: string;
    as: string;
}>>>, {
    as: import('../Primitive').AsTag | import('vue').Component;
    orientation: "vertical" | "horizontal";
}, {}>, {
    default?(_: {}): any;
    default?(_: {}): any;
    default?(_: {}): any;
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
