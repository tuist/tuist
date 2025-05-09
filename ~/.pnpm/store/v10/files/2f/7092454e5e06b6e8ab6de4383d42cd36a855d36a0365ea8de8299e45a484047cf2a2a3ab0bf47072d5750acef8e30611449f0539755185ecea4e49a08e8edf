import * as _zag_js_anatomy from '@zag-js/anatomy';
import * as _zag_js_core from '@zag-js/core';
import { Machine, Service } from '@zag-js/core';
import { CommonProperties, DirectionProperty, PropTypes, NormalizeProps } from '@zag-js/types';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"root" | "trigger" | "content" | "indicator">;

interface OpenChangeDetails {
    open: boolean;
}
type ElementIds = Partial<{
    root: string;
    content: string;
    trigger: string;
}>;
interface CollapsibleProps extends CommonProperties, DirectionProperty {
    /**
     * The ids of the elements in the collapsible. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * The controlled open state of the collapsible.
     */
    open?: boolean | undefined;
    /**
     * The initial open state of the collapsible when rendered.
     * Use when you don't need to control the open state of the collapsible.
     */
    defaultOpen?: boolean | undefined;
    /**
     * The callback invoked when the open state changes.
     */
    onOpenChange?: ((details: OpenChangeDetails) => void) | undefined;
    /**
     * The callback invoked when the exit animation completes.
     */
    onExitComplete?: VoidFunction | undefined;
    /**
     * Whether the collapsible is disabled.
     */
    disabled?: boolean | undefined;
}
interface CollapsibleSchema {
    state: "open" | "closed" | "closing";
    props: CollapsibleProps;
    context: {
        size: {
            width: number;
            height: number;
        };
        initial: boolean;
    };
    refs: {
        stylesRef: any;
        cleanup: VoidFunction | undefined;
    };
    guard: "isOpenControlled";
    event: {
        type: "controlled.open";
    } | {
        type: "controlled.close";
    } | {
        type: "open";
    } | {
        type: "close";
    } | {
        type: "size.measure";
    } | {
        type: "animation.end";
    };
    action: "setInitial" | "clearInitial" | "cleanupNode" | "measureSize" | "computeSize" | "invokeOnOpen" | "invokeOnClose" | "invokeOnExitComplete" | "toggleVisibility";
    effect: "trackEnterAnimation" | "trackExitAnimation";
}
type CollapsibleService = Service<CollapsibleSchema>;
type CollapsibleMachine = Machine<CollapsibleSchema>;
interface CollapsibleApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the collapsible is open.
     */
    open: boolean;
    /**
     * Whether the collapsible is visible (open or closing)
     */
    visible: boolean;
    /**
     * Whether the collapsible is disabled
     */
    disabled: boolean;
    /**
     * Function to open or close the collapsible.
     */
    setOpen(open: boolean): void;
    /**
     * Function to measure the size of the content.
     */
    measureSize(): void;
    getRootProps(): T["element"];
    getTriggerProps(): T["button"];
    getContentProps(): T["element"];
    getIndicatorProps(): T["element"];
}

declare function connect<T extends PropTypes>(service: Service<CollapsibleSchema>, normalize: NormalizeProps<T>): CollapsibleApi<T>;

declare const machine: _zag_js_core.Machine<CollapsibleSchema>;

declare const props: (keyof CollapsibleProps)[];
declare const splitProps: <Props extends Partial<CollapsibleProps>>(props: Props) => [Partial<CollapsibleProps>, Omit<Props, keyof CollapsibleProps>];

export { type CollapsibleApi as Api, type ElementIds, type CollapsibleMachine as Machine, type OpenChangeDetails, type CollapsibleProps as Props, type CollapsibleService as Service, anatomy, connect, machine, props, splitProps };
