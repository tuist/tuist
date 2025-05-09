type FocusableElement = HTMLElement | SVGElement;
type FocusTargetValue = FocusableElement | string;
type FocusTargetValueOrFalse = FocusTargetValue | false;
/**
 * A DOM node, a selector string (which will be passed to
 * `document.querySelector()` to find the DOM node), or a function that
 * returns a DOM node.
 */
type FocusTarget = FocusTargetValue | (() => FocusTargetValue);
/**
 * A DOM node, a selector string (which will be passed to
 * `document.querySelector()` to find the DOM node), `false` to explicitly indicate
 * an opt-out, or a function that returns a DOM node or `false`.
 */
type FocusTargetOrFalse = FocusTargetValueOrFalse | (() => FocusTargetValueOrFalse);
type MouseEventToBoolean = (event: MouseEvent | TouchEvent) => boolean;
type KeyboardEventToBoolean = (event: KeyboardEvent) => boolean;
interface FocusTrapOptions {
    /**
     * A function that will be called **before** sending focus to the
     * target element upon activation.
     */
    onActivate?: VoidFunction;
    /**
     * A function that will be called **after** focus has been sent to the
     * target element upon activation.
     */
    onPostActivate?: VoidFunction;
    /**
     * A function that will be called immediately after the trap's state is updated to be paused.
     */
    onPause?: VoidFunction;
    /**
     * A function that will be called after the trap has been completely paused and is no longer
     *  managing/trapping focus.
     */
    onPostPause?: VoidFunction;
    /**
     * A function that will be called immediately after the trap's state is updated to be active
     *  again, but prior to updating its knowledge of what nodes are tabbable within its containers,
     *  and prior to actively managing/trapping focus.
     */
    onUnpause?: VoidFunction;
    /**
     * A function that will be called after the trap has been completely unpaused and is once
     *  again managing/trapping focus.
     */
    onPostUnpause?: VoidFunction;
    /**
     * A function for determining if it is safe to send focus to the focus trap
     * or not.
     *
     * It should return a promise that only resolves once all the listed `containers`
     * are able to receive focus.
     *
     * The purpose of this is to prevent early focus-trap activation on animated
     * dialogs that fade in and out. When a dialog fades in, there is a brief delay
     * between the activation of the trap and the trap element being focusable.
     */
    checkCanFocusTrap?: (containers: Array<HTMLElement | SVGElement>) => Promise<void>;
    /**
     * A function that will be called **before** sending focus to the
     * trigger element upon deactivation.
     */
    onDeactivate?: VoidFunction;
    /**
     * A function that will be called after the trap is deactivated, after `onDeactivate`.
     * If `returnFocus` was set, it will be called **after** focus has been sent to the trigger
     * element upon deactivation; otherwise, it will be called after deactivation completes.
     */
    onPostDeactivate?: VoidFunction;
    /**
     * A function for determining if it is safe to send focus back to the `trigger` element.
     *
     * It should return a promise that only resolves once `trigger` is focusable.
     *
     * The purpose of this is to prevent the focus being sent to an animated trigger element too early.
     * If a trigger element fades in upon trap deactivation, there is a brief delay between the deactivation
     * of the trap and when the trigger element is focusable.
     *
     * `trigger` will be either the node that had focus prior to the trap being activated,
     * or the result of the `setReturnFocus` option, if configured.
     *
     * This handler is **not** called if the `returnFocusOnDeactivate` configuration option
     * (or the `returnFocus` deactivation option) is falsy.
     */
    checkCanReturnFocus?: (trigger: HTMLElement | SVGElement) => Promise<void>;
    /**
     * By default, when a focus trap is activated the first element in the
     * focus trap's tab order will receive focus. With this option you can
     * specify a different element to receive that initial focus, or use `false`
     * for no initially focused element at all.
     *
     * NOTE: Setting this option to `false` (or a function that returns `false`)
     * will prevent the `fallbackFocus` option from being used.
     *
     * Setting this option to `undefined` (or a function that returns `undefined`)
     * will result in the default behavior.
     */
    initialFocus?: FocusTargetOrFalse | undefined | VoidFunction;
    /**
     * By default, an error will be thrown if the focus trap contains no
     * elements in its tab order. With this option you can specify a
     * fallback element to programmatically receive focus if no other
     * tabbable elements are found. For example, you may want a popover's
     * `<div>` to receive focus if the popover's content includes no
     * tabbable elements. *Make sure the fallback element has a negative
     * `tabindex` so it can be programmatically focused.
     *
     * NOTE: If `initialFocus` is `false` (or a function that returns `false`),
     * this function will not be called when the trap is activated, and no element
     * will be initially focused. This function may still be called while the trap
     * is active if things change such that there are no longer any tabbable nodes
     * in the trap.
     */
    fallbackFocus?: FocusTarget;
    /**
     * Default: `true`. If `false`, when the trap is deactivated,
     * focus will *not* return to the element that had focus before activation.
     */
    returnFocusOnDeactivate?: boolean;
    /**
     * By default, focus trap on deactivation will return to the element
     * that was focused before activation.
     */
    setReturnFocus?: FocusTargetValueOrFalse | ((nodeFocusedBeforeActivation: HTMLElement | SVGElement) => FocusTargetValueOrFalse);
    /**
     * Default: `true`. If `false` or returns `false`, the `Escape` key will not trigger
     * deactivation of the focus trap. This can be useful if you want
     * to force the user to make a decision instead of allowing an easy
     * way out. Note that if a function is given, it's only called if the ESC key
     * was pressed.
     */
    escapeDeactivates?: boolean | KeyboardEventToBoolean;
    /**
     * If `true` or returns `true`, a click outside the focus trap will
     * deactivate the focus trap and allow the click event to do its thing (i.e.
     * to pass-through to the element that was clicked). This option **takes
     * precedence** over `allowOutsideClick` when it's set to `true`, causing
     * that option to be ignored. Default: `false`.
     */
    clickOutsideDeactivates?: boolean | MouseEventToBoolean;
    /**
     * If set and is or returns `true`, a click outside the focus trap will not
     * be prevented, even when `clickOutsideDeactivates` is `false`. When
     * `clickOutsideDeactivates` is `true`, this option is **ignored** (i.e.
     * if it's a function, it will not be called). Use this option to control
     * if (and even which) clicks are allowed outside the trap in conjunction
     * with `clickOutsideDeactivates: false`. Default: `false`.
     */
    allowOutsideClick?: boolean | MouseEventToBoolean;
    /**
     * By default, focus() will scroll to the element if not in viewport.
     * It can produce unintended effects like scrolling back to the top of a modal.
     * If set to `true`, no scroll will happen.
     */
    preventScroll?: boolean;
    /**
     * Default: `true`. Delays the autofocus when the focus trap is activated.
     * This prevents elements within the focusable element from capturing
     * the event that triggered the focus trap activation.
     */
    delayInitialFocus?: boolean;
    /**
     * Default: `window.document`. Document where the focus trap will be active.
     * This allows to use FocusTrap in an iFrame context.
     */
    document?: Document;
    /**
     * Determines if the given keyboard event is a "tab forward" event that will move
     * the focus to the next trapped element in tab order. Defaults to the `TAB` key.
     * Use this to override the trap's behavior if you want to use arrow keys to control
     * keyboard navigation within the trap, for example. Also see `isKeyBackward()` option.
     */
    isKeyForward?: KeyboardEventToBoolean;
    /**
     * Determines if the given keyboard event is a "tab backward" event that will move
     * the focus to the previous trapped element in tab order. Defaults to the `SHIFT+TAB` key.
     * Use this to override the trap's behavior if you want to use arrow keys to control
     * keyboard navigation within the trap, for example. Also see `isKeyForward()` option.
     */
    isKeyBackward?: KeyboardEventToBoolean;
    /**
     * Default: `[]`. An array of FocusTrap instances that will be managed by this FocusTrap.
     */
    trapStack?: any[];
}
interface DeactivateOptions extends Pick<FocusTrapOptions, "onDeactivate" | "onPostDeactivate" | "checkCanReturnFocus"> {
    returnFocus?: boolean | undefined;
}
type ActivateOptions = Pick<FocusTrapOptions, "onActivate" | "onPostActivate" | "checkCanFocusTrap">;
type PauseOptions = Pick<FocusTrapOptions, "onPause" | "onPostPause">;
type UnpauseOptions = Pick<FocusTrapOptions, "onUnpause" | "onPostUnpause">;

