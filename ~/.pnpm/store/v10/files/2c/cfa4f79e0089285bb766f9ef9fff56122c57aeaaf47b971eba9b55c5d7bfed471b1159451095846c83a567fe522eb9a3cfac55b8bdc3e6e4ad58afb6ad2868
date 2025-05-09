import { JSX, MaybeFn, Nullable, MaybeElement as MaybeElement$2 } from '@zag-js/types';

declare function isCaretAtStart(input: HTMLInputElement | HTMLTextAreaElement | null): boolean;
declare function setCaretToEnd(input: HTMLInputElement | HTMLTextAreaElement | null): void;

declare function getComputedStyle(el: Element): CSSStyleDeclaration;

type DataUrlType = "image/png" | "image/jpeg" | "image/svg+xml";
interface DataUrlOptions {
    /**
     * The type of the image
     */
    type: DataUrlType;
    /**
     * The quality of the image
     * @default 0.92
     */
    quality?: number | undefined;
    /**
     * The background color of the canvas.
     * Useful when type is `image/jpeg`
     */
    background?: string | undefined;
}
declare function getDataUrl(svg: SVGSVGElement | undefined | null, opts: DataUrlOptions): Promise<string>;

type Booleanish = boolean | "true" | "false";
interface Point {
    x: number;
    y: number;
}
interface EventKeyOptions {
    dir?: "ltr" | "rtl" | undefined;
    orientation?: "horizontal" | "vertical" | undefined;
}
type NativeEvent<E> = JSX.ChangeEvent<any> extends E ? InputEvent : E extends JSX.SyntheticEvent<any, infer T> ? T : never;
type AnyPointerEvent = MouseEvent | TouchEvent | PointerEvent;
type MaybeElement$1 = Nullable<HTMLElement>;
type MaybeElementOrFn = MaybeFn<MaybeElement$1>;
type HTMLElementWithValue = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;

declare function getBeforeInputValue(event: Pick<InputEvent, "currentTarget">): string;
declare function getEventTarget<T extends EventTarget>(event: Partial<Pick<UIEvent, "target" | "composedPath">>): T | null;
declare const isSelfTarget: (event: Partial<Pick<UIEvent, "currentTarget" | "target" | "composedPath">>) => boolean;
declare function isOpeningInNewTab(event: Pick<MouseEvent, "currentTarget" | "metaKey" | "ctrlKey">): boolean;
declare function isDownloadingEvent(event: Pick<MouseEvent, "altKey" | "currentTarget">): boolean;
declare function isComposingEvent(event: any): boolean;
declare function isKeyboardClick(e: Pick<MouseEvent, "detail" | "clientX" | "clientY">): boolean;
declare function isCtrlOrMetaKey(e: Pick<KeyboardEvent, "ctrlKey" | "metaKey">): boolean;
declare function isPrintableKey(e: Pick<KeyboardEvent, "key" | "ctrlKey" | "metaKey">): boolean;
declare function isVirtualPointerEvent(e: PointerEvent): boolean;
declare function isVirtualClick(e: MouseEvent | PointerEvent): boolean;
declare const isLeftClick: (e: Pick<MouseEvent, "button">) => boolean;
declare const isContextMenuEvent: (e: Pick<MouseEvent, "button" | "ctrlKey" | "metaKey">) => boolean;
declare const isModifierKey: (e: Pick<KeyboardEvent, "ctrlKey" | "metaKey" | "altKey">) => boolean;
declare const isTouchEvent: (event: AnyPointerEvent) => event is TouchEvent;
declare function getEventKey(event: Pick<KeyboardEvent, "key">, options?: EventKeyOptions): string;
declare function getNativeEvent<E>(event: E): NativeEvent<E>;
declare function getEventStep(event: Pick<KeyboardEvent, "ctrlKey" | "metaKey" | "key" | "shiftKey">): 1 | 0.1 | 10;
declare function getEventPoint(event: any, type?: "page" | "client"): {
    x: number;
    y: number;
};
interface DOMEventMap extends DocumentEventMap, WindowEventMap, HTMLElementEventMap {
}
declare const addDomEvent: <K extends keyof DOMEventMap>(target: MaybeFn<EventTarget | null>, eventName: K, handler: (event: DOMEventMap[K]) => void, options?: boolean | AddEventListenerOptions) => () => void;

