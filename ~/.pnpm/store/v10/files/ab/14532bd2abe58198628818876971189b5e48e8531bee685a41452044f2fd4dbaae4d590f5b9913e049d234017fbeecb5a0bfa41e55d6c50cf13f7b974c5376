export type Orientation = 'vertical' | 'horizontal';
export type Direction = 'ltr' | 'rtl';
export declare function getOpenState(open: boolean): "open" | "closed";
export declare function makeTriggerId(baseId: string, value: string): string;
export declare function makeContentId(baseId: string, value: string): string;
export declare const LINK_SELECT = "navigationMenu.linkSelect";
export declare const EVENT_ROOT_CONTENT_DISMISS = "navigationMenu.rootContentDismiss";
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
export declare function focusFirst(candidates: HTMLElement[]): boolean;
export declare function removeFromTabOrder(candidates: HTMLElement[]): () => void;
export declare function whenMouse<E extends PointerEvent>(handler: (event?: E) => void): (event: E) => void;
