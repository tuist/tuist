import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { DataOrientation, Direction } from '../shared/types';
export interface ToolbarRootProps extends PrimitiveProps {
    /** The orientation of the toolbar */
    orientation?: DataOrientation;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** When `true`, keyboard navigation will loop from last tab to first, and vice versa. */
    loop?: boolean;
}
export interface ToolbarRootContext {
    orientation: Ref<DataOrientation>;
    dir: Ref<Direction>;
}
export declare const injectToolbarRootContext: <T extends ToolbarRootContext | null | undefined = ToolbarRootContext>(fallback?: T | undefined) => T extends null ? ToolbarRootContext | null : ToolbarRootContext, provideToolbarRootContext: (contextValue: ToolbarRootContext) => ToolbarRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToolbarRootProps>, {
    orientation: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToolbarRootProps>, {
    orientation: string;
}>>>, {
    orientation: DataOrientation;
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