declare function setElementValue(el: HTMLElementWithValue | null, value: string, property?: "value" | "checked"): void;
declare function setElementChecked(el: HTMLInputElement | null, checked: boolean): void;
interface InputValueEventOptions {
    value: string | number;
    bubbles?: boolean;
}
declare function dispatchInputValueEvent(el: HTMLElementWithValue | null, options: InputValueEventOptions): void;
interface CheckedEventOptions {
    checked: boolean;
    bubbles?: boolean;
}
declare function dispatchInputCheckedEvent(el: HTMLInputElement | null, options: CheckedEventOptions): void;
interface TrackFormControlOptions {
    onFieldsetDisabledChange: (disabled: boolean) => void;
    onFormReset: VoidFunction;
}
declare function trackFormControl(el: HTMLElement | null, options: TrackFormControlOptions): (() => void) | undefined;

interface InitialFocusOptions {
    root: HTMLElement | null;
    getInitialEl?: (() => HTMLElement | null) | undefined;
    enabled?: boolean | undefined;
    filter?: ((el: HTMLElement) => boolean) | undefined;
}
declare function getInitialFocus(options: InitialFocusOptions): HTMLElement | undefined;
declare function isValidTabEvent(event: Pick<KeyboardEvent, "shiftKey" | "currentTarget">): boolean;

interface ObserveAttributeOptions {
    attributes: string[];
    callback(record: MutationRecord): void;
    defer?: boolean | undefined;
}
declare function observeAttributes(nodeOrFn: MaybeElementOrFn, options: ObserveAttributeOptions): () => void;
interface ObserveChildrenOptions {
    callback: MutationCallback;
    defer?: boolean | undefined;
}
declare function observeChildren(nodeOrFn: MaybeElementOrFn, options: ObserveChildrenOptions): () => void;

declare function clickIfLink(el: HTMLAnchorElement): void;

declare const isHTMLElement: (el: any) => el is HTMLElement;
declare const isDocument: (el: any) => el is Document;
declare const isWindow: (el: any) => el is Window;
declare const isVisualViewport: (el: any) => el is VisualViewport;
declare const getNodeName: (node: Node | Window) => string;
declare function isRootElement(node: Node): boolean;
declare const isNode: (el: any) => el is Node;
declare const isShadowRoot: (el: any) => el is ShadowRoot;
declare const isInputElement: (el: any) => el is HTMLInputElement;
declare const isAnchorElement: (el: HTMLElement | null | undefined) => el is HTMLAnchorElement;
declare const isElementVisible: (el: Node) => boolean;
declare function isEditableElement(el: HTMLElement | EventTarget | null): boolean;
type Target = HTMLElement | EventTarget | null | undefined;
declare function contains(parent: Target, child: Target): boolean;
declare function getDocument(el: Element | Window | Node | Document | null | undefined): Document;
declare function getDocumentElement(el: Element | Node | Window | Document | null | undefined): HTMLElement;
declare function getWindow(el: Node | ShadowRoot | Document | null | undefined): Window & typeof globalThis;
declare function getActiveElement(rootNode: Document | ShadowRoot): HTMLElement | null;
declare function getParentNode(node: Node): Node;

type OverflowAncestor = Array<VisualViewport | Window | HTMLElement | null>;
declare function getNearestOverflowAncestor(el: Node): HTMLElement;
declare function getOverflowAncestors(el: HTMLElement, list?: OverflowAncestor): OverflowAncestor;
declare function isInView(el: HTMLElement | Window | VisualViewport, ancestor: HTMLElement | Window | VisualViewport): boolean;
declare function isOverflowElement(el: HTMLElement): boolean;
interface ScrollOptions extends ScrollIntoViewOptions {
    rootEl: HTMLElement | null;
}
declare function scrollIntoView(el: HTMLElement | null | undefined, options?: ScrollOptions): void;
interface ScrollPosition {
    scrollLeft: number;
    scrollTop: number;
}
declare function getScrollPosition(element: HTMLElement | Window): ScrollPosition;

