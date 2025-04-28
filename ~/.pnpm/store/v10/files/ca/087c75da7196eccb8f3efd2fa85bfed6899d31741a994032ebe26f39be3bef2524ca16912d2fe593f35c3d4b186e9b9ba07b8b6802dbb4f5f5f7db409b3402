import { Direction, ScrollBodyOption } from '../shared/types';
import { Ref } from 'vue';
interface ConfigProviderContextValue {
    dir?: Ref<Direction>;
    scrollBody?: Ref<boolean | ScrollBodyOption>;
    nonce?: Ref<string | undefined>;
    useId?: () => string;
}
export declare const injectConfigProviderContext: <T extends ConfigProviderContextValue | null | undefined = ConfigProviderContextValue>(fallback?: T | undefined) => T extends null ? ConfigProviderContextValue | null : ConfigProviderContextValue, provideConfigProviderContext: (contextValue: ConfigProviderContextValue) => ConfigProviderContextValue;
export interface ConfigProviderProps {
    /**
     * The global reading direction of your application. This will be inherited by all primitives.
     * @defaultValue 'ltr'
     */
    dir?: Direction;
    /**
     * The global scroll body behavior of your application. This will be inherited by the related primitives.
     * @type boolean | ScrollBodyOption
     */
    scrollBody?: boolean | ScrollBodyOption;
    /**
     * The global `nonce` value of your application. This will be inherited by the related primitives.
     * @type string
     */
    nonce?: string;
    /**
     * The global `useId` injection as a workaround for preventing hydration issue.
     */
    useId?: () => string;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ConfigProviderProps>, {
    dir: string;
    scrollBody: boolean;
    nonce: undefined;
    useId: undefined;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ConfigProviderProps>, {
    dir: string;
    scrollBody: boolean;
    nonce: undefined;
    useId: undefined;
}>>>, {
    dir: Direction;
    scrollBody: boolean | ScrollBodyOption;
    nonce: string;
    useId: () => string;
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
