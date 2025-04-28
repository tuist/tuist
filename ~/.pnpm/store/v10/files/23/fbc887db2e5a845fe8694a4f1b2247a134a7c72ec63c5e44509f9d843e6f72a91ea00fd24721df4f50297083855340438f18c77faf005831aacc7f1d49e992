import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Align, Side } from './utils';
export declare const PopperContentPropsDefaultValue: {
    side: "right" | "left" | "top" | "bottom";
    sideOffset: number;
    align: "center" | "end" | "start";
    alignOffset: number;
    arrowPadding: number;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    sticky: "partial" | "always";
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
};
export interface PopperContentProps extends PrimitiveProps {
    /**
     * The preferred side of the trigger to render against when open.
     * Will be reversed when collisions occur and avoidCollisions
     * is enabled.
     *
     * @defaultValue "top"
     */
    side?: Side;
    /**
     * The distance in pixels from the trigger.
     *
     * @defaultValue 0
     */
    sideOffset?: number;
    /**
     * The preferred alignment against the trigger.
     * May change when collisions occur.
     *
     * @defaultValue "center"
     */
    align?: Align;
    /**
     * An offset in pixels from the `start` or `end` alignment options.
     *
     * @defaultValue 0
     */
    alignOffset?: number;
    /**
     * When `true`, overrides the side andalign preferences
     * to prevent collisions with boundary edges.
     *
     * @defaultValue true
     */
    avoidCollisions?: boolean;
    /**
     * The element used as the collision boundary. By default
     * this is the viewport, though you can provide additional
     * element(s) to be included in this check.
     *
     * @defaultValue []
     */
    collisionBoundary?: Element | null | Array<Element | null>;
    /**
     * The distance in pixels from the boundary edges where collision
     * detection should occur. Accepts a number (same for all sides),
     * or a partial padding object, for example: { top: 20, left: 20 }.
     *
     * @defaultValue 0
     */
    collisionPadding?: number | Partial<Record<Side, number>>;
    /**
     * The padding between the arrow and the edges of the content.
     * If your content has border-radius, this will prevent it from
     * overflowing the corners.
     *
     * @defaultValue 0
     */
    arrowPadding?: number;
    /**
     * The sticky behavior on the align axis. `partial` will keep the
     * content in the boundary as long as the trigger is at least partially
     * in the boundary whilst "always" will keep the content in the boundary
     * regardless.
     *
     * @defaultValue "partial"
     */
    sticky?: 'partial' | 'always';
    /**
     * Whether to hide the content when the trigger becomes fully occluded.
     *
     * @defaultValue false
     */
    hideWhenDetached?: boolean;
    /**
     * Strategy to update the position of the floating element on every animation frame.
     *
     * @defaultValue 'optimized'
     */
    updatePositionStrategy?: 'optimized' | 'always';
    /**
     * Force content to be position within the viewport.
     *
     * Might overlap the reference element, which may not be desired.
     *
     * @defaultValue false
     */
    prioritizePosition?: boolean;
}
export interface PopperContentContext {
    placedSide: Ref<Side>;
    onArrowChange: (arrow: HTMLElement | undefined) => void;
    arrowX?: Ref<number>;
    arrowY?: Ref<number>;
    shouldHideArrow: Ref<boolean>;
}
export declare const injectPopperContentContext: <T extends PopperContentContext | null | undefined = PopperContentContext>(fallback?: T | undefined) => T extends null ? PopperContentContext | null : PopperContentContext, providePopperContentContext: (contextValue: PopperContentContext) => PopperContentContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<PopperContentProps>, {
    side: "right" | "left" | "top" | "bottom";
    sideOffset: number;
    align: "center" | "end" | "start";
    alignOffset: number;
    arrowPadding: number;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    sticky: "partial" | "always";
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    [x: string]: (...args: unknown[]) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<PopperContentProps>, {
    side: "right" | "left" | "top" | "bottom";
    sideOffset: number;
    align: "center" | "end" | "start";
    alignOffset: number;
    arrowPadding: number;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    sticky: "partial" | "always";
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
}>>>, {
    side: "right" | "left" | "top" | "bottom";
    align: "center" | "end" | "start";
    sticky: "partial" | "always";
    sideOffset: number;
    alignOffset: number;
    avoidCollisions: boolean;
    collisionBoundary: Element | (Element | null)[] | null;
    collisionPadding: number | Partial<Record<"right" | "left" | "top" | "bottom", number>>;
    arrowPadding: number;
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
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