declare class FocusTrap {
    private trapStack;
    private config;
    private doc;
    private state;
    get active(): boolean;
    get paused(): boolean;
    constructor(elements: HTMLElement | HTMLElement[], options: FocusTrapOptions);
    private findContainerIndex;
    private updateTabbableNodes;
    private listenerCleanups;
    private addListeners;
    private removeListeners;
    private handleFocus;
    private handlePointerDown;
    private handleClick;
    private handleTabKey;
    private handleEscapeKey;
    private _mutationObserver?;
    private setupMutationObserver;
    private updateObservedNodes;
    private getInitialFocusNode;
    private tryFocus;
    activate(activateOptions?: ActivateOptions): this;
    deactivate: (deactivateOptions?: DeactivateOptions) => this;
    pause: (pauseOptions?: PauseOptions) => this;
    unpause: (unpauseOptions?: UnpauseOptions) => this;
    updateContainerElements: (containerElements: HTMLElement | HTMLElement[]) => this;
    private getReturnFocusNode;
    private getOption;
    private getNodeForOption;
    private findNextNavNode;
}

type ElementOrGetter = HTMLElement | null | (() => HTMLElement | null);
interface TrapFocusOptions extends Omit<FocusTrapOptions, "document"> {
}
declare function trapFocus(el: ElementOrGetter, options?: TrapFocusOptions): () => void;

export { FocusTrap, type FocusTrapOptions, type TrapFocusOptions, trapFocus };
