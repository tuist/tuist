import { DismissableElementHandlers, PersistentElementOptions } from '@zag-js/dismissable';
export { FocusOutsideEvent, InteractOutsideEvent, PointerDownOutsideEvent } from '@zag-js/dismissable';
import * as _zag_js_anatomy from '@zag-js/anatomy';
import { RequiredBy, DirectionProperty, CommonProperties, MaybeElement, PropTypes, NormalizeProps } from '@zag-js/types';
import * as _zag_js_core from '@zag-js/core';
import { Machine, Service } from '@zag-js/core';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"content" | "title" | "trigger" | "backdrop" | "positioner" | "description" | "closeTrigger">;

interface OpenChangeDetails {
    open: boolean;
}
type ElementIds = Partial<{
    trigger: string;
    positioner: string;
    backdrop: string;
    content: string;
    closeTrigger: string;
    title: string;
    description: string;
}>;
interface DialogProps extends DirectionProperty, CommonProperties, DismissableElementHandlers, PersistentElementOptions {
    /**
     * The ids of the elements in the dialog. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * Whether to trap focus inside the dialog when it's opened
     * @default true
     */
    trapFocus?: boolean | undefined;
    /**
     * Whether to prevent scrolling behind the dialog when it's opened
     * @default true
     */
    preventScroll?: boolean | undefined;
    /**
     * Whether to prevent pointer interaction outside the element and hide all content below it
     * @default true
     */
    modal?: boolean | undefined;
    /**
     * Element to receive focus when the dialog is opened
     */
    initialFocusEl?: (() => MaybeElement) | undefined;
    /**
     * Element to receive focus when the dialog is closed
     */
    finalFocusEl?: (() => MaybeElement) | undefined;
    /**
     * Whether to restore focus to the element that had focus before the dialog was opened
     */
    restoreFocus?: boolean | undefined;
    /**
     * Whether to close the dialog when the outside is clicked
     * @default true
     */
    closeOnInteractOutside?: boolean | undefined;
    /**
     * Whether to close the dialog when the escape key is pressed
     * @default true
     */
    closeOnEscape?: boolean | undefined;
    /**
     * Human readable label for the dialog, in event the dialog title is not rendered
     */
    "aria-label"?: string | undefined;
    /**
     * The dialog's role
     * @default "dialog"
     */
    role?: "dialog" | "alertdialog" | undefined;
    /**
     * The controlled open state of the dialog
     */
    open?: boolean | undefined;
    /**
     * The initial open state of the dialog when rendered.
     * Use when you don't need to control the open state of the dialog.
     * @default false
     */
    defaultOpen?: boolean | undefined;
    /**
     * Function to call when the dialog's open state changes
     */
    onOpenChange?: ((details: OpenChangeDetails) => void) | undefined;
}
type PropsWithDefault = "closeOnInteractOutside" | "closeOnEscape" | "role" | "modal" | "trapFocus" | "restoreFocus" | "preventScroll" | "initialFocusEl";
interface DialogSchema {
    props: RequiredBy<DialogProps, PropsWithDefault>;
    state: "open" | "closed";
    context: {
        rendered: {
            title: boolean;
            description: boolean;
        };
    };
    guard: "isOpenControlled";
    effect: "trackDismissableElement" | "preventScroll" | "trapFocus" | "hideContentBelow";
    action: "checkRenderedElements" | "syncZIndex" | "invokeOnClose" | "invokeOnOpen" | "toggleVisibility";
    event: {
        type: "CONTROLLED.OPEN" | "CONTROLLED.CLOSE" | "OPEN" | "CLOSE" | "TOGGLE";
    };
}
type DialogService = Service<DialogSchema>;
type DialogMachine = Machine<DialogSchema>;
interface DialogApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the dialog is open
     */
    open: boolean;
    /**
     * Function to open or close the dialog
     */
    setOpen(open: boolean): void;
    getTriggerProps(): T["button"];
    getBackdropProps(): T["element"];
    getPositionerProps(): T["element"];
    getContentProps(): T["element"];
    getTitleProps(): T["element"];
    getDescriptionProps(): T["element"];
    getCloseTriggerProps(): T["button"];
}

declare function connect<T extends PropTypes>(service: Service<DialogSchema>, normalize: NormalizeProps<T>): DialogApi<T>;

declare const machine: _zag_js_core.Machine<DialogSchema>;

declare const props: (keyof DialogProps)[];
declare const splitProps: <Props extends Partial<DialogProps>>(props: Props) => [Partial<DialogProps>, Omit<Props, keyof DialogProps>];

export { type DialogApi as Api, type ElementIds, type DialogMachine as Machine, type OpenChangeDetails, type DialogProps as Props, type DialogService as Service, anatomy, connect, machine, props, splitProps };
