export declare const TOAST_SWIPE_START = "toast.swipeStart";
export declare const TOAST_SWIPE_MOVE = "toast.swipeMove";
export declare const TOAST_SWIPE_CANCEL = "toast.swipeCancel";
export declare const TOAST_SWIPE_END = "toast.swipeEnd";
export declare const VIEWPORT_NAME = "ToastViewport";
export declare const VIEWPORT_DEFAULT_HOTKEY: string[];
export declare const VIEWPORT_PAUSE = "toast.viewportPause";
export declare const VIEWPORT_RESUME = "toast.viewportResume";
export type SwipeDirection = 'up' | 'down' | 'left' | 'right';
export type SwipeEvent = {
    currentTarget: EventTarget & HTMLElement;
} & Omit<CustomEvent<{
    originalEvent: PointerEvent;
    delta: {
        x: number;
        y: number;
    };
}>, 'currentTarget'>;
export declare function handleAndDispatchCustomEvent<E extends CustomEvent, OriginalEvent extends Event>(name: string, handler: ((event: E) => void) | undefined, detail: {
    originalEvent: OriginalEvent;
} & (E extends CustomEvent<infer D> ? D : never)): void;
export declare function isDeltaInDirection(delta: {
    x: number;
    y: number;
}, direction: SwipeDirection, threshold?: number): boolean;
export declare function isHTMLElement(node: any): node is HTMLElement;
export declare function getAnnounceTextContent(container: HTMLElement): string[];
