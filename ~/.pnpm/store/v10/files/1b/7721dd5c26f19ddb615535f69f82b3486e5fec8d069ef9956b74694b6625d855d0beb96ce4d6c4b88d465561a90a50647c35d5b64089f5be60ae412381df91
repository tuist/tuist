import { PrimitiveProps } from '../Primitive';
export type SliderImplEmits = {
    slideStart: [event: PointerEvent];
    slideMove: [event: PointerEvent];
    slideEnd: [event: PointerEvent];
    homeKeyDown: [event: KeyboardEvent];
    endKeyDown: [event: KeyboardEvent];
    stepKeyDown: [event: KeyboardEvent];
};
export interface SliderImplProps extends PrimitiveProps {
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SliderImplProps>, {
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    slideStart: (event: PointerEvent) => void;
    slideMove: (event: PointerEvent) => void;
    slideEnd: (event: PointerEvent) => void;
    homeKeyDown: (event: KeyboardEvent) => void;
    endKeyDown: (event: KeyboardEvent) => void;
    stepKeyDown: (event: KeyboardEvent) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SliderImplProps>, {
    as: string;
}>>> & {
    onSlideStart?: ((event: PointerEvent) => any) | undefined;
    onSlideMove?: ((event: PointerEvent) => any) | undefined;
    onSlideEnd?: ((event: PointerEvent) => any) | undefined;
    onHomeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onEndKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onStepKeyDown?: ((event: KeyboardEvent) => any) | undefined;
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
