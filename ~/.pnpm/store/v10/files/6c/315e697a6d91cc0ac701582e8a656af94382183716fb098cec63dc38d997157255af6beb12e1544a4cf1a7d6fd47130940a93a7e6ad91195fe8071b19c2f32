import { DismissableElementHandlers, PersistentElementOptions } from '@zag-js/dismissable';
export { FocusOutsideEvent, InteractOutsideEvent, PointerDownOutsideEvent } from '@zag-js/dismissable';
import * as _zag_js_anatomy from '@zag-js/anatomy';
import { RequiredBy, CommonProperties, DirectionProperty, PropTypes, NormalizeProps } from '@zag-js/types';
import * as _zag_js_core from '@zag-js/core';
import { Service, EventObject, Machine } from '@zag-js/core';
import { PositioningOptions, Placement } from '@zag-js/popper';
export { Placement, PositioningOptions } from '@zag-js/popper';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"content" | "title" | "anchor" | "arrow" | "arrowTip" | "trigger" | "indicator" | "positioner" | "description" | "closeTrigger">;

interface OpenChangeDetails {
    open: boolean;
}
type ElementIds = Partial<{
    anchor: string;
    trigger: string;
    content: string;
    title: string;
    description: string;
    closeTrigger: string;
    positioner: string;
    arrow: string;
}>;
interface PopoverProps extends CommonProperties, DirectionProperty, DismissableElementHandlers, PersistentElementOptions {
    /**
     * The ids of the elements in the popover. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * Whether the popover should be modal. When set to `true`:
     * - interaction with outside elements will be disabled
     * - only popover content will be visible to screen readers
     * - scrolling is blocked
     * - focus is trapped within the popover
     *
     * @default false
     */
    modal?: boolean | undefined;
    /**
     * Whether the popover is portalled. This will proxy the tabbing behavior regardless of the DOM position
     * of the popover content.
     *
     * @default true
     */
    portalled?: boolean | undefined;
    /**
     * Whether to automatically set focus on the first focusable
     * content within the popover when opened.
     *
     * @default true
     */
    autoFocus?: boolean | undefined;
    /**
     * The element to focus on when the popover is opened.
     */
    initialFocusEl?: (() => HTMLElement | null) | undefined;
    /**
     * Whether to close the popover when the user clicks outside of the popover.
     * @default true
     */
    closeOnInteractOutside?: boolean | undefined;
    /**
     * Whether to close the popover when the escape key is pressed.
     * @default true
     */
    closeOnEscape?: boolean | undefined;
    /**
     * Function invoked when the popover opens or closes
     */
    onOpenChange?: ((details: OpenChangeDetails) => void) | undefined;
    /**
     * The user provided options used to position the popover content
     */
    positioning?: PositioningOptions | undefined;
    /**
     * The controlled open state of the popover
     */
    open?: boolean | undefined;
    /**
     * The initial open state of the popover when rendered.
     * Use when you don't need to control the open state of the popover.
     */
    defaultOpen?: boolean | undefined;
}
type PropsWithDefault = "closeOnInteractOutside" | "closeOnEscape" | "modal" | "portalled" | "autoFocus" | "positioning";
type ComputedContext = Readonly<{
    /**
     * The computed value of `portalled`
     */
    currentPortalled: boolean;
}>;
interface PrivateContext {
    /**
     * The elements that are rendered on mount
     */
    renderedElements: {
        title: boolean;
        description: boolean;
    };
    /**
     * The computed placement (maybe different from initial placement)
     */
    currentPlacement?: Placement | undefined;
}
interface PopoverSchema {
    props: RequiredBy<PopoverProps, PropsWithDefault>;
    state: "open" | "closed";
    context: PrivateContext;
    computed: ComputedContext;
    event: EventObject;
    action: string;
    effect: string;
    guard: string;
}
type PopoverService = Service<PopoverSchema>;
type PopoverMachine = Machine<PopoverSchema>;
interface PopoverApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the popover is portalled.
     */
    portalled: boolean;
    /**
     * Whether the popover is open
     */
    open: boolean;
    /**
     * Function to open or close the popover
     */
    setOpen(open: boolean): void;
    /**
     * Function to reposition the popover
     */
    reposition(options?: Partial<PositioningOptions>): void;
    getArrowProps(): T["element"];
    getArrowTipProps(): T["element"];
    getAnchorProps(): T["element"];
    getTriggerProps(): T["button"];
    getIndicatorProps(): T["element"];
    getPositionerProps(): T["element"];
    getContentProps(): T["element"];
    getTitleProps(): T["element"];
    getDescriptionProps(): T["element"];
    getCloseTriggerProps(): T["button"];
}

declare function connect<T extends PropTypes>(service: PopoverService, normalize: NormalizeProps<T>): PopoverApi<T>;

declare const machine: _zag_js_core.Machine<PopoverSchema>;

declare const props: (keyof PopoverProps)[];
declare const splitProps: <Props extends Partial<PopoverProps>>(props: Props) => [Partial<PopoverProps>, Omit<Props, keyof PopoverProps>];

export { type PopoverApi as Api, type ElementIds, type PopoverMachine as Machine, type OpenChangeDetails, type PopoverProps as Props, type PopoverService as Service, anatomy, connect, machine, props, splitProps };