declare const isDom: () => boolean;
declare function getPlatform(): string;
declare function getUserAgent(): string;
declare const isTouchDevice: () => boolean;
declare const isIPhone: () => boolean;
declare const isIPad: () => boolean;
declare const isIos: () => boolean;
declare const isApple: () => boolean;
declare const isMac: () => boolean;
declare const isSafari: () => boolean;
declare const isFirefox: () => boolean;
declare const isChrome: () => boolean;
declare const isWebKit: () => boolean;
declare const isAndroid: () => boolean;

interface PercentValueOptions {
    inverted?: boolean | {
        x?: boolean;
        y?: boolean;
    } | undefined;
    dir?: "ltr" | "rtl" | undefined;
    orientation?: "vertical" | "horizontal" | undefined;
}
declare function getRelativePoint(point: Point, element: HTMLElement): {
    offset: {
        x: number;
        y: number;
    };
    percent: {
        x: number;
        y: number;
    };
    getPercentValue: (options?: PercentValueOptions) => number;
};

declare function requestPointerLock(doc: Document, fn?: (locked: boolean) => void): (() => void) | undefined;

interface PointerMoveDetails {
    /**
     * The current position of the pointer.
     */
    point: Point;
    /**
     * The event that triggered the move.
     */
    event: PointerEvent;
}
interface PointerMoveHandlers {
    /**
     * Called when the pointer is released.
     */
    onPointerUp: VoidFunction;
    /**
     * Called when the pointer moves.
     */
    onPointerMove: (details: PointerMoveDetails) => void;
}
declare function trackPointerMove(doc: Document, handlers: PointerMoveHandlers): () => void;

interface PressDetails {
    /**
     * The current position of the pointer.
     */
    point: Point;
    /**
     * The event that triggered the move.
     */
    event: PointerEvent;
}
interface TrackPressOptions {
    /**
     * The element that will be used to track the pointer events.
     */
    pointerNode: Element | null;
    /**
     * The element that will be used to track the keyboard focus events.
     */
    keyboardNode?: Element | null | undefined;
    /**
     * A function that determines if the key is valid for the press event.
     */
    isValidKey?(event: KeyboardEvent): boolean;
    /**
     * A function that will be called when the pointer is pressed.
     */
    onPress?(details: PressDetails): void;
    /**
     * A function that will be called when the pointer is pressed down.
     */
    onPressStart?(details: PressDetails): void;
    /**
     * A function that will be called when the pointer is pressed up or cancelled.
     */
    onPressEnd?(details: PressDetails): void;
}
declare function trackPress(options: TrackPressOptions): () => void;

interface ProxyTabFocusOptions<T = MaybeElement$1> {
    triggerElement?: T | undefined;
    onFocus?: ((elementToFocus: HTMLElement) => void) | undefined;
    onFocusEnter?: VoidFunction | undefined;
    defer?: boolean | undefined;
}
declare function proxyTabFocus(container: MaybeElementOrFn, options: ProxyTabFocusOptions<MaybeElementOrFn>): () => void;

type Root = Document | Element | null | undefined;
declare function queryAll<T extends Element = HTMLElement>(root: Root, selector: string): T[];
declare function query<T extends Element = HTMLElement>(root: Root, selector: string): T | null;
type ItemToId<T> = (v: T) => string;
interface Item {
    id: string;
}
declare const defaultItemToId: <T extends Item>(v: T) => string;
declare function itemById<T extends Item>(v: T[], id: string, itemToId?: ItemToId<T>): T | undefined;
declare function indexOfId<T extends Item>(v: T[], id: string, itemToId?: ItemToId<T>): number;
declare function nextById<T extends Item>(v: T[], id: string, loop?: boolean): T;
declare function prevById<T extends Item>(v: T[], id: string, loop?: boolean): T | null;

declare function nextTick(fn: VoidFunction): () => void;
declare function raf(fn: VoidFunction | (() => VoidFunction)): () => void;
declare function queueBeforeEvent(el: EventTarget, type: string, cb: () => void): () => void;

