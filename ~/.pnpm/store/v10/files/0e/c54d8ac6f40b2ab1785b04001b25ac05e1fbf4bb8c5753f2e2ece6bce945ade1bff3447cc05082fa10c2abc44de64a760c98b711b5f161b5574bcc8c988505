export declare const AUTOFOCUS_ON_MOUNT = "focusScope.autoFocusOnMount";
export declare const AUTOFOCUS_ON_UNMOUNT = "focusScope.autoFocusOnUnmount";
export declare const EVENT_OPTIONS: {
    bubbles: boolean;
    cancelable: boolean;
};
type FocusableTarget = HTMLElement | {
    focus: () => void;
};
/**
 * Attempts focusing the first element in a list of candidates.
 * Stops when focus has actually moved.
 */
export declare function focusFirst(candidates: HTMLElement[], { select }?: {
    select?: boolean | undefined;
}): true | undefined;
/**
 * Returns the first and last tabbable elements inside a container.
 */
export declare function getTabbableEdges(container: HTMLElement): readonly [HTMLElement | undefined, HTMLElement | undefined];
/**
 * Returns a list of potential tabbable candidates.
 *
 * NOTE: This is only a close approximation. For example it doesn't take into account cases like when
 * elements are not visible. This cannot be worked out easily by just reading a property, but rather
 * necessitate runtime knowledge (computed styles, etc). We deal with these cases separately.
 *
 * See: https://developer.mozilla.org/en-US/docs/Web/API/TreeWalker
 * Credit: https://github.com/discord/focus-layers/blob/master/src/util/wrapFocus.tsx#L1
 */
export declare function getTabbableCandidates(container: HTMLElement): HTMLElement[];
/**
 * Returns the first visible element in a list.
 * NOTE: Only checks visibility up to the `container`.
 */
export declare function findVisible(elements: HTMLElement[], container: HTMLElement): HTMLElement | undefined;
export declare function isHidden(node: HTMLElement, { upTo }: {
    upTo?: HTMLElement;
}): boolean;
export declare function isSelectableInput(element: any): element is FocusableTarget & {
    select: () => void;
};
export declare function focus(element?: FocusableTarget | null, { select }?: {
    select?: boolean | undefined;
}): void;
export {};
