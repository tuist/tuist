import * as CSS from 'csstype';

type NativeAnimationEvent = AnimationEvent;
type NativeClipboardEvent = ClipboardEvent;
type NativeCompositionEvent = CompositionEvent;
type NativeDragEvent = DragEvent;
type NativeFocusEvent = FocusEvent;
type NativeKeyboardEvent = KeyboardEvent;
type NativeMouseEvent = MouseEvent;
type NativeTouchEvent = TouchEvent;
type NativePointerEvent = PointerEvent;
type NativeTransitionEvent = TransitionEvent;
type NativeUIEvent = UIEvent;
type NativeWheelEvent = WheelEvent;
type Booleanish = boolean | "true" | "false";
declare namespace JSX {
    export interface BaseSyntheticEvent<E = object, C = any, T = any> {
        nativeEvent: E;
        currentTarget: C;
        target: T;
        bubbles: boolean;
        cancelable: boolean;
        defaultPrevented: boolean;
        eventPhase: number;
        isTrusted: boolean;
        preventDefault(): void;
        isDefaultPrevented(): boolean;
        stopPropagation(): void;
        isPropagationStopped(): boolean;
        persist(): void;
        timeStamp: number;
        type: string;
    }
    export interface SyntheticEvent<T = Element, E = Event> extends BaseSyntheticEvent<E, EventTarget & T, EventTarget> {
    }
    export interface ClipboardEvent<T = Element> extends SyntheticEvent<T, NativeClipboardEvent> {
        clipboardData: DataTransfer;
    }
    export interface CompositionEvent<T = Element> extends SyntheticEvent<T, NativeCompositionEvent> {
        data: string;
    }
    export interface DragEvent<T = Element> extends MouseEvent<T, NativeDragEvent> {
        dataTransfer: DataTransfer;
    }
    export interface PointerEvent<T = Element> extends MouseEvent<T, NativePointerEvent> {
        pointerId: number;
        pressure: number;
        tangentialPressure: number;
        tiltX: number;
        tiltY: number;
        twist: number;
        width: number;
        height: number;
        pointerType: "mouse" | "pen" | "touch";
        isPrimary: boolean;
    }
    export interface FocusEvent<Target = Element, RelatedTarget = Element> extends SyntheticEvent<Target, NativeFocusEvent> {
        relatedTarget: (EventTarget & RelatedTarget) | null;
        target: EventTarget & Target;
    }
    export interface FormEvent<T = Element> extends SyntheticEvent<T> {
    }
    export interface InvalidEvent<T = Element> extends SyntheticEvent<T> {
        target: EventTarget & T;
    }
    export interface ChangeEvent<T = Element> extends SyntheticEvent<T> {
        target: EventTarget & T;
    }
    export interface KeyboardEvent<T = Element> extends UIEvent<T, NativeKeyboardEvent> {
        altKey: boolean;
        /** @deprecated */
        charCode: number;
        ctrlKey: boolean;
        code: string;
        /**
         * See [DOM Level 3 Events spec](https://www.w3.org/TR/uievents-key/#keys-modifier). for a list of valid (case-sensitive) arguments to this method.
         */
        getModifierState(key: string): boolean;
        /**
         * See the [DOM Level 3 Events spec](https://www.w3.org/TR/uievents-key/#named-key-attribute-values). for possible values
         */
        key: string;
        /** @deprecated */
        keyCode: number;
        locale: string;
        location: number;
        metaKey: boolean;
        repeat: boolean;
        shiftKey: boolean;
        /** @deprecated */
        which: number;
    }
    export interface MouseEvent<T = Element, E = NativeMouseEvent> extends UIEvent<T, E> {
        altKey: boolean;
        button: number;
        buttons: number;
        clientX: number;
        clientY: number;
        ctrlKey: boolean;
        /**
         * See [DOM Level 3 Events spec](https://www.w3.org/TR/uievents-key/#keys-modifier). for a list of valid (case-sensitive) arguments to this method.
         */
        getModifierState(key: string): boolean;
        metaKey: boolean;
        movementX: number;
        movementY: number;
        pageX: number;
        pageY: number;
        relatedTarget: EventTarget | null;
        screenX: number;
        screenY: number;
        shiftKey: boolean;
    }
    export interface TouchEvent<T = Element> extends UIEvent<T, NativeTouchEvent> {
        altKey: boolean;
        changedTouches: TouchList;
        ctrlKey: boolean;
        /**
         * See [DOM Level 3 Events spec](https://www.w3.org/TR/uievents-key/#keys-modifier). for a list of valid (case-sensitive) arguments to this method.
         */
        getModifierState(key: string): boolean;
        metaKey: boolean;
        shiftKey: boolean;
        targetTouches: TouchList;
        touches: TouchList;
    }
    export interface AbstractView {
        document: Document;
        styleMedia: StyleMedia;
    }
    export interface UIEvent<T = Element, E = NativeUIEvent> extends SyntheticEvent<T, E> {
        detail: number;
        view: AbstractView;
    }
    export interface WheelEvent<T = Element> extends MouseEvent<T, NativeWheelEvent> {
        deltaMode: number;
        deltaX: number;
        deltaY: number;
        deltaZ: number;
    }
    export interface AnimationEvent<T = Element> extends SyntheticEvent<T, NativeAnimationEvent> {
        animationName: string;
        elapsedTime: number;
        pseudoElement: string;
    }
    export interface TransitionEvent<T = Element> extends SyntheticEvent<T, NativeTransitionEvent> {
        elapsedTime: number;
        propertyName: string;
        pseudoElement: string;
    }
    type EventHandler<E extends SyntheticEvent<any>> = {
        bivarianceHack(event: E): void;
    }["bivarianceHack"];
    type ZagEventHandler<T = Element> = EventHandler<SyntheticEvent<T>>;
    export type ClipboardEventHandler<T = Element> = EventHandler<ClipboardEvent<T>>;
    export type CompositionEventHandler<T = Element> = EventHandler<CompositionEvent<T>>;
    export type DragEventHandler<T = Element> = EventHandler<DragEvent<T>>;
    export type FocusEventHandler<T = Element> = EventHandler<FocusEvent<T>>;
    export type FormEventHandler<T = Element> = EventHandler<FormEvent<T>>;
    export type ChangeEventHandler<T = Element> = EventHandler<ChangeEvent<T>>;
    export type KeyboardEventHandler<T = Element> = EventHandler<KeyboardEvent<T>>;
    export type MouseEventHandler<T = Element> = EventHandler<MouseEvent<T>>;
    export type TouchEventHandler<T = Element> = EventHandler<TouchEvent<T>>;
    export type PointerEventHandler<T = Element> = EventHandler<PointerEvent<T>>;
    export type UIEventHandler<T = Element> = EventHandler<UIEvent<T>>;
    export type WheelEventHandler<T = Element> = EventHandler<WheelEvent<T>>;
    export type AnimationEventHandler<T = Element> = EventHandler<AnimationEvent<T>>;
    export type TransitionEventHandler<T = Element> = EventHandler<TransitionEvent<T>>;
    export interface HTMLProps<T> extends AllHTMLAttributes<T> {
    }
    export interface DOMAttributes<T> {
        children?: string | undefined;
        onCopy?: ClipboardEventHandler<T> | undefined;
        onCut?: ClipboardEventHandler<T> | undefined;
        onPaste?: ClipboardEventHandler<T> | undefined;
        onCompositionEnd?: CompositionEventHandler<T> | undefined;
        onCompositionStart?: CompositionEventHandler<T> | undefined;
        onCompositionUpdate?: CompositionEventHandler<T> | undefined;
        onFocus?: FocusEventHandler<T> | undefined;
        onBlur?: FocusEventHandler<T> | undefined;
        onChange?: FormEventHandler<T> | undefined;
        onBeforeInput?: FormEventHandler<T> | undefined;
        onInput?: FormEventHandler<T> | undefined;
        onReset?: FormEventHandler<T> | undefined;
        onSubmit?: FormEventHandler<T> | undefined;
        onInvalid?: FormEventHandler<T> | undefined;
        onLoad?: ZagEventHandler<T> | undefined;
        onError?: ZagEventHandler<T> | undefined;
        onKeyDown?: KeyboardEventHandler<T> | undefined;
        onKeyUp?: KeyboardEventHandler<T> | undefined;
        onAbort?: ZagEventHandler<T> | undefined;
        onCanPlay?: ZagEventHandler<T> | undefined;
        onCanPlayThrough?: ZagEventHandler<T> | undefined;
        onDurationChange?: ZagEventHandler<T> | undefined;
        onEmptied?: ZagEventHandler<T> | undefined;
        onEncrypted?: ZagEventHandler<T> | undefined;
        onEnded?: ZagEventHandler<T> | undefined;
        onLoadedData?: ZagEventHandler<T> | undefined;
        onLoadedMetadata?: ZagEventHandler<T> | undefined;
        onLoadStart?: ZagEventHandler<T> | undefined;
        onPause?: ZagEventHandler<T> | undefined;
        onPlay?: ZagEventHandler<T> | undefined;
        onPlaying?: ZagEventHandler<T> | undefined;
        onProgress?: ZagEventHandler<T> | undefined;
        onRateChange?: ZagEventHandler<T> | undefined;
        onSeeked?: ZagEventHandler<T> | undefined;
        onSeeking?: ZagEventHandler<T> | undefined;
        onStalled?: ZagEventHandler<T> | undefined;
        onSuspend?: ZagEventHandler<T> | undefined;
        onTimeUpdate?: ZagEventHandler<T> | undefined;
        onVolumeChange?: ZagEventHandler<T> | undefined;
        onWaiting?: ZagEventHandler<T> | undefined;
        onAuxClick?: MouseEventHandler<T> | undefined;
        onClick?: MouseEventHandler<T> | undefined;
        onContextMenu?: MouseEventHandler<T> | undefined;
        onDoubleClick?: MouseEventHandler<T> | undefined;
        onDrag?: DragEventHandler<T> | undefined;
        onDragEnd?: DragEventHandler<T> | undefined;
        onDragEnter?: DragEventHandler<T> | undefined;
        onDragExit?: DragEventHandler<T> | undefined;
        onDragLeave?: DragEventHandler<T> | undefined;
        onDragOver?: DragEventHandler<T> | undefined;
        onDragStart?: DragEventHandler<T> | undefined;
        onDrop?: DragEventHandler<T> | undefined;
        onMouseDown?: MouseEventHandler<T> | undefined;
        onMouseEnter?: MouseEventHandler<T> | undefined;
        onMouseLeave?: MouseEventHandler<T> | undefined;
        onMouseMove?: MouseEventHandler<T> | undefined;
        onMouseOut?: MouseEventHandler<T> | undefined;
        onMouseOver?: MouseEventHandler<T> | undefined;
        onMouseUp?: MouseEventHandler<T> | undefined;
        onSelect?: ZagEventHandler<T> | undefined;
        onTouchCancel?: TouchEventHandler<T> | undefined;
        onTouchEnd?: TouchEventHandler<T> | undefined;
        onTouchMove?: TouchEventHandler<T> | undefined;
        onTouchStart?: TouchEventHandler<T> | undefined;
        onPointerDown?: PointerEventHandler<T> | undefined;
        onPointerMove?: PointerEventHandler<T> | undefined;
        onPointerUp?: PointerEventHandler<T> | undefined;
        onPointerCancel?: PointerEventHandler<T> | undefined;
        onPointerEnter?: PointerEventHandler<T> | undefined;
        onPointerLeave?: PointerEventHandler<T> | undefined;
        onPointerOver?: PointerEventHandler<T> | undefined;
        onPointerOut?: PointerEventHandler<T> | undefined;
        onScroll?: UIEventHandler<T> | undefined;
        onWheel?: WheelEventHandler<T> | undefined;
        onAnimationStart?: AnimationEventHandler<T> | undefined;
        onAnimationEnd?: AnimationEventHandler<T> | undefined;
        onAnimationIteration?: AnimationEventHandler<T> | undefined;
        onTransitionEnd?: TransitionEventHandler<T> | undefined;
    }
    export interface CSSProperties extends CSS.Properties<string | number> {
        [prop: string]: string | number | undefined;
    }
    export interface AriaAttributes {
        /** Identifies the currently active element when DOM focus is on a composite widget, textbox, group, or application. */
        "aria-activedescendant"?: string | undefined;
        /** Indicates whether assistive technologies will present all, or only parts of, the changed region based on the change notifications defined by the aria-relevant attribute. */
        "aria-atomic"?: Booleanish | undefined;
        /**
         * Indicates whether inputting text could trigger display of one or more predictions of the user's intended value for an input and specifies how predictions would be
         * presented if they are made.
         */
        "aria-autocomplete"?: "none" | "inline" | "list" | "both" | undefined;
        /** Indicates an element is being modified and that assistive technologies MAY want to wait until the modifications are complete before exposing them to the user. */
        "aria-busy"?: Booleanish | undefined;
        /**
         * Indicates the current "checked" state of checkboxes, radio buttons, and other widgets.
         * @see aria-pressed @see aria-selected.
         */
        "aria-checked"?: boolean | "false" | "mixed" | "true" | undefined;
        /**
         * Defines the total number of columns in a table, grid, or treegrid.
         * @see aria-colindex.
         */
        "aria-colcount"?: number | undefined;
        /**
         * Defines an element's column index or position with respect to the total number of columns within a table, grid, or treegrid.
         * @see aria-colcount @see aria-colspan.
         */
        "aria-colindex"?: number | undefined;
        /**
         * Defines the number of columns spanned by a cell or gridcell within a table, grid, or treegrid.
         * @see aria-colindex @see aria-rowspan.
         */
        "aria-colspan"?: number | undefined;
        /**
         * Identifies the element (or elements) whose contents or presence are controlled by the current element.
         * @see aria-owns.
         */
        "aria-controls"?: string | undefined;
        /** Indicates the element that represents the current item within a container or set of related elements. */
        "aria-current"?: boolean | "false" | "true" | "page" | "step" | "location" | "date" | "time" | undefined;
        /**
         * Identifies the element (or elements) that describes the object.
         * @see aria-labelledby
         */
        "aria-describedby"?: string | undefined;
        /**
         * Identifies the element that provides a detailed, extended description for the object.
         * @see aria-describedby.
         */
        "aria-details"?: string | undefined;
        /**
         * Indicates that the element is perceivable but disabled, so it is not editable or otherwise operable.
         * @see aria-hidden @see aria-readonly.
         */
        "aria-disabled"?: Booleanish | undefined;
        /**
         * Indicates what functions can be performed when a dragged object is released on the drop target.
         * @deprecated in ARIA 1.1
         */
        "aria-dropeffect"?: "none" | "copy" | "execute" | "link" | "move" | "popup" | undefined;
        /**
         * Identifies the element that provides an error message for the object.
         * @see aria-invalid @see aria-describedby.
         */
        "aria-errormessage"?: string | undefined;
        /** Indicates whether the element, or another grouping element it controls, is currently expanded or collapsed. */
        "aria-expanded"?: Booleanish | undefined;
        /**
         * Identifies the next element (or elements) in an alternate reading order of content which, at the user's discretion,
         * allows assistive technology to override the general default of reading in document source order.
         */
        "aria-flowto"?: string | undefined;
        /**
         * Indicates an element's "grabbed" state in a drag-and-drop operation.
         * @deprecated in ARIA 1.1
         */
        "aria-grabbed"?: Booleanish | undefined;
        /** Indicates the availability and type of interactive popup element, such as menu or dialog, that can be triggered by an element. */
        "aria-haspopup"?: boolean | "false" | "true" | "menu" | "listbox" | "tree" | "grid" | "dialog" | undefined;
        /**
         * Indicates whether the element is exposed to an accessibility API.
         * @see aria-disabled.
         */
        "aria-hidden"?: Booleanish | undefined;
        /**
         * Indicates the entered value does not conform to the format expected by the application.
         * @see aria-errormessage.
         */
        "aria-invalid"?: boolean | "false" | "true" | "grammar" | "spelling" | undefined;
        /** Indicates keyboard shortcuts that an author has implemented to activate or give focus to an element. */
        "aria-keyshortcuts"?: string | undefined;
        /**
         * Defines a string value that labels the current element.
         * @see aria-labelledby.
         */
        "aria-label"?: string | undefined;
        /**
         * Identifies the element (or elements) that labels the current element.
         * @see aria-describedby.
         */
        "aria-labelledby"?: string | undefined;
        /** Defines the hierarchical level of an element within a structure. */
        "aria-level"?: number | undefined;
        /** Indicates that an element will be updated, and describes the types of updates the user agents, assistive technologies, and user can expect from the live region. */
        "aria-live"?: "off" | "assertive" | "polite" | undefined;
        /** Indicates whether an element is modal when displayed. */
        "aria-modal"?: Booleanish | undefined;
        /** Indicates whether a text box accepts multiple lines of input or only a single line. */
        "aria-multiline"?: Booleanish | undefined;
        /** Indicates that the user may select more than one item from the current selectable descendants. */
        "aria-multiselectable"?: Booleanish | undefined;
        /** Indicates whether the element's orientation is horizontal, vertical, or unknown/ambiguous. */
        "aria-orientation"?: "horizontal" | "vertical" | undefined;
        /**
         * Identifies an element (or elements) in order to define a visual, functional, or contextual parent/child relationship
         * between DOM elements where the DOM hierarchy cannot be used to represent the relationship.
         * @see aria-controls.
         */
        "aria-owns"?: string | undefined;
        /**
         * Defines a short hint (a word or short phrase) intended to aid the user with data entry when the control has no value.
         * A hint could be a sample value or a brief description of the expected format.
         */
        "aria-placeholder"?: string | undefined;
        /**
         * Defines an element's number or position in the current set of listitems or treeitems. Not required if all elements in the set are present in the DOM.
         * @see aria-setsize.
         */
        "aria-posinset"?: number | undefined;
        /**
         * Indicates the current "pressed" state of toggle buttons.
         * @see aria-checked @see aria-selected.
         */
        "aria-pressed"?: boolean | "false" | "mixed" | "true" | undefined;
        /**
         * Indicates that the element is not editable, but is otherwise operable.
         * @see aria-disabled.
         */
        "aria-readonly"?: Booleanish | undefined;
        /**
         * Indicates what notifications the user agent will trigger when the accessibility tree within a live region is modified.
         * @see aria-atomic.
         */
        "aria-relevant"?: "additions" | "additions removals" | "additions text" | "all" | "removals" | "removals additions" | "removals text" | "text" | "text additions" | "text removals" | undefined;
        /** Indicates that user input is required on the element before a form may be submitted. */
        "aria-required"?: Booleanish | undefined;
        /** Defines a human-readable, author-localized description for the role of an element. */
        "aria-roledescription"?: string | undefined;
        /**
         * Defines the total number of rows in a table, grid, or treegrid.
         * @see aria-rowindex.
         */
        "aria-rowcount"?: number | undefined;
        /**
         * Defines an element's row index or position with respect to the total number of rows within a table, grid, or treegrid.
         * @see aria-rowcount @see aria-rowspan.
         */
        "aria-rowindex"?: number | undefined;
        /**
         * Defines the number of rows spanned by a cell or gridcell within a table, grid, or treegrid.
         * @see aria-rowindex @see aria-colspan.
         */
        "aria-rowspan"?: number | undefined;
        /**
         * Indicates the current "selected" state of various widgets.
         * @see aria-checked @see aria-pressed.
         */
        "aria-selected"?: Booleanish | undefined;
        /**
         * Defines the number of items in the current set of listitems or treeitems. Not required if all elements in the set are present in the DOM.
         * @see aria-posinset.
         */
        "aria-setsize"?: number | undefined;
        /** Indicates if items in a table or grid are sorted in ascending or descending order. */
        "aria-sort"?: "none" | "ascending" | "descending" | "other" | undefined;
        /** Defines the maximum allowed value for a range widget. */
        "aria-valuemax"?: number | undefined;
        /** Defines the minimum allowed value for a range widget. */
        "aria-valuemin"?: number | undefined;
        /**
         * Defines the current value for a range widget.
         * @see aria-valuetext.
         */
        "aria-valuenow"?: number | undefined;
        /** Defines the human readable text alternative of aria-valuenow for a range widget. */
        "aria-valuetext"?: string | undefined;
    }
    type AriaRole = "alert" | "alertdialog" | "application" | "article" | "banner" | "button" | "cell" | "checkbox" | "columnheader" | "combobox" | "complementary" | "contentinfo" | "definition" | "dialog" | "directory" | "document" | "feed" | "figure" | "form" | "grid" | "gridcell" | "group" | "heading" | "img" | "link" | "list" | "listbox" | "listitem" | "log" | "main" | "marquee" | "math" | "menu" | "menubar" | "menuitem" | "menuitemcheckbox" | "menuitemradio" | "navigation" | "none" | "note" | "option" | "presentation" | "progressbar" | "radio" | "radiogroup" | "region" | "row" | "rowgroup" | "rowheader" | "scrollbar" | "search" | "searchbox" | "separator" | "slider" | "spinbutton" | "status" | "switch" | "tab" | "table" | "tablist" | "tabpanel" | "term" | "textbox" | "timer" | "toolbar" | "tooltip" | "tree" | "treegrid" | "treeitem" | (string & {});
    export interface HTMLAttributes<T> extends AriaAttributes, DOMAttributes<T> {
        defaultChecked?: boolean | undefined;
        defaultValue?: string | number | ReadonlyArray<string> | undefined;
        suppressContentEditableWarning?: boolean | undefined;
        suppressHydrationWarning?: boolean | undefined;
        accessKey?: string | undefined;
        className?: string | undefined;
        contentEditable?: Booleanish | "inherit" | undefined;
        contextMenu?: string | undefined;
        dir?: string | undefined;
        draggable?: Booleanish | undefined;
        hidden?: boolean | undefined;
        id?: string | undefined;
        lang?: string | undefined;
        placeholder?: string | undefined;
        slot?: string | undefined;
        spellCheck?: Booleanish | undefined;
        style?: CSSProperties | undefined;
        tabIndex?: number | undefined;
        title?: string | undefined;
        translate?: "yes" | "no" | undefined;
        radioGroup?: string | undefined;
        role?: AriaRole | undefined;
        about?: string | undefined;
        datatype?: string | undefined;
        inlist?: any;
        prefix?: string | undefined;
        property?: string | undefined;
        resource?: string | undefined;
        typeof?: string | undefined;
        vocab?: string | undefined;
        autoCapitalize?: string | undefined;
        autoCorrect?: string | undefined;
        autoSave?: string | undefined;
        color?: string | undefined;
        itemProp?: string | undefined;
        itemScope?: boolean | undefined;
        itemType?: string | undefined;
        itemID?: string | undefined;
        itemRef?: string | undefined;
        results?: number | undefined;
        security?: string | undefined;
        unselectable?: "on" | "off" | undefined;
        /**
         * Hints at the type of data that might be entered by the user while editing the element or its contents
         * @see https://html.spec.whatwg.org/multipage/interaction.html#input-modalities:-the-inputmode-attribute
         */
        inputMode?: "none" | "text" | "tel" | "url" | "email" | "numeric" | "decimal" | "search" | undefined;
        /**
         * Specify that a standard HTML element should behave like a defined custom built-in element
         * @see https://html.spec.whatwg.org/multipage/custom-elements.html#attr-is
         */
        is?: string | undefined;
    }
    export interface AllHTMLAttributes<T> extends HTMLAttributes<T> {
        accept?: string | undefined;
        acceptCharset?: string | undefined;
        action?: string | undefined;
        allowFullScreen?: boolean | undefined;
        allowTransparency?: boolean | undefined;
        alt?: string | undefined;
        as?: string | undefined;
        async?: boolean | undefined;
        autoComplete?: string | undefined;
        autoFocus?: boolean | undefined;
        autoPlay?: boolean | undefined;
        capture?: boolean | "user" | "environment" | undefined;
        cellPadding?: number | string | undefined;
        cellSpacing?: number | string | undefined;
        charSet?: string | undefined;
        challenge?: string | undefined;
        checked?: boolean | undefined;
        cite?: string | undefined;
        classID?: string | undefined;
        cols?: number | undefined;
        colSpan?: number | undefined;
        content?: string | undefined;
        controls?: boolean | undefined;
        coords?: string | undefined;
        crossOrigin?: string | undefined;
        data?: string | undefined;
        dateTime?: string | undefined;
        default?: boolean | undefined;
        defer?: boolean | undefined;
        disabled?: boolean | undefined;
        download?: any;
        encType?: string | undefined;
        form?: string | undefined;
        formAction?: string | undefined;
        formEncType?: string | undefined;
        formMethod?: string | undefined;
        formNoValidate?: boolean | undefined;
        formTarget?: string | undefined;
        frameBorder?: number | string | undefined;
        headers?: string | undefined;
        height?: number | string | undefined;
        high?: number | undefined;
        href?: string | undefined;
        hrefLang?: string | undefined;
        htmlFor?: string | undefined;
        httpEquiv?: string | undefined;
        integrity?: string | undefined;
        keyParams?: string | undefined;
        keyType?: string | undefined;
        kind?: string | undefined;
        label?: string | undefined;
        list?: string | undefined;
        loop?: boolean | undefined;
        low?: number | undefined;
        manifest?: string | undefined;
        marginHeight?: number | undefined;
        marginWidth?: number | undefined;
        max?: number | string | undefined;
        maxLength?: number | undefined;
        media?: string | undefined;
        mediaGroup?: string | undefined;
        method?: string | undefined;
        min?: number | string | undefined;
        minLength?: number | undefined;
        multiple?: boolean | undefined;
        muted?: boolean | undefined;
        name?: string | undefined;
        nonce?: string | undefined;
        noValidate?: boolean | undefined;
        open?: boolean | undefined;
        optimum?: number | undefined;
        pattern?: string | undefined;
        placeholder?: string | undefined;
        playsInline?: boolean | undefined;
        poster?: string | undefined;
        preload?: string | undefined;
        readOnly?: boolean | undefined;
        rel?: string | undefined;
        required?: boolean | undefined;
        reversed?: boolean | undefined;
        rows?: number | undefined;
        rowSpan?: number | undefined;
        sandbox?: string | undefined;
        scope?: string | undefined;
        scoped?: boolean | undefined;
        scrolling?: string | undefined;
        seamless?: boolean | undefined;
        selected?: boolean | undefined;
        shape?: string | undefined;
        size?: number | undefined;
        sizes?: string | undefined;
        span?: number | undefined;
        src?: string | undefined;
        srcDoc?: string | undefined;
        srcLang?: string | undefined;
        srcSet?: string | undefined;
        start?: number | undefined;
        step?: number | string | undefined;
        summary?: string | undefined;
        target?: string | undefined;
        type?: string | undefined;
        useMap?: string | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
        width?: number | string | undefined;
        wmode?: string | undefined;
        wrap?: string | undefined;
    }
    type HTMLAttributeReferrerPolicy = "" | "no-referrer" | "no-referrer-when-downgrade" | "origin" | "origin-when-cross-origin" | "same-origin" | "strict-origin" | "strict-origin-when-cross-origin" | "unsafe-url";
    type HTMLAttributeAnchorTarget = "_self" | "_blank" | "_parent" | "_top" | (string & {});
    export interface AnchorHTMLAttributes<T> extends HTMLAttributes<T> {
        download?: any;
        href?: string | undefined;
        hrefLang?: string | undefined;
        media?: string | undefined;
        ping?: string | undefined;
        rel?: string | undefined;
        target?: HTMLAttributeAnchorTarget | undefined;
        type?: string | undefined;
        referrerPolicy?: HTMLAttributeReferrerPolicy | undefined;
    }
    export interface AudioHTMLAttributes<T> extends MediaHTMLAttributes<T> {
    }
    export interface AreaHTMLAttributes<T> extends HTMLAttributes<T> {
        alt?: string | undefined;
        coords?: string | undefined;
        download?: any;
        href?: string | undefined;
        hrefLang?: string | undefined;
        media?: string | undefined;
        referrerPolicy?: HTMLAttributeReferrerPolicy | undefined;
        rel?: string | undefined;
        shape?: string | undefined;
        target?: string | undefined;
    }
    export interface BaseHTMLAttributes<T> extends HTMLAttributes<T> {
        href?: string | undefined;
        target?: string | undefined;
    }
    export interface BlockquoteHTMLAttributes<T> extends HTMLAttributes<T> {
        cite?: string | undefined;
    }
    export interface ButtonHTMLAttributes<T> extends HTMLAttributes<T> {
        autoFocus?: boolean | undefined;
        disabled?: boolean | undefined;
        form?: string | undefined;
        formAction?: string | undefined;
        formEncType?: string | undefined;
        formMethod?: string | undefined;
        formNoValidate?: boolean | undefined;
        formTarget?: string | undefined;
        name?: string | undefined;
        type?: "submit" | "reset" | "button" | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface CanvasHTMLAttributes<T> extends HTMLAttributes<T> {
        height?: number | string | undefined;
        width?: number | string | undefined;
    }
    export interface ColHTMLAttributes<T> extends HTMLAttributes<T> {
        span?: number | undefined;
        width?: number | string | undefined;
    }
    export interface ColgroupHTMLAttributes<T> extends HTMLAttributes<T> {
        span?: number | undefined;
    }
    export interface DataHTMLAttributes<T> extends HTMLAttributes<T> {
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface DetailsHTMLAttributes<T> extends HTMLAttributes<T> {
        open?: boolean | undefined;
        onToggle?: ZagEventHandler<T> | undefined;
    }
    export interface DelHTMLAttributes<T> extends HTMLAttributes<T> {
        cite?: string | undefined;
        dateTime?: string | undefined;
    }
    export interface DialogHTMLAttributes<T> extends HTMLAttributes<T> {
        onCancel?: ZagEventHandler<T> | undefined;
        onClose?: ZagEventHandler<T> | undefined;
        open?: boolean | undefined;
    }
    export interface EmbedHTMLAttributes<T> extends HTMLAttributes<T> {
        height?: number | string | undefined;
        src?: string | undefined;
        type?: string | undefined;
        width?: number | string | undefined;
    }
    export interface FieldsetHTMLAttributes<T> extends HTMLAttributes<T> {
        disabled?: boolean | undefined;
        form?: string | undefined;
        name?: string | undefined;
    }
    export interface FormHTMLAttributes<T> extends HTMLAttributes<T> {
        acceptCharset?: string | undefined;
        action?: string | undefined;
        autoComplete?: string | undefined;
        encType?: string | undefined;
        method?: string | undefined;
        name?: string | undefined;
        noValidate?: boolean | undefined;
        target?: string | undefined;
    }
    export interface HtmlHTMLAttributes<T> extends HTMLAttributes<T> {
        manifest?: string | undefined;
    }
    export interface IframeHTMLAttributes<T> extends HTMLAttributes<T> {
        allow?: string | undefined;
        allowFullScreen?: boolean | undefined;
        allowTransparency?: boolean | undefined;
        /** @deprecated */
        frameBorder?: number | string | undefined;
        height?: number | string | undefined;
        loading?: "eager" | "lazy" | undefined;
        /** @deprecated */
        marginHeight?: number | undefined;
        /** @deprecated */
        marginWidth?: number | undefined;
        name?: string | undefined;
        referrerPolicy?: HTMLAttributeReferrerPolicy | undefined;
        sandbox?: string | undefined;
        /** @deprecated */
        scrolling?: string | undefined;
        seamless?: boolean | undefined;
        src?: string | undefined;
        srcDoc?: string | undefined;
        width?: number | string | undefined;
    }
    export interface ImgHTMLAttributes<T> extends HTMLAttributes<T> {
        alt?: string | undefined;
        crossOrigin?: "anonymous" | "use-credentials" | "" | undefined;
        decoding?: "async" | "auto" | "sync" | undefined;
        height?: number | string | undefined;
        loading?: "eager" | "lazy" | undefined;
        referrerPolicy?: HTMLAttributeReferrerPolicy | undefined;
        sizes?: string | undefined;
        src?: string | undefined;
        srcSet?: string | undefined;
        useMap?: string | undefined;
        width?: number | string | undefined;
    }
    export interface InsHTMLAttributes<T> extends HTMLAttributes<T> {
        cite?: string | undefined;
        dateTime?: string | undefined;
    }
    type HTMLInputTypeAttribute = "button" | "checkbox" | "color" | "date" | "datetime-local" | "email" | "file" | "hidden" | "image" | "month" | "number" | "password" | "radio" | "range" | "reset" | "search" | "submit" | "tel" | "text" | "time" | "url" | "week" | (string & {});
    export interface InputHTMLAttributes<T> extends HTMLAttributes<T> {
        webkitdirectory?: any;
        accept?: string | undefined;
        alt?: string | undefined;
        autoComplete?: string | undefined;
        autoFocus?: boolean | undefined;
        capture?: boolean | "user" | "environment" | undefined;
        checked?: boolean | undefined;
        crossOrigin?: string | undefined;
        disabled?: boolean | undefined;
        enterKeyHint?: "enter" | "done" | "go" | "next" | "previous" | "search" | "send" | undefined;
        form?: string | undefined;
        formAction?: string | undefined;
        formEncType?: string | undefined;
        formMethod?: string | undefined;
        formNoValidate?: boolean | undefined;
        formTarget?: string | undefined;
        height?: number | string | undefined;
        list?: string | undefined;
        max?: number | string | undefined;
        maxLength?: number | undefined;
        min?: number | string | undefined;
        minLength?: number | undefined;
        multiple?: boolean | undefined;
        name?: string | undefined;
        pattern?: string | undefined;
        placeholder?: string | undefined;
        readOnly?: boolean | undefined;
        required?: boolean | undefined;
        size?: number | undefined;
        src?: string | undefined;
        step?: number | string | undefined;
        type?: HTMLInputTypeAttribute | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
        width?: number | string | undefined;
        onChange?: ChangeEventHandler<T> | undefined;
    }
    export interface KeygenHTMLAttributes<T> extends HTMLAttributes<T> {
        autoFocus?: boolean | undefined;
        challenge?: string | undefined;
        disabled?: boolean | undefined;
        form?: string | undefined;
        keyType?: string | undefined;
        keyParams?: string | undefined;
        name?: string | undefined;
    }
    export interface LabelHTMLAttributes<T> extends HTMLAttributes<T> {
        form?: string | undefined;
        htmlFor?: string | undefined;
    }
    export interface LiHTMLAttributes<T> extends HTMLAttributes<T> {
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface LinkHTMLAttributes<T> extends HTMLAttributes<T> {
        as?: string | undefined;
        crossOrigin?: string | undefined;
        href?: string | undefined;
        hrefLang?: string | undefined;
        integrity?: string | undefined;
        media?: string | undefined;
        imageSrcSet?: string | undefined;
        imageSizes?: string | undefined;
        referrerPolicy?: HTMLAttributeReferrerPolicy | undefined;
        rel?: string | undefined;
        sizes?: string | undefined;
        type?: string | undefined;
        charSet?: string | undefined;
    }
    export interface MapHTMLAttributes<T> extends HTMLAttributes<T> {
        name?: string | undefined;
    }
    export interface MenuHTMLAttributes<T> extends HTMLAttributes<T> {
        type?: string | undefined;
    }
    export interface MediaHTMLAttributes<T> extends HTMLAttributes<T> {
        autoPlay?: boolean | undefined;
        controls?: boolean | undefined;
        controlsList?: string | undefined;
        crossOrigin?: string | undefined;
        loop?: boolean | undefined;
        mediaGroup?: string | undefined;
        muted?: boolean | undefined;
        playsInline?: boolean | undefined;
        preload?: string | undefined;
        src?: string | undefined;
    }
    export interface MetaHTMLAttributes<T> extends HTMLAttributes<T> {
        charSet?: string | undefined;
        content?: string | undefined;
        httpEquiv?: string | undefined;
        name?: string | undefined;
        media?: string | undefined;
    }
    export interface MeterHTMLAttributes<T> extends HTMLAttributes<T> {
        form?: string | undefined;
        high?: number | undefined;
        low?: number | undefined;
        max?: number | string | undefined;
        min?: number | string | undefined;
        optimum?: number | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface QuoteHTMLAttributes<T> extends HTMLAttributes<T> {
        cite?: string | undefined;
    }
    export interface ObjectHTMLAttributes<T> extends HTMLAttributes<T> {
        classID?: string | undefined;
        data?: string | undefined;
        form?: string | undefined;
        height?: number | string | undefined;
        name?: string | undefined;
        type?: string | undefined;
        useMap?: string | undefined;
        width?: number | string | undefined;
        wmode?: string | undefined;
    }
    export interface OlHTMLAttributes<T> extends HTMLAttributes<T> {
        reversed?: boolean | undefined;
        start?: number | undefined;
        type?: "1" | "a" | "A" | "i" | "I" | undefined;
    }
    export interface OptgroupHTMLAttributes<T> extends HTMLAttributes<T> {
        disabled?: boolean | undefined;
        label?: string | undefined;
    }
    export interface OptionHTMLAttributes<T> extends HTMLAttributes<T> {
        disabled?: boolean | undefined;
        label?: string | undefined;
        selected?: boolean | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface OutputHTMLAttributes<T> extends HTMLAttributes<T> {
        form?: string | undefined;
        htmlFor?: string | undefined;
        name?: string | undefined;
    }
    export interface ParamHTMLAttributes<T> extends HTMLAttributes<T> {
        name?: string | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface ProgressHTMLAttributes<T> extends HTMLAttributes<T> {
        max?: number | string | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
    }
    export interface SlotHTMLAttributes<T> extends HTMLAttributes<T> {
        name?: string | undefined;
    }
    export interface ScriptHTMLAttributes<T> extends HTMLAttributes<T> {
        async?: boolean | undefined;
        /** @deprecated */
        charSet?: string | undefined;
        crossOrigin?: string | undefined;
        defer?: boolean | undefined;
        integrity?: string | undefined;
        noModule?: boolean | undefined;
        nonce?: string | undefined;
        referrerPolicy?: HTMLAttributeReferrerPolicy | undefined;
        src?: string | undefined;
        type?: string | undefined;
    }
    export interface SelectHTMLAttributes<T> extends HTMLAttributes<T> {
        autoComplete?: string | undefined;
        autoFocus?: boolean | undefined;
        disabled?: boolean | undefined;
        form?: string | undefined;
        multiple?: boolean | undefined;
        name?: string | undefined;
        required?: boolean | undefined;
        size?: number | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
        onChange?: ChangeEventHandler<T> | undefined;
    }
    export interface SourceHTMLAttributes<T> extends HTMLAttributes<T> {
        height?: number | string | undefined;
        media?: string | undefined;
        sizes?: string | undefined;
        src?: string | undefined;
        srcSet?: string | undefined;
        type?: string | undefined;
        width?: number | string | undefined;
    }
    export interface StyleHTMLAttributes<T> extends HTMLAttributes<T> {
        media?: string | undefined;
        nonce?: string | undefined;
        scoped?: boolean | undefined;
        type?: string | undefined;
    }
    export interface TableHTMLAttributes<T> extends HTMLAttributes<T> {
        align?: "left" | "center" | "right" | undefined;
        bgcolor?: string | undefined;
        border?: number | undefined;
        cellPadding?: number | string | undefined;
        cellSpacing?: number | string | undefined;
        frame?: boolean | undefined;
        rules?: "none" | "groups" | "rows" | "columns" | "all" | undefined;
        summary?: string | undefined;
        width?: number | string | undefined;
    }
    export interface TextareaHTMLAttributes<T> extends HTMLAttributes<T> {
        autoComplete?: string | undefined;
        autoFocus?: boolean | undefined;
        cols?: number | undefined;
        dirName?: string | undefined;
        disabled?: boolean | undefined;
        form?: string | undefined;
        maxLength?: number | undefined;
        minLength?: number | undefined;
        name?: string | undefined;
        placeholder?: string | undefined;
        readOnly?: boolean | undefined;
        required?: boolean | undefined;
        rows?: number | undefined;
        value?: string | ReadonlyArray<string> | number | undefined;
        wrap?: string | undefined;
        onChange?: ChangeEventHandler<T> | undefined;
    }
    export interface TdHTMLAttributes<T> extends HTMLAttributes<T> {
        align?: "left" | "center" | "right" | "justify" | "char" | undefined;
        colSpan?: number | undefined;
        headers?: string | undefined;
        rowSpan?: number | undefined;
        scope?: string | undefined;
        abbr?: string | undefined;
        height?: number | string | undefined;
        width?: number | string | undefined;
        valign?: "top" | "middle" | "bottom" | "baseline" | undefined;
    }
    export interface ThHTMLAttributes<T> extends HTMLAttributes<T> {
        align?: "left" | "center" | "right" | "justify" | "char" | undefined;
        colSpan?: number | undefined;
        headers?: string | undefined;
        rowSpan?: number | undefined;
        scope?: string | undefined;
        abbr?: string | undefined;
    }
    export interface TimeHTMLAttributes<T> extends HTMLAttributes<T> {
        dateTime?: string | undefined;
    }
    export interface TrackHTMLAttributes<T> extends HTMLAttributes<T> {
        default?: boolean | undefined;
        kind?: string | undefined;
        label?: string | undefined;
        src?: string | undefined;
        srcLang?: string | undefined;
    }
    export interface VideoHTMLAttributes<T> extends MediaHTMLAttributes<T> {
        height?: number | string | undefined;
        playsInline?: boolean | undefined;
        poster?: string | undefined;
        width?: number | string | undefined;
        disablePictureInPicture?: boolean | undefined;
        disableRemotePlayback?: boolean | undefined;
    }
    export interface SVGAttributes<T> extends AriaAttributes, DOMAttributes<T> {
        suppressHydrationWarning?: boolean | undefined;
        className?: string | undefined;
        color?: string | undefined;
        height?: number | string | undefined;
        id?: string | undefined;
        lang?: string | undefined;
        max?: number | string | undefined;
        media?: string | undefined;
        method?: string | undefined;
        min?: number | string | undefined;
        name?: string | undefined;
        style?: CSSProperties | undefined;
        target?: string | undefined;
        type?: string | undefined;
        width?: number | string | undefined;
        role?: AriaRole | undefined;
        tabIndex?: number | undefined;
        crossOrigin?: any;
        accentHeight?: number | string | undefined;
        accumulate?: "none" | "sum" | undefined;
        additive?: "replace" | "sum" | undefined;
        alignmentBaseline?: "auto" | "baseline" | "before-edge" | "text-before-edge" | "middle" | "central" | "after-edge" | "text-after-edge" | "ideographic" | "alphabetic" | "hanging" | "mathematical" | "inherit" | undefined;
        allowReorder?: "no" | "yes" | undefined;
        alphabetic?: number | string | undefined;
        amplitude?: number | string | undefined;
        arabicForm?: "initial" | "medial" | "terminal" | "isolated" | undefined;
        ascent?: number | string | undefined;
        attributeName?: string | undefined;
        attributeType?: string | undefined;
        autoReverse?: Booleanish | undefined;
        azimuth?: number | string | undefined;
        baseFrequency?: number | string | undefined;
        baselineShift?: number | string | undefined;
        baseProfile?: number | string | undefined;
        bbox?: number | string | undefined;
        begin?: number | string | undefined;
        bias?: number | string | undefined;
        by?: number | string | undefined;
        calcMode?: number | string | undefined;
        capHeight?: number | string | undefined;
        clip?: number | string | undefined;
        clipPath?: string | undefined;
        clipPathUnits?: number | string | undefined;
        clipRule?: number | string | undefined;
        colorInterpolation?: number | string | undefined;
        colorInterpolationFilters?: "auto" | "sRGB" | "linearRGB" | "inherit" | undefined;
        colorProfile?: number | string | undefined;
        colorRendering?: number | string | undefined;
        contentScriptType?: number | string | undefined;
        contentStyleType?: number | string | undefined;
        cursor?: number | string | undefined;
        cx?: number | string | undefined;
        cy?: number | string | undefined;
        d?: string | undefined;
        decelerate?: number | string | undefined;
        descent?: number | string | undefined;
        diffuseConstant?: number | string | undefined;
        direction?: number | string | undefined;
        display?: number | string | undefined;
        divisor?: number | string | undefined;
        dominantBaseline?: number | string | undefined;
        dur?: number | string | undefined;
        dx?: number | string | undefined;
        dy?: number | string | undefined;
        edgeMode?: number | string | undefined;
        elevation?: number | string | undefined;
        enableBackground?: number | string | undefined;
        end?: number | string | undefined;
        exponent?: number | string | undefined;
        externalResourcesRequired?: Booleanish | undefined;
        fill?: string | undefined;
        fillOpacity?: number | string | undefined;
        fillRule?: "nonzero" | "evenodd" | "inherit" | undefined;
        filter?: string | undefined;
        filterRes?: number | string | undefined;
        filterUnits?: number | string | undefined;
        floodColor?: number | string | undefined;
        floodOpacity?: number | string | undefined;
        focusable?: Booleanish | "auto" | undefined;
        fontFamily?: string | undefined;
        fontSize?: number | string | undefined;
        fontSizeAdjust?: number | string | undefined;
        fontStretch?: number | string | undefined;
        fontStyle?: number | string | undefined;
        fontVariant?: number | string | undefined;
        fontWeight?: number | string | undefined;
        format?: number | string | undefined;
        fr?: number | string | undefined;
        from?: number | string | undefined;
        fx?: number | string | undefined;
        fy?: number | string | undefined;
        g1?: number | string | undefined;
        g2?: number | string | undefined;
        glyphName?: number | string | undefined;
        glyphOrientationHorizontal?: number | string | undefined;
        glyphOrientationVertical?: number | string | undefined;
        glyphRef?: number | string | undefined;
        gradientTransform?: string | undefined;
        gradientUnits?: string | undefined;
        hanging?: number | string | undefined;
        horizAdvX?: number | string | undefined;
        horizOriginX?: number | string | undefined;
        href?: string | undefined;
        ideographic?: number | string | undefined;
        imageRendering?: number | string | undefined;
        in2?: number | string | undefined;
        in?: string | undefined;
        intercept?: number | string | undefined;
        k1?: number | string | undefined;
        k2?: number | string | undefined;
        k3?: number | string | undefined;
        k4?: number | string | undefined;
        k?: number | string | undefined;
        kernelMatrix?: number | string | undefined;
        kernelUnitLength?: number | string | undefined;
        kerning?: number | string | undefined;
        keyPoints?: number | string | undefined;
        keySplines?: number | string | undefined;
        keyTimes?: number | string | undefined;
        lengthAdjust?: number | string | undefined;
        letterSpacing?: number | string | undefined;
        lightingColor?: number | string | undefined;
        limitingConeAngle?: number | string | undefined;
        local?: number | string | undefined;
        markerEnd?: string | undefined;
        markerHeight?: number | string | undefined;
        markerMid?: string | undefined;
        markerStart?: string | undefined;
        markerUnits?: number | string | undefined;
        markerWidth?: number | string | undefined;
        mask?: string | undefined;
        maskContentUnits?: number | string | undefined;
        maskUnits?: number | string | undefined;
        mathematical?: number | string | undefined;
        mode?: number | string | undefined;
        numOctaves?: number | string | undefined;
        offset?: number | string | undefined;
        opacity?: number | string | undefined;
        operator?: number | string | undefined;
        order?: number | string | undefined;
        orient?: number | string | undefined;
        orientation?: number | string | undefined;
        origin?: number | string | undefined;
        overflow?: number | string | undefined;
        overlinePosition?: number | string | undefined;
        overlineThickness?: number | string | undefined;
        paintOrder?: number | string | undefined;
        panose1?: number | string | undefined;
        path?: string | undefined;
        pathLength?: number | string | undefined;
        patternContentUnits?: string | undefined;
        patternTransform?: number | string | undefined;
        patternUnits?: string | undefined;
        pointerEvents?: number | string | undefined;
        points?: string | undefined;
        pointsAtX?: number | string | undefined;
        pointsAtY?: number | string | undefined;
        pointsAtZ?: number | string | undefined;
        preserveAlpha?: Booleanish | undefined;
        preserveAspectRatio?: string | undefined;
        primitiveUnits?: number | string | undefined;
        r?: number | string | undefined;
        radius?: number | string | undefined;
        refX?: number | string | undefined;
        refY?: number | string | undefined;
        renderingIntent?: number | string | undefined;
        repeatCount?: number | string | undefined;
        repeatDur?: number | string | undefined;
        requiredExtensions?: number | string | undefined;
        requiredFeatures?: number | string | undefined;
        restart?: number | string | undefined;
        result?: string | undefined;
        rotate?: number | string | undefined;
        rx?: number | string | undefined;
        ry?: number | string | undefined;
        scale?: number | string | undefined;
        seed?: number | string | undefined;
        shapeRendering?: number | string | undefined;
        slope?: number | string | undefined;
        spacing?: number | string | undefined;
        specularConstant?: number | string | undefined;
        specularExponent?: number | string | undefined;
        speed?: number | string | undefined;
        spreadMethod?: string | undefined;
        startOffset?: number | string | undefined;
        stdDeviation?: number | string | undefined;
        stemh?: number | string | undefined;
        stemv?: number | string | undefined;
        stitchTiles?: number | string | undefined;
        stopColor?: string | undefined;
        stopOpacity?: number | string | undefined;
        strikethroughPosition?: number | string | undefined;
        strikethroughThickness?: number | string | undefined;
        string?: number | string | undefined;
        stroke?: string | undefined;
        strokeDasharray?: string | number | undefined;
        strokeDashoffset?: string | number | undefined;
        strokeLinecap?: "butt" | "round" | "square" | "inherit" | undefined;
        strokeLinejoin?: "miter" | "round" | "bevel" | "inherit" | undefined;
        strokeMiterlimit?: number | string | undefined;
        strokeOpacity?: number | string | undefined;
        strokeWidth?: number | string | undefined;
        surfaceScale?: number | string | undefined;
        systemLanguage?: number | string | undefined;
        tableValues?: number | string | undefined;
        targetX?: number | string | undefined;
        targetY?: number | string | undefined;
        textAnchor?: string | undefined;
        textDecoration?: number | string | undefined;
        textLength?: number | string | undefined;
        textRendering?: number | string | undefined;
        to?: number | string | undefined;
        transform?: string | undefined;
        u1?: number | string | undefined;
        u2?: number | string | undefined;
        underlinePosition?: number | string | undefined;
        underlineThickness?: number | string | undefined;
        unicode?: number | string | undefined;
        unicodeBidi?: number | string | undefined;
        unicodeRange?: number | string | undefined;
        unitsPerEm?: number | string | undefined;
        vAlphabetic?: number | string | undefined;
        values?: string | undefined;
        vectorEffect?: number | string | undefined;
        version?: string | undefined;
        vertAdvY?: number | string | undefined;
        vertOriginX?: number | string | undefined;
        vertOriginY?: number | string | undefined;
        vHanging?: number | string | undefined;
        vIdeographic?: number | string | undefined;
        viewBox?: string | undefined;
        viewTarget?: number | string | undefined;
        visibility?: number | string | undefined;
        vMathematical?: number | string | undefined;
        widths?: number | string | undefined;
        wordSpacing?: number | string | undefined;
        writingMode?: number | string | undefined;
        x1?: number | string | undefined;
        x2?: number | string | undefined;
        x?: number | string | undefined;
        xChannelSelector?: string | undefined;
        xHeight?: number | string | undefined;
        xlinkActuate?: string | undefined;
        xlinkArcrole?: string | undefined;
        xlinkHref?: string | undefined;
        xlinkRole?: string | undefined;
        xlinkShow?: string | undefined;
        xlinkTitle?: string | undefined;
        xlinkType?: string | undefined;
        xmlBase?: string | undefined;
        xmlLang?: string | undefined;
        xmlns?: string | undefined;
        xmlnsXlink?: string | undefined;
        xmlSpace?: string | undefined;
        y1?: number | string | undefined;
        y2?: number | string | undefined;
        y?: number | string | undefined;
        yChannelSelector?: string | undefined;
        z?: number | string | undefined;
        zoomAndPan?: string | undefined;
    }
    export interface IntrinsicElements {
        a: AnchorHTMLAttributes<HTMLAnchorElement>;
        abbr: HTMLAttributes<HTMLElement>;
        address: HTMLAttributes<HTMLElement>;
        area: AreaHTMLAttributes<HTMLAreaElement>;
        article: HTMLAttributes<HTMLElement>;
        aside: HTMLAttributes<HTMLElement>;
        audio: AudioHTMLAttributes<HTMLAudioElement>;
        b: HTMLAttributes<HTMLElement>;
        base: BaseHTMLAttributes<HTMLBaseElement>;
        bdi: HTMLAttributes<HTMLElement>;
        bdo: HTMLAttributes<HTMLElement>;
        big: HTMLAttributes<HTMLElement>;
        blockquote: BlockquoteHTMLAttributes<HTMLQuoteElement>;
        body: HTMLAttributes<HTMLBodyElement>;
        br: HTMLAttributes<HTMLBRElement>;
        button: ButtonHTMLAttributes<HTMLButtonElement>;
        canvas: CanvasHTMLAttributes<HTMLCanvasElement>;
        caption: HTMLAttributes<HTMLElement>;
        cite: HTMLAttributes<HTMLElement>;
        code: HTMLAttributes<HTMLElement>;
        col: ColHTMLAttributes<HTMLTableColElement>;
        colgroup: ColgroupHTMLAttributes<HTMLTableColElement>;
        data: DataHTMLAttributes<HTMLDataElement>;
        datalist: HTMLAttributes<HTMLDataListElement>;
        dd: HTMLAttributes<HTMLElement>;
        del: DelHTMLAttributes<HTMLModElement>;
        details: DetailsHTMLAttributes<HTMLDetailsElement>;
        dfn: HTMLAttributes<HTMLElement>;
        dialog: DialogHTMLAttributes<HTMLDialogElement>;
        div: HTMLAttributes<HTMLDivElement>;
        dl: HTMLAttributes<HTMLDListElement>;
        dt: HTMLAttributes<HTMLElement>;
        em: HTMLAttributes<HTMLElement>;
        embed: EmbedHTMLAttributes<HTMLEmbedElement>;
        fieldset: FieldsetHTMLAttributes<HTMLFieldSetElement>;
        figcaption: HTMLAttributes<HTMLElement>;
        figure: HTMLAttributes<HTMLElement>;
        footer: HTMLAttributes<HTMLElement>;
        form: FormHTMLAttributes<HTMLFormElement>;
        h1: HTMLAttributes<HTMLHeadingElement>;
        h2: HTMLAttributes<HTMLHeadingElement>;
        h3: HTMLAttributes<HTMLHeadingElement>;
        h4: HTMLAttributes<HTMLHeadingElement>;
        h5: HTMLAttributes<HTMLHeadingElement>;
        h6: HTMLAttributes<HTMLHeadingElement>;
        head: HTMLAttributes<HTMLHeadElement>;
        header: HTMLAttributes<HTMLElement>;
        hgroup: HTMLAttributes<HTMLElement>;
        hr: HTMLAttributes<HTMLHRElement>;
        html: HtmlHTMLAttributes<HTMLHtmlElement>;
        i: HTMLAttributes<HTMLElement>;
        iframe: IframeHTMLAttributes<HTMLIFrameElement>;
        img: ImgHTMLAttributes<HTMLImageElement>;
        input: InputHTMLAttributes<HTMLInputElement>;
        ins: InsHTMLAttributes<HTMLModElement>;
        kbd: HTMLAttributes<HTMLElement>;
        keygen: KeygenHTMLAttributes<HTMLElement>;
        label: LabelHTMLAttributes<HTMLLabelElement>;
        legend: HTMLAttributes<HTMLLegendElement>;
        li: LiHTMLAttributes<HTMLLIElement>;
        link: LinkHTMLAttributes<HTMLLinkElement>;
        main: HTMLAttributes<HTMLElement>;
        map: MapHTMLAttributes<HTMLMapElement>;
        mark: HTMLAttributes<HTMLElement>;
        menu: MenuHTMLAttributes<HTMLElement>;
        menuitem: HTMLAttributes<HTMLElement>;
        meta: MetaHTMLAttributes<HTMLMetaElement>;
        meter: MeterHTMLAttributes<HTMLMeterElement>;
        nav: HTMLAttributes<HTMLElement>;
        noindex: HTMLAttributes<HTMLElement>;
        noscript: HTMLAttributes<HTMLElement>;
        object: ObjectHTMLAttributes<HTMLObjectElement>;
        ol: OlHTMLAttributes<HTMLOListElement>;
        optgroup: OptgroupHTMLAttributes<HTMLOptGroupElement>;
        option: OptionHTMLAttributes<HTMLOptionElement>;
        output: OutputHTMLAttributes<HTMLOutputElement>;
        p: HTMLAttributes<HTMLParagraphElement>;
        param: ParamHTMLAttributes<HTMLParamElement>;
        picture: HTMLAttributes<HTMLElement>;
        pre: HTMLAttributes<HTMLPreElement>;
        progress: ProgressHTMLAttributes<HTMLProgressElement>;
        q: QuoteHTMLAttributes<HTMLQuoteElement>;
        rp: HTMLAttributes<HTMLElement>;
        rt: HTMLAttributes<HTMLElement>;
        ruby: HTMLAttributes<HTMLElement>;
        s: HTMLAttributes<HTMLElement>;
        samp: HTMLAttributes<HTMLElement>;
        slot: SlotHTMLAttributes<HTMLSlotElement>;
        script: ScriptHTMLAttributes<HTMLScriptElement>;
        section: HTMLAttributes<HTMLElement>;
        select: SelectHTMLAttributes<HTMLSelectElement>;
        small: HTMLAttributes<HTMLElement>;
        source: SourceHTMLAttributes<HTMLSourceElement>;
        span: HTMLAttributes<HTMLSpanElement>;
        strong: HTMLAttributes<HTMLElement>;
        style: StyleHTMLAttributes<HTMLStyleElement>;
        sub: HTMLAttributes<HTMLElement>;
        summary: HTMLAttributes<HTMLElement>;
        sup: HTMLAttributes<HTMLElement>;
        table: TableHTMLAttributes<HTMLTableElement>;
        template: HTMLAttributes<HTMLTemplateElement>;
        tbody: HTMLAttributes<HTMLTableSectionElement>;
        td: TdHTMLAttributes<HTMLTableDataCellElement>;
        textarea: TextareaHTMLAttributes<HTMLTextAreaElement>;
        tfoot: HTMLAttributes<HTMLTableSectionElement>;
        th: ThHTMLAttributes<HTMLTableHeaderCellElement>;
        thead: HTMLAttributes<HTMLTableSectionElement>;
        time: TimeHTMLAttributes<HTMLTimeElement>;
        title: HTMLAttributes<HTMLTitleElement>;
        tr: HTMLAttributes<HTMLTableRowElement>;
        track: TrackHTMLAttributes<HTMLTrackElement>;
        u: HTMLAttributes<HTMLElement>;
        ul: HTMLAttributes<HTMLUListElement>;
        var: HTMLAttributes<HTMLElement>;
        video: VideoHTMLAttributes<HTMLVideoElement>;
        g: SVGAttributes<SVGGElement>;
        svg: SVGAttributes<SVGSVGElement>;
        circle: SVGAttributes<SVGCircleElement>;
        path: SVGAttributes<SVGPathElement>;
        rect: SVGAttributes<SVGRectElement>;
        polyline: SVGAttributes<SVGPolylineElement>;
        polygon: SVGAttributes<SVGPolygonElement>;
    }
    export {  };
}

type Dict<T = any> = Record<string, T>;
type DataAttr = {
    "data-selected"?: any | undefined;
    "data-expanded"?: any | undefined;
    "data-highlighted"?: any | undefined;
    "data-readonly"?: any | undefined;
    "data-indeterminate"?: any | undefined;
    "data-invalid"?: any | undefined;
    "data-hover"?: any | undefined;
    "data-active"?: any | undefined;
    "data-focus"?: any | undefined;
    "data-focus-visible"?: any | undefined;
    "data-disabled"?: any | undefined;
    "data-open"?: any | undefined;
    "data-checked"?: any | undefined;
    "data-pressed"?: any | undefined;
    "data-complete"?: any | undefined;
    "data-side"?: any | undefined;
    "data-align"?: any | undefined;
    "data-empty"?: any | undefined;
    "data-placeholder-shown"?: any | undefined;
    "data-half"?: any | undefined;
    "data-scope"?: string | undefined;
    "data-uid"?: string | undefined;
    "data-name"?: string | undefined;
    "data-ownedby"?: string | undefined;
    "data-type"?: string | undefined;
    "data-valuetext"?: string | undefined;
    "data-placement"?: string | undefined;
    "data-controls"?: string | undefined;
    "data-part"?: string | undefined;
    "data-label"?: string | undefined;
    "data-state"?: string | null | undefined;
    "data-value"?: string | number | undefined;
    "data-orientation"?: "horizontal" | "vertical" | undefined;
    "data-count"?: number | undefined;
    "data-index"?: number | undefined;
} & {
    [key in `data-${string}`]?: any | undefined;
};
type PropTypes<T = Dict> = Record<"button" | "label" | "input" | "textarea" | "img" | "output" | "element" | "select" | "rect" | "style" | "circle" | "svg" | "path", T>;
type NormalizeProps<T extends PropTypes> = {
    [K in keyof T]: (props: K extends keyof JSX.IntrinsicElements ? DataAttr & JSX.IntrinsicElements[K] : never) => T[K];
} & {
    element(props: DataAttr & JSX.HTMLAttributes<HTMLElement> & Record<string, any>): T["element"];
    style: JSX.CSSProperties;
};
declare function createNormalizer<T extends PropTypes>(fn: (props: Dict) => Dict): NormalizeProps<T>;

type StrictKeys<K extends (keyof T)[], T> = K extends (keyof T)[] ? [keyof T] extends [K[number]] ? unknown : `Missing required keys: ${Exclude<keyof T, K[number]>}` : never;
declare const createProps: <T extends Record<never, never>>() => <K extends (keyof T)[]>(props: K & StrictKeys<K, T>) => (keyof T)[];

type RequiredBy<T, K extends keyof T> = Partial<Omit<T, K>> & Required<Pick<T, K>>;
type Nullable<T> = T | null;
type NonNullable<T> = T extends null | undefined ? never : T;
type Required<T> = {
    [P in keyof T]-?: NonNullable<T[P]>;
};
type Direction = "ltr" | "rtl";
type Orientation = "horizontal" | "vertical";
type MaybeFn<T> = T | (() => T);
type MaybeElement<T extends HTMLElement = HTMLElement> = Nullable<T>;
interface OrientationProperty {
    /**
     * The orientation of the element.
     * @default "horizontal"
     */
    orientation?: "horizontal" | "vertical" | undefined;
}
interface DirectionProperty {
    /**
     * The document's text/writing direction.
     * @default "ltr"
     */
    dir?: "ltr" | "rtl" | undefined;
}
interface LocaleProperties extends DirectionProperty {
    /**
     * The current locale. Based on the BCP 47 definition.
     * @default "en-US"
     */
    locale?: string | undefined;
}
interface CommonProperties {
    /**
     * The unique identifier of the machine.
     */
    id: string;
    /**
     * A root node to correctly resolve document in custom environments. E.x.: Iframes, Electron.
     */
    getRootNode?: (() => ShadowRoot | Document | Node) | undefined;
}
type Style = JSX.CSSProperties;
type EventKey = "ArrowDown" | "ArrowUp" | "ArrowLeft" | "ArrowRight" | "Space" | "Enter" | "Comma" | "Escape" | "Backspace" | "Delete" | "Home" | "End" | "Tab" | "PageUp" | "PageDown" | (string & {});
type EventKeyMap<T extends HTMLElement = HTMLElement> = {
    [key in EventKey]?: (event: JSX.KeyboardEvent<T>) => void;
};
interface Point {
    x: number;
    y: number;
}
interface Size {
    width: number;
    height: number;
}
interface Rect extends Size {
    y: number;
    x: number;
}

export { type CommonProperties, type Direction, type DirectionProperty, type EventKey, type EventKeyMap, JSX, type LocaleProperties, type MaybeElement, type MaybeFn, type NonNullable, type NormalizeProps, type Nullable, type Orientation, type OrientationProperty, type Point, type PropTypes, type Rect, type Required, type RequiredBy, type Size, type Style, createNormalizer, createProps };
