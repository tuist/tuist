import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { ImageLoadingStatus } from './utils';
export interface AvatarRootProps extends PrimitiveProps {
}
export type AvatarRootContext = {
    imageLoadingStatus: Ref<ImageLoadingStatus>;
};
export declare const injectAvatarRootContext: <T extends AvatarRootContext | null | undefined = AvatarRootContext>(fallback?: T | undefined) => T extends null ? AvatarRootContext | null : AvatarRootContext, provideAvatarRootContext: (contextValue: AvatarRootContext) => AvatarRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<AvatarRootProps>, {
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<AvatarRootProps>, {
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
