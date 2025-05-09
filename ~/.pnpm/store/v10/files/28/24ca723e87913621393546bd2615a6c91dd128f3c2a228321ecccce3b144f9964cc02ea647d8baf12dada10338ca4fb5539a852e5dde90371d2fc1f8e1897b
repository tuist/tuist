import { PrimitiveProps } from '../Primitive';
export type FocusScopeEmits = {
    /**
     * Event handler called when auto-focusing on mount.
     * Can be prevented.
     */
    mountAutoFocus: [event: Event];
    /**
     * Event handler called when auto-focusing on unmount.
     * Can be prevented.
     */
    unmountAutoFocus: [event: Event];
};
export interface FocusScopeProps extends PrimitiveProps {
    /**
     * When `true`, tabbing from last item will focus first tabbable
     * and shift+tab from first item will focus last tababble.
     * @defaultValue false
     */
    loop?: boolean;
    /**
     * When `true`, focus cannot escape the focus scope via keyboard,
     * pointer, or a programmatic focus.
     * @defaultValue false
     */
    trapped?: boolean;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<FocusScopeProps>, {
    loop: boolean;
    trapped: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    mountAutoFocus: (event: Event) => void;
    unmountAutoFocus: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<FocusScopeProps>, {
    loop: boolean;
    trapped: boolean;
}>>> & {
    onMountAutoFocus?: ((event: Event) => any) | undefined;
    onUnmountAutoFocus?: ((event: Event) => any) | undefined;
}, {
    loop: boolean;
    trapped: boolean;
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