interface ElementRect {
    left: number;
    top: number;
    width: number;
    height: number;
}
interface RectEntryDetails {
    rects: ElementRect[];
    entries: ResizeObserverEntry[];
}
interface ElementRectOptions extends ResizeObserverOptions {
    /**
     * The callback to call when the element's rect changes.
     */
    onEntry: (details: RectEntryDetails) => void;
    /**
     * The function to call to get the element's rect.
     */
    measure: (el: HTMLElement) => ElementRect;
}
declare function trackElementRect(elements: MaybeElement$2[], options: ElementRectOptions): () => void;

interface ScopeContext {
    getRootNode?: (() => Document | ShadowRoot | Node) | undefined;
}
declare function createScope<T>(methods: T): {
    getRootNode: (ctx: ScopeContext) => Document | ShadowRoot;
    getDoc: (ctx: ScopeContext) => Document;
    getWin: (ctx: ScopeContext) => Window & typeof globalThis;
    getActiveElement: (ctx: ScopeContext) => HTMLElement | null;
    isActiveElement: (ctx: ScopeContext, elem: HTMLElement | null) => boolean;
    getById: <T_1 extends Element = HTMLElement>(ctx: ScopeContext, id: string) => T_1 | null;
    setValue: <T_1 extends HTMLElementWithValue>(elem: T_1 | null, value: string | number | null | undefined) => void;
} & T;

interface SearchableItem {
    id: string;
    textContent: string | null;
    dataset?: any;
}
declare function getByText<T extends SearchableItem>(v: T[], text: string, currentId?: string | null, itemToId?: ItemToId<T>): T | undefined;

declare function setAttribute(el: Element, attr: string, v: string): () => void;
declare function setProperty<T extends Element, K extends keyof T & string>(el: T, prop: K, v: T[K]): () => void;
declare function setStyle(el: HTMLElement | null | undefined, style: Partial<CSSStyleDeclaration>): () => void;
declare function setStyleProperty(el: HTMLElement | null | undefined, prop: string, value: string): () => void;

declare const MAX_Z_INDEX = 2147483647;
declare const dataAttr: (guard: boolean | undefined) => Booleanish;
declare const ariaAttr: (guard: boolean | undefined) => "true" | undefined;

type IncludeContainerType = boolean | "if-empty";
declare const getFocusables: (container: Pick<HTMLElement, "querySelectorAll"> | null, includeContainer?: IncludeContainerType) => HTMLElement[];
declare function isFocusable(element: HTMLElement | null): element is HTMLElement;
declare function getFirstFocusable(container: HTMLElement | null, includeContainer?: IncludeContainerType): HTMLElement | null;
declare function getTabbables(container: HTMLElement | null, includeContainer?: IncludeContainerType): HTMLElement[];
declare function isTabbable(el: HTMLElement | null): el is HTMLElement;
declare function getFirstTabbable(container: HTMLElement | null, includeContainer?: IncludeContainerType): HTMLElement | null;
declare function getLastTabbable(container: HTMLElement | null, includeContainer?: IncludeContainerType): HTMLElement | null;
declare function getTabbableEdges(container: HTMLElement | null, includeContainer?: IncludeContainerType): [HTMLElement, HTMLElement] | [null, null];
declare function getNextTabbable(container: HTMLElement | null, current?: HTMLElement | null): HTMLElement | null;
declare function getTabIndex(node: HTMLElement | SVGElement): number;

interface DisableTextSelectionOptions<T = MaybeElement> {
    target?: T | undefined;
    doc?: Document | undefined;
    defer?: boolean | undefined;
}
declare function restoreTextSelection(options?: DisableTextSelectionOptions): void;
type MaybeElement = HTMLElement | null | undefined;
type NodeOrFn = MaybeElement | (() => MaybeElement);
declare function disableTextSelection(options?: DisableTextSelectionOptions<NodeOrFn>): () => void;

