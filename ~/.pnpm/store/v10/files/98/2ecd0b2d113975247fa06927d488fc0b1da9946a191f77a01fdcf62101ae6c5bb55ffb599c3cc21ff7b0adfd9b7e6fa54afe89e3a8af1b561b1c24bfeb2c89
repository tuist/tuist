import { InteractOutsideHandlers } from '@zag-js/dismissable';
export { FocusOutsideEvent, InteractOutsideEvent, PointerDownOutsideEvent } from '@zag-js/dismissable';
import * as _zag_js_anatomy from '@zag-js/anatomy';
import { CollectionOptions, ListCollection, CollectionItem } from '@zag-js/collection';
export { CollectionItem, CollectionOptions } from '@zag-js/collection';
import * as _zag_js_core from '@zag-js/core';
import { EventObject, Service, Machine } from '@zag-js/core';
import { RequiredBy, DirectionProperty, CommonProperties, PropTypes, NormalizeProps } from '@zag-js/types';
import { TypeaheadState } from '@zag-js/dom-query';
import { PositioningOptions, Placement } from '@zag-js/popper';
export { PositioningOptions } from '@zag-js/popper';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"content" | "list" | "label" | "root" | "item" | "positioner" | "trigger" | "indicator" | "clearTrigger" | "itemText" | "itemIndicator" | "itemGroup" | "itemGroupLabel" | "control" | "valueText">;

declare const collection: {
    <T extends unknown>(options: CollectionOptions<T>): ListCollection<T>;
    empty(): ListCollection<CollectionItem>;
};

interface ValueChangeDetails<T extends CollectionItem = CollectionItem> {
    value: string[];
    items: T[];
}
interface HighlightChangeDetails<T extends CollectionItem = CollectionItem> {
    highlightedValue: string | null;
    highlightedItem: T | null;
    highlightedIndex: number;
}
interface OpenChangeDetails {
    open: boolean;
}
interface ScrollToIndexDetails {
    index: number;
    immediate?: boolean | undefined;
}
type ElementIds = Partial<{
    root: string;
    content: string;
    control: string;
    trigger: string;
    clearTrigger: string;
    label: string;
    hiddenSelect: string;
    positioner: string;
    item(id: string | number): string;
    itemGroup(id: string | number): string;
    itemGroupLabel(id: string | number): string;
}>;
interface SelectProps<T extends CollectionItem = CollectionItem> extends DirectionProperty, CommonProperties, InteractOutsideHandlers {
    /**
     * The item collection
     */
    collection: ListCollection<T>;
    /**
     * The ids of the elements in the select. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * The `name` attribute of the underlying select.
     */
    name?: string | undefined;
    /**
     * The associate form of the underlying select.
     */
    form?: string | undefined;
    /**
     * Whether the select is disabled
     */
    disabled?: boolean | undefined;
    /**
     * Whether the select is invalid
     */
    invalid?: boolean | undefined;
    /**
     * Whether the select is read-only
     */
    readOnly?: boolean | undefined;
    /**
     * Whether the select is required
     */
    required?: boolean | undefined;
    /**
     * Whether the select should close after an item is selected
     * @default true
     */
    closeOnSelect?: boolean | undefined;
    /**
     * The callback fired when the highlighted item changes.
     */
    onHighlightChange?: ((details: HighlightChangeDetails<T>) => void) | undefined;
    /**
     * The callback fired when the selected item changes.
     */
    onValueChange?: ((details: ValueChangeDetails<T>) => void) | undefined;
    /**
     * Function called when the popup is opened
     */
    onOpenChange?: ((details: OpenChangeDetails) => void) | undefined;
    /**
     * The positioning options of the menu.
     */
    positioning?: PositioningOptions | undefined;
    /**
     * The controlled keys of the selected items
     */
    value?: string[] | undefined;
    /**
     * The initial default value of the select when rendered.
     * Use when you don't need to control the value of the select.
     */
    defaultValue?: string[] | undefined;
    /**
     * The controlled key of the highlighted item
     */
    highlightedValue?: string | null;
    /**
     * The initial value of the highlighted item when opened.
     * Use when you don't need to control the highlighted value of the select.
     */
    defaultHighlightedValue?: string | null | undefined;
    /**
     * Whether to loop the keyboard navigation through the options
     * @default false
     */
    loopFocus?: boolean | undefined;
    /**
     * Whether to allow multiple selection
     */
    multiple?: boolean | undefined;
    /**
     * Whether the select menu is open
     */
    open?: boolean | undefined;
    /**
     * Whether the select's open state is controlled by the user
     */
    defaultOpen?: boolean | undefined;
    /**
     * Function to scroll to a specific index
     */
    scrollToIndexFn?: ((details: ScrollToIndexDetails) => void) | undefined;
    /**
     * Whether the select is a composed with other composite widgets like tabs or combobox
     * @default true
     */
    composite?: boolean | undefined;
    /**
     * Whether the value can be cleared by clicking the selected item.
     *
     * **Note:** this is only applicable for single selection
     */
    deselectable?: boolean | undefined;
}
type PropsWithDefault = "positioning" | "closeOnSelect" | "loopFocus" | "composite" | "collection";
interface SelectSchema<T extends CollectionItem = CollectionItem> {
    state: "idle" | "focused" | "open";
    props: RequiredBy<SelectProps<T>, PropsWithDefault>;
    context: {
        currentPlacement: Placement | undefined;
        value: string[];
        highlightedValue: string | null;
        fieldsetDisabled: boolean;
        highlightedItem: T | null;
        selectedItems: T[];
        valueAsString: string;
    };
    computed: {
        hasSelectedItems: boolean;
        isTypingAhead: boolean;
        isInteractive: boolean;
        isDisabled: boolean;
    };
    refs: {
        typeahead: TypeaheadState;
    };
    action: string;
    guard: string;
    effect: string;
    event: EventObject;
}
type SelectService<T extends CollectionItem = CollectionItem> = Service<SelectSchema<T>>;
type SelectMachine<T extends CollectionItem = CollectionItem> = Machine<SelectSchema<T>>;
interface ItemProps<T extends CollectionItem = CollectionItem> {
    /**
     * The item to render
     */
    item: T;
    /**
     * Whether hovering outside should clear the highlighted state
     */
    persistFocus?: boolean | undefined;
}
interface ItemState {
    /**
     * The underlying value of the item
     */
    value: string;
    /**
     * Whether the item is disabled
     */
    disabled: boolean;
    /**
     * Whether the item is selected
     */
    selected: boolean;
    /**
     * Whether the item is highlighted
     */
    highlighted: boolean;
}
interface ItemGroupProps {
    id: string;
}
interface ItemGroupLabelProps {
    htmlFor: string;
}
interface SelectApi<T extends PropTypes = PropTypes, V extends CollectionItem = CollectionItem> {
    /**
     * Whether the select is focused
     */
    focused: boolean;
    /**
     * Whether the select is open
     */
    open: boolean;
    /**
     * Whether the select value is empty
     */
    empty: boolean;
    /**
     * The value of the highlighted item
     */
    highlightedValue: string | null;
    /**
     * The highlighted item
     */
    highlightedItem: V | null;
    /**
     * Function to highlight a value
     */
    highlightValue(value: string): void;
    /**
     * The selected items
     */
    selectedItems: V[];
    /**
     * Whether there's a selected option
     */
    hasSelectedItems: boolean;
    /**
     * The selected item keys
     */
    value: string[];
    /**
     * The string representation of the selected items
     */
    valueAsString: string;
    /**
     * Function to select a value
     */
    selectValue(value: string): void;
    /**
     * Function to select all values
     */
    selectAll(): void;
    /**
     * Function to set the value of the select
     */
    setValue(value: string[]): void;
    /**
     * Function to clear the value of the select.
     * If a value is provided, it will only clear that value, otherwise, it will clear all values.
     */
    clearValue(value?: string): void;
    /**
     * Function to focus on the select input
     */
    focus(): void;
    /**
     * Returns the state of a select item
     */
    getItemState(props: ItemProps): ItemState;
    /**
     * Function to open or close the select
     */
    setOpen(open: boolean): void;
    /**
     * Function to toggle the select
     */
    collection: ListCollection<V>;
    /**
     * Function to set the positioning options of the select
     */
    reposition(options?: Partial<PositioningOptions>): void;
    /**
     * Whether the select allows multiple selections
     */
    multiple: boolean;
    /**
     * Whether the select is disabled
     */
    disabled: boolean;
    getRootProps(): T["element"];
    getLabelProps(): T["label"];
    getControlProps(): T["element"];
    getTriggerProps(): T["button"];
    getIndicatorProps(): T["element"];
    getClearTriggerProps(): T["button"];
    getValueTextProps(): T["element"];
    getPositionerProps(): T["element"];
    getContentProps(): T["element"];
    getListProps(): T["element"];
    getItemProps(props: ItemProps): T["element"];
    getItemTextProps(props: ItemProps): T["element"];
    getItemIndicatorProps(props: ItemProps): T["element"];
    getItemGroupProps(props: ItemGroupProps): T["element"];
    getItemGroupLabelProps(props: ItemGroupLabelProps): T["element"];
    getHiddenSelectProps(): T["select"];
}

