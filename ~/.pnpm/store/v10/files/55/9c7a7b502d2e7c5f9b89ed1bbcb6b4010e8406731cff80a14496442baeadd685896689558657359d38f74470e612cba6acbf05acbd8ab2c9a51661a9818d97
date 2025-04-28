import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
interface SelectItemAlignedPositionContext {
    contentWrapper?: Ref<HTMLElement | undefined>;
    shouldExpandOnScrollRef?: Ref<boolean>;
    onScrollButtonChange: (node: HTMLElement | undefined) => void;
}
export interface SelectItemAlignedPositionProps extends PrimitiveProps {
}
export declare const injectSelectItemAlignedPositionContext: <T extends SelectItemAlignedPositionContext | null | undefined = SelectItemAlignedPositionContext>(fallback?: T | undefined) => T extends null ? SelectItemAlignedPositionContext | null : SelectItemAlignedPositionContext, provideSelectItemAlignedPositionContext: (contextValue: SelectItemAlignedPositionContext) => SelectItemAlignedPositionContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<SelectItemAlignedPositionProps>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    placed: () => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<SelectItemAlignedPositionProps>>> & {
    onPlaced?: (() => any) | undefined;
}, {}, {}>, {
    default?(_: {}): any;
}>;
export default _default;
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
