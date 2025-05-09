import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Direction, ScrollType } from './types';
export interface ScrollAreaRootContext {
    type: Ref<ScrollType>;
    dir: Ref<Direction>;
    scrollHideDelay: Ref<number>;
    scrollArea: Ref<HTMLElement | undefined>;
    viewport: Ref<HTMLElement | undefined>;
    onViewportChange: (viewport: HTMLElement | null) => void;
    content: Ref<HTMLElement | undefined>;
    onContentChange: (content: HTMLElement) => void;
    scrollbarX: Ref<HTMLElement | undefined>;
    onScrollbarXChange: (scrollbar: HTMLElement | null) => void;
    scrollbarXEnabled: Ref<boolean>;
    onScrollbarXEnabledChange: (rendered: boolean) => void;
    scrollbarY: Ref<HTMLElement | undefined>;
    onScrollbarYChange: (scrollbar: HTMLElement | null) => void;
    scrollbarYEnabled: Ref<boolean>;
    onScrollbarYEnabledChange: (rendered: boolean) => void;
    onCornerWidthChange: (width: number) => void;
    onCornerHeightChange: (height: number) => void;
}
export declare const injectScrollAreaRootContext: <T extends ScrollAreaRootContext | null | undefined = ScrollAreaRootContext>(fallback?: T | undefined) => T extends null ? ScrollAreaRootContext | null : ScrollAreaRootContext, provideScrollAreaRootContext: (contextValue: ScrollAreaRootContext) => ScrollAreaRootContext;
export interface ScrollAreaRootProps extends PrimitiveProps {
    /**
     * Describes the nature of scrollbar visibility, similar to how the scrollbar preferences in MacOS control visibility of native scrollbars.
     *
     * `auto` - means that scrollbars are visible when content is overflowing on the corresponding orientation. <br>
     * `always` - means that scrollbars are always visible regardless of whether the content is overflowing.<br>
     * `scroll` - means that scrollbars are visible when the user is scrolling along its corresponding orientation.<br>
     * `hover` - when the user is scrolling along its corresponding orientation and when the user is hovering over the scroll area.
     */
    type?: ScrollType;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** If type is set to either `scroll` or `hover`, this prop determines the length of time, in milliseconds, <br> before the scrollbars are hidden after the user stops interacting with scrollbars. */
    scrollHideDelay?: number;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ScrollAreaRootProps>, {
    type: string;
    scrollHideDelay: number;
}>, {
    /** Viewport element within ScrollArea */
    viewport: Ref<HTMLElement | undefined>;
    /** Scroll viewport to top */
    scrollTop: () => void;
    /** Scroll viewport to top-left */
    scrollTopLeft: () => void;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ScrollAreaRootProps>, {
    type: string;
    scrollHideDelay: number;
}>>>, {
    type: ScrollType;
    scrollHideDelay: number;
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
