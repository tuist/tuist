import { DismissableElementHandlers } from '@zag-js/dismissable';
export { FocusOutsideEvent, InteractOutsideEvent, PointerDownOutsideEvent } from '@zag-js/dismissable';
import * as _zag_js_anatomy from '@zag-js/anatomy';
import * as _zag_js_core from '@zag-js/core';
import { Service, EventObject, Machine } from '@zag-js/core';
import { RequiredBy, DirectionProperty, CommonProperties, PropTypes, NormalizeProps } from '@zag-js/types';
import { TypeaheadState } from '@zag-js/dom-query';
import { PositioningOptions, Placement } from '@zag-js/popper';
export { PositioningOptions } from '@zag-js/popper';
import { Point } from '@zag-js/rect-utils';
export { Point } from '@zag-js/rect-utils';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"content" | "separator" | "item" | "arrow" | "arrowTip" | "contextTrigger" | "indicator" | "itemGroup" | "itemGroupLabel" | "itemIndicator" | "itemText" | "positioner" | "trigger" | "triggerItem">;

interface OpenChangeDetails {
    /**
     * Whether the menu is open
     */
    open: boolean;
}
interface SelectionDetails {
    /**
     * The value of the selected menu item
     */
    value: string;
}
interface HighlightChangeDetails {
    /**
     * The value of the highlighted menu item
     */
    highlightedValue: string | null;
}
interface NavigateDetails {
    value: string | null;
    node: HTMLAnchorElement;
}
type ElementIds = Partial<{
    trigger: string;
    contextTrigger: string;
    content: string;
    groupLabel(id: string): string;
    group(id: string): string;
    positioner: string;
    arrow: string;
}>;
interface MenuProps extends DirectionProperty, CommonProperties, DismissableElementHandlers {
    /**
     * The ids of the elements in the menu. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * The initial highlighted value of the menu item when rendered.
     * Use when you don't need to control the highlighted value of the menu item.
     */
    defaultHighlightedValue?: string | null | undefined;
    /**
     * The controlled highlighted value of the menu item.
     */
    highlightedValue?: string | null | undefined;
    /**
     * Function called when the highlighted menu item changes.
     */
    onHighlightChange?: ((details: HighlightChangeDetails) => void) | undefined;
    /**
     * Function called when a menu item is selected.
     */
    onSelect?: ((details: SelectionDetails) => void) | undefined;
    /**
     * The positioning point for the menu. Can be set by the context menu trigger or the button trigger.
     */
    anchorPoint?: Point | null | undefined;
    /**
     * Whether to loop the keyboard navigation.
     * @default false
     */
    loopFocus?: boolean | undefined;
    /**
     * The options used to dynamically position the menu
     */
    positioning?: PositioningOptions | undefined;
    /**
     * Whether to close the menu when an option is selected
     * @default true
     */
    closeOnSelect?: boolean | undefined;
    /**
     * The accessibility label for the menu
     */
    "aria-label"?: string | undefined;
    /**
     * The controlled open state of the menu
     */
    open?: boolean | undefined;
    /**
     * Function called when the menu opens or closes
     */
    onOpenChange?: ((details: OpenChangeDetails) => void) | undefined;
    /**
     * The initial open state of the menu when rendered.
     * Use when you don't need to control the open state of the menu.
     */
    defaultOpen?: boolean | undefined;
    /**
     * Whether the pressing printable characters should trigger typeahead navigation
     * @default true
     */
    typeahead?: boolean | undefined;
    /**
     * Whether the menu is a composed with other composite widgets like a combobox or tabs
     * @default true
     */
    composite?: boolean | undefined;
    /**
     * Function to navigate to the selected item if it's an anchor element
     */
    navigate?: ((details: NavigateDetails) => void) | undefined;
}
type PropsWithDefault = "closeOnSelect" | "typeahead" | "composite" | "positioning" | "navigate" | "loopFocus";
interface MenuSchema {
    props: RequiredBy<MenuProps, PropsWithDefault>;
    context: {
        highlightedValue: string | null;
        lastHighlightedValue: string | null;
        currentPlacement: Placement | undefined;
        intentPolygon: Point[] | null;
        anchorPoint: Point | null;
        suspendPointer: boolean;
    };
    computed: {
        isSubmenu: boolean;
        isRtl: boolean;
        isTypingAhead: boolean;
        highlightedId: string | null;
    };
    refs: {
        parent: Service<MenuSchema> | null;
        children: Record<string, Service<MenuSchema>>;
        typeaheadState: TypeaheadState;
        positioningOverride: Partial<PositioningOptions>;
    };
    action: string;
    effect: string;
    guard: string;
    event: EventObject;
    state: "idle" | "open" | "closed" | "opening" | "closing" | "opening:contextmenu";
    tag: "open" | "closed";
}
type MenuService = Service<MenuSchema>;
type MenuMachine = Machine<MenuSchema>;
interface Api {
    getItemProps: (opts: ItemProps) => Record<string, any>;
    getTriggerProps(): Record<string, any>;
}
interface ItemProps {
    /**
     * The unique value of the menu item option.
     */
    value: string;
    /**
     * Whether the menu item is disabled
     */
    disabled?: boolean | undefined;
    /**
     * The textual value of the option. Used in typeahead navigation of the menu.
     * If not provided, the text content of the menu item will be used.
     */
    valueText?: string | undefined;
    /**
     * Whether the menu should be closed when the option is selected.
     */
    closeOnSelect?: boolean | undefined;
}
interface ItemListenerProps {
    /**
     * The id of the item. Can be obtained from the `getItemState` function.
     */
    id: string;
    /**
     * Function called when the item is selected
     */
    onSelect?: VoidFunction;
}
interface OptionItemProps extends Partial<ItemProps> {
    /**
     * Whether the option is checked
     */
    checked: boolean;
    /**
     * Whether the option is a radio or a checkbox
     */
    type: "radio" | "checkbox";
    /**
     * The value of the option
     */
    value: string;
    /**
     * Function called when the option state is changed
     */
    onCheckedChange?(checked: boolean): void;
}
interface ItemState {
    /**
     * The unique id of the item
     */
    id: string;
    /**
     * Whether the item is disabled
     */
    disabled: boolean;
    /**
     * Whether the item is highlighted
     */
    highlighted: boolean;
}
interface OptionItemState extends ItemState {
    /**
     * Whether the option item is checked
     */
    checked: boolean;
}
interface ItemGroupProps {
    /**
     * The `id` of the element that provides accessibility label to the option group
     */
    id: string;
}
interface ItemGroupLabelProps {
    /**
     * The `id` of the group this refers to
     */
    htmlFor: string;
}
interface MenuApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the menu is open
     */
    open: boolean;
    /**
     * Function to open or close the menu
     */
    setOpen(open: boolean): void;
    /**
     * The id of the currently highlighted menuitem
     */
    highlightedValue: string | null;
    /**
     * Function to set the highlighted menuitem
     */
    setHighlightedValue(value: string): void;
    /**
     * Function to register a parent menu. This is used for submenus
     */
    setParent(parent: MenuService): void;
    /**
     * Function to register a child menu. This is used for submenus
     */
    setChild(child: MenuService): void;
    /**
     * Function to reposition the popover
     */
    reposition(options?: Partial<PositioningOptions>): void;
    /**
     * Returns the state of the option item
     */
    getOptionItemState(props: OptionItemProps): OptionItemState;
    /**
     * Returns the state of the menu item
     */
    getItemState(props: ItemProps): ItemState;
    /**
     * Setup the custom event listener for item selection event
     */
    addItemListener(props: ItemListenerProps): VoidFunction | undefined;
    getContextTriggerProps(): T["element"];
    getTriggerItemProps<A extends Api>(childApi: A): T["element"];
    getTriggerProps(): T["button"];
    getIndicatorProps(): T["element"];
    getPositionerProps(): T["element"];
    getArrowProps(): T["element"];
    getArrowTipProps(): T["element"];
    getContentProps(): T["element"];
    getSeparatorProps(): T["element"];
    getItemProps(options: ItemProps): T["element"];
    getOptionItemProps(option: OptionItemProps): T["element"];
    getItemIndicatorProps(option: OptionItemProps): T["element"];
    getItemTextProps(option: OptionItemProps): T["element"];
    getItemGroupLabelProps(options: ItemGroupLabelProps): T["element"];
    getItemGroupProps(options: ItemGroupProps): T["element"];
}

