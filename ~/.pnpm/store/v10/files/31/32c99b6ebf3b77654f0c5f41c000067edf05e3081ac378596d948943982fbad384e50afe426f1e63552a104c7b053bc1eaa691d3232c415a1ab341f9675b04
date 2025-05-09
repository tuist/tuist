import { Ref } from 'vue';
export interface Measurable {
    getBoundingClientRect: () => DOMRect;
}
interface PopperRootContext {
    anchor: Ref<Measurable | HTMLElement | undefined>;
    onAnchorChange: (element: Measurable | HTMLElement | undefined) => void;
}
export declare const injectPopperRootContext: <T extends PopperRootContext | null | undefined = PopperRootContext>(fallback?: T | undefined) => T extends null ? PopperRootContext | null : PopperRootContext, providePopperRootContext: (contextValue: PopperRootContext) => PopperRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<{}, {}, {}, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<{}>>, {}, {}>, {
    default?(_: {}): any;
}>;
export default _default;
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
