import { Ref } from 'vue';
import { Sizes } from './types';
export interface ScrollAreaScrollbarVisibleContext {
    sizes: Ref<Sizes>;
    hasThumb: Ref<boolean>;
    handleWheelScroll: (event: WheelEvent, payload: number) => void;
    handleThumbDown: (event: MouseEvent, payload: {
        x: number;
        y: number;
    }) => void;
    handleThumbUp: (event: MouseEvent) => void;
    handleSizeChange: (payload: Sizes) => void;
    onThumbPositionChange: () => void;
    onDragScroll: (payload: number) => void;
    onThumbChange: (element: HTMLElement) => void;
}
export declare const injectScrollAreaScrollbarVisibleContext: <T extends ScrollAreaScrollbarVisibleContext | null | undefined = ScrollAreaScrollbarVisibleContext>(fallback?: T | undefined) => T extends null ? ScrollAreaScrollbarVisibleContext | null : ScrollAreaScrollbarVisibleContext, provideScrollAreaScrollbarVisibleContext: (contextValue: ScrollAreaScrollbarVisibleContext) => ScrollAreaScrollbarVisibleContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<{}, {}, {}, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<{}>>, {}, {}>, {
    default?(_: {}): any;
    default?(_: {}): any;
}>;
export default _default;
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
