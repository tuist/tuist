import { Ref } from 'vue';
export type PointerDownOutsideEvent = CustomEvent<{
    originalEvent: PointerEvent;
}>;
export type FocusOutsideEvent = CustomEvent<{
    originalEvent: FocusEvent;
}>;
export declare const DISMISSABLE_LAYER_NAME = "DismissableLayer";
export declare const CONTEXT_UPDATE = "dismissableLayer.update";
export declare const POINTER_DOWN_OUTSIDE = "dismissableLayer.pointerDownOutside";
export declare const FOCUS_OUTSIDE = "dismissableLayer.focusOutside";
/**
 * Listens for `pointerdown` outside a DOM subtree. We use `pointerdown` rather than `pointerup`
 * to mimic layer dismissing behaviour present in OS.
 * Returns props to pass to the node we want to check for outside events.
 */
export declare function usePointerDownOutside(onPointerDownOutside?: (event: PointerDownOutsideEvent) => void, element?: Ref<HTMLElement | undefined>): {
    onPointerDownCapture: () => boolean;
};
/**
 * Listens for when focus happens outside a DOM subtree.
 * Returns props to pass to the root (node) of the subtree we want to check.
 */
export declare function useFocusOutside(onFocusOutside?: (event: FocusOutsideEvent) => void, element?: Ref<HTMLElement | undefined>): {
    onFocusCapture: () => boolean;
    onBlurCapture: () => boolean;
};
export declare function dispatchUpdate(): void;