interface TypeaheadState {
    keysSoFar: string;
    timer: number;
}
interface TypeaheadOptions<T> {
    state: TypeaheadState;
    activeId: string | null;
    key: string;
    timeout?: number | undefined;
    itemToId?: ItemToId<T> | undefined;
}
declare function getByTypeaheadImpl<T extends SearchableItem>(baseItems: T[], options: TypeaheadOptions<T>): T | undefined;
declare const getByTypeahead: typeof getByTypeaheadImpl & {
    defaultOptions: {
        keysSoFar: string;
        timer: number;
    };
    isValidEvent: typeof isValidTypeaheadEvent;
};
declare function isValidTypeaheadEvent(event: Pick<KeyboardEvent, "key" | "ctrlKey" | "metaKey">): boolean;

interface ViewportSize {
    width: number;
    height: number;
}
declare function trackVisualViewport(doc: Document, fn: (data: ViewportSize) => void): () => void;

declare const visuallyHiddenStyle: {
    readonly border: "0";
    readonly clip: "rect(0 0 0 0)";
    readonly height: "1px";
    readonly margin: "-1px";
    readonly overflow: "hidden";
    readonly padding: "0";
    readonly position: "absolute";
    readonly width: "1px";
    readonly whiteSpace: "nowrap";
    readonly wordWrap: "normal";
};
declare function setVisuallyHidden(el: HTMLElement): void;

type ElementGetter = () => Element | null;
declare function waitForElement(query: ElementGetter, cb: (el: HTMLElement) => void): () => void;
declare function waitForElements(queries: ElementGetter[], cb: (el: HTMLElement) => void): () => void;

export { type CheckedEventOptions, type DataUrlOptions, type DataUrlType, type DisableTextSelectionOptions, type ElementRect, type ElementRectOptions, type InitialFocusOptions, type InputValueEventOptions, type ItemToId, MAX_Z_INDEX, type ObserveAttributeOptions, type ObserveChildrenOptions, type OverflowAncestor, type PercentValueOptions, type PointerMoveDetails, type PointerMoveHandlers, type PressDetails, type ProxyTabFocusOptions, type RectEntryDetails, type ScopeContext, type ScrollOptions, type ScrollPosition, type SearchableItem, type TrackFormControlOptions, type TrackPressOptions, type TypeaheadOptions, type TypeaheadState, type ViewportSize, addDomEvent, ariaAttr, clickIfLink, contains, createScope, dataAttr, defaultItemToId, disableTextSelection, dispatchInputCheckedEvent, dispatchInputValueEvent, getActiveElement, getBeforeInputValue, getByText, getByTypeahead, getComputedStyle, getDataUrl, getDocument, getDocumentElement, getEventKey, getEventPoint, getEventStep, getEventTarget, getFirstFocusable, getFirstTabbable, getFocusables, getInitialFocus, getLastTabbable, getNativeEvent, getNearestOverflowAncestor, getNextTabbable, getNodeName, getOverflowAncestors, getParentNode, getPlatform, getRelativePoint, getScrollPosition, getTabIndex, getTabbableEdges, getTabbables, getUserAgent, getWindow, indexOfId, isAnchorElement, isAndroid, isApple, isCaretAtStart, isChrome, isComposingEvent, isContextMenuEvent, isCtrlOrMetaKey, isDocument, isDom, isDownloadingEvent, isEditableElement, isElementVisible, isFirefox, isFocusable, isHTMLElement, isIPad, isIPhone, isInView, isInputElement, isIos, isKeyboardClick, isLeftClick, isMac, isModifierKey, isNode, isOpeningInNewTab, isOverflowElement, isPrintableKey, isRootElement, isSafari, isSelfTarget, isShadowRoot, isTabbable, isTouchDevice, isTouchEvent, isValidTabEvent, isVirtualClick, isVirtualPointerEvent, isVisualViewport, isWebKit, isWindow, itemById, nextById, nextTick, observeAttributes, observeChildren, prevById, proxyTabFocus, query, queryAll, queueBeforeEvent, raf, requestPointerLock, restoreTextSelection, scrollIntoView, setAttribute, setCaretToEnd, setElementChecked, setElementValue, setProperty, setStyle, setStyleProperty, setVisuallyHidden, trackElementRect, trackFormControl, trackPointerMove, trackPress, trackVisualViewport, visuallyHiddenStyle, waitForElement, waitForElements };