declare function connect<T extends PropTypes, V extends CollectionItem = CollectionItem>(service: Service<SelectSchema<V>>, normalize: NormalizeProps<T>): SelectApi<T, V>;

declare const machine: _zag_js_core.Machine<SelectSchema<any>>;

declare const props: (keyof SelectProps<any>)[];
declare const splitProps: <Props extends Partial<SelectProps<any>>>(props: Props) => [Partial<SelectProps<any>>, Omit<Props, keyof SelectProps<any>>];
declare const itemProps: (keyof ItemProps<any>)[];
declare const splitItemProps: <Props extends ItemProps<any>>(props: Props) => [ItemProps<any>, Omit<Props, keyof ItemProps<any>>];
declare const itemGroupProps: "id"[];
declare const splitItemGroupProps: <Props extends ItemGroupProps>(props: Props) => [ItemGroupProps, Omit<Props, "id">];
declare const itemGroupLabelProps: "htmlFor"[];
declare const splitItemGroupLabelProps: <Props extends ItemGroupLabelProps>(props: Props) => [ItemGroupLabelProps, Omit<Props, "htmlFor">];

export { type SelectApi as Api, type ElementIds, type HighlightChangeDetails, type ItemGroupLabelProps, type ItemGroupProps, type ItemProps, type ItemState, type SelectMachine as Machine, type OpenChangeDetails, type SelectProps as Props, type ScrollToIndexDetails, type SelectService as Service, type ValueChangeDetails, anatomy, collection, connect, itemGroupLabelProps, itemGroupProps, itemProps, machine, props, splitItemGroupLabelProps, splitItemGroupProps, splitItemProps, splitProps };
