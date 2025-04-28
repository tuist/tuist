export type Orientation = 'horizontal' | 'vertical';
export type Direction = 'ltr' | 'rtl';
export declare const ENTRY_FOCUS = "rovingFocusGroup.onEntryFocus";
export declare const EVENT_OPTIONS: {
    bubbles: boolean;
    cancelable: boolean;
};
export declare const MAP_KEY_TO_FOCUS_INTENT: Record<string, FocusIntent>;
export declare function getDirectionAwareKey(key: string, dir?: Direction): string;
type FocusIntent = 'first' | 'last' | 'prev' | 'next';
export declare function getFocusIntent(event: KeyboardEvent, orientation?: Orientation, dir?: Direction): FocusIntent | undefined;
export declare function focusFirst(candidates: HTMLElement[], preventScroll?: boolean): void;
/**
 * Wraps an array around itself at a given start index
 * Example: `wrapArray(['a', 'b', 'c', 'd'], 2) === ['c', 'd', 'a', 'b']`
 */
export declare function wrapArray<T>(array: T[], startIndex: number): T[];
export {};