declare function connect<T extends PropTypes>(service: Service<MenuSchema>, normalize: NormalizeProps<T>): MenuApi<T>;

declare const machine: _zag_js_core.Machine<MenuSchema>;

declare const props: (keyof MenuProps)[];
declare const splitProps: <Props extends Partial<MenuProps>>(props: Props) => [Partial<MenuProps>, Omit<Props, keyof MenuProps>];
declare const itemProps: (keyof ItemProps)[];
declare const splitItemProps: <Props extends ItemProps>(props: Props) => [ItemProps, Omit<Props, keyof ItemProps>];
declare const itemGroupLabelProps: "htmlFor"[];
declare const splitItemGroupLabelProps: <Props extends ItemGroupLabelProps>(props: Props) => [ItemGroupLabelProps, Omit<Props, "htmlFor">];
declare const itemGroupProps: "id"[];
declare const splitItemGroupProps: <Props extends ItemGroupProps>(props: Props) => [ItemGroupProps, Omit<Props, "id">];
declare const optionItemProps: (keyof OptionItemProps)[];
declare const splitOptionItemProps: <Props extends OptionItemProps>(props: Props) => [OptionItemProps, Omit<Props, keyof OptionItemProps>];

export { type MenuApi as Api, type HighlightChangeDetails, type ItemGroupLabelProps, type ItemGroupProps, type ItemListenerProps, type ItemProps, type ItemState, type MenuMachine as Machine, type NavigateDetails, type OpenChangeDetails, type OptionItemProps, type OptionItemState, type MenuProps as Props, type SelectionDetails, type MenuService as Service, anatomy, connect, itemGroupLabelProps, itemGroupProps, itemProps, machine, optionItemProps, props, splitItemGroupLabelProps, splitItemGroupProps, splitItemProps, splitOptionItemProps, splitProps };
