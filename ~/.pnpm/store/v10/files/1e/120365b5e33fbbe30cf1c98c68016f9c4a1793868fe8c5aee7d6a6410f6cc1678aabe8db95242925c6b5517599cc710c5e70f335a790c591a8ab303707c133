import { InteractOutsideHandlers } from '@zag-js/interact-outside';
export { FocusOutsideEvent, InteractOutsideEvent, PointerDownOutsideEvent } from '@zag-js/interact-outside';
import * as _zag_js_anatomy from '@zag-js/anatomy';
import * as _zag_js_core from '@zag-js/core';
import { EventObject, Machine, Service } from '@zag-js/core';
import { RequiredBy, DirectionProperty, CommonProperties, PropTypes, NormalizeProps } from '@zag-js/types';
import { LiveRegion } from '@zag-js/live-region';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"label" | "input" | "root" | "item" | "control" | "clearTrigger" | "itemPreview" | "itemInput" | "itemText" | "itemDeleteTrigger">;

interface ValueChangeDetails {
    value: string[];
}
interface InputValueChangeDetails {
    inputValue: string;
}
interface HighlightChangeDetails {
    highlightedValue: string | null;
}
type ValidityState = "rangeOverflow" | "invalidTag";
interface ValidityChangeDetails {
    reason: ValidityState;
}
interface ValidateArgs {
    inputValue: string;
    value: string[];
}
interface IntlTranslations {
    clearTriggerLabel: string;
    deleteTagTriggerLabel(value: string): string;
    tagSelected(value: string): string;
    tagAdded(value: string): string;
    tagsPasted(value: string[]): string;
    tagEdited(value: string): string;
    tagUpdated(value: string): string;
    tagDeleted(value: string): string;
    noTagsSelected?: string | undefined;
    inputLabel?(count: number): string;
}
type Log = {
    type: "add" | "update" | "delete" | "select";
    value: string;
} | {
    type: "clear";
} | {
    type: "paste";
    values: string[];
} | {
    type: "set";
    values: string[];
};
type ElementIds = Partial<{
    root: string;
    input: string;
    hiddenInput: string;
    clearBtn: string;
    label: string;
    control: string;
    item(opts: ItemProps): string;
    itemDeleteTrigger(opts: ItemProps): string;
    itemInput(opts: ItemProps): string;
}>;
interface TagsInputProps extends DirectionProperty, CommonProperties, InteractOutsideHandlers {
    /**
     * The ids of the elements in the tags input. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * Specifies the localized strings that identifies the accessibility elements and their states
     */
    translations?: IntlTranslations | undefined;
    /**
     * The max length of the input.
     */
    maxLength?: number | undefined;
    /**
     * The character that serves has:
     * - event key to trigger the addition of a new tag
     * - character used to split tags when pasting into the input
     *
     * @default ","
     */
    delimiter?: string | RegExp | undefined;
    /**
     * Whether the input should be auto-focused
     */
    autoFocus?: boolean | undefined;
    /**
     * Whether the tags input should be disabled
     */
    disabled?: boolean | undefined;
    /**
     * Whether the tags input should be read-only
     */
    readOnly?: boolean | undefined;
    /**
     * Whether the tags input is invalid
     */
    invalid?: boolean | undefined;
    /**
     * Whether the tags input is required
     */
    required?: boolean | undefined;
    /**
     * Whether a tag can be edited after creation, by pressing `Enter` or double clicking.
     * @default true
     */
    editable?: boolean | undefined;
    /**
     * The controlled tag input's value
     */
    inputValue?: string | undefined;
    /**
     * The initial tag input value when rendered.
     * Use when you don't need to control the tag input value.
     */
    defaultInputValue?: string | undefined;
    /**
     * The controlled tag value
     */
    value?: string[] | undefined;
    /**
     * The initial tag value when rendered.
     * Use when you don't need to control the tag value.
     */
    defaultValue?: string[] | undefined;
    /**
     * Callback fired when the tag values is updated
     */
    onValueChange?: ((details: ValueChangeDetails) => void) | undefined;
    /**
     * Callback fired when the input value is updated
     */
    onInputValueChange?: ((details: InputValueChangeDetails) => void) | undefined;
    /**
     * Callback fired when a tag is highlighted by pointer or keyboard navigation
     */
    onHighlightChange?: ((details: HighlightChangeDetails) => void) | undefined;
    /**
     * Callback fired when the max tag count is reached or the `validateTag` function returns `false`
     */
    onValueInvalid?: ((details: ValidityChangeDetails) => void) | undefined;
    /**
     * Returns a boolean that determines whether a tag can be added.
     * Useful for preventing duplicates or invalid tag values.
     */
    validate?: ((details: ValidateArgs) => boolean) | undefined;
    /**
     * The behavior of the tags input when the input is blurred
     * - `"add"`: add the input value as a new tag
     * - `"clear"`: clear the input value
     */
    blurBehavior?: "clear" | "add" | undefined;
    /**
     * Whether to add a tag when you paste values into the tag input
     * @default false
     */
    addOnPaste?: boolean | undefined;
    /**
     * The max number of tags
     * @default Infinity
     */
    max?: number | undefined;
    /**
     * Whether to allow tags to exceed max. In this case,
     * we'll attach `data-invalid` to the root
     */
    allowOverflow?: boolean | undefined;
    /**
     * The name attribute for the input. Useful for form submissions
     */
    name?: string | undefined;
    /**
     * The associate form of the underlying input element.
     */
    form?: string | undefined;
}
type PropsWithDefault = "dir" | "addOnPaste" | "editable" | "validate" | "delimiter" | "defaultValue" | "translations" | "max";
type ComputedContext = Readonly<{
    valueAsString: string;
    trimmedInputValue: string;
    isInteractive: boolean;
    isAtMax: boolean;
    count: number;
    isOverflowing: boolean;
    isDisabled: boolean;
}>;
interface TagsInputSchema {
    state: "idle" | "navigating:tag" | "focused:input" | "editing:tag";
    tag: "focused" | "editing";
    props: RequiredBy<TagsInputProps, PropsWithDefault>;
    context: {
        value: string[];
        inputValue: string;
        highlightedTagId: string | null;
        editedTagValue: string;
        editedTagId: string | null;
        editedTagIndex: number | null;
        fieldsetDisabled: boolean;
    };
    refs: {
        log: {
            current: Log | null;
            prev: Log | null;
        };
        liveRegion: LiveRegion | null;
    };
    computed: ComputedContext;
    event: EventObject;
    action: string;
    effect: string;
    guard: string;
}
type TagsInputService = Service<TagsInputSchema>;
type TagsInputMachine = Machine<TagsInputSchema>;
interface ItemProps {
    index: string | number;
    value: string;
    disabled?: boolean | undefined;
}
interface ItemState {
    /**
     * The underlying id of the item
     */
    id: string;
    /**
     * Whether the item is being edited
     */
    editing: boolean;
    /**
     * Whether the item is highlighted
     */
    highlighted: boolean;
    /**
     * Whether the item is disabled
     */
    disabled: boolean;
}
interface TagsInputApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the tags are empty
     */
    empty: boolean;
    /**
     * The value of the tags entry input.
     */
    inputValue: string;
    /**
     * The value of the tags as an array of strings.
     */
    value: string[];
    /**
     * The value of the tags as a string.
     */
    valueAsString: string;
    /**
     * The number of the tags.
     */
    count: number;
    /**
     * Whether the tags have reached the max limit.
     */
    atMax: boolean;
    /**
     * Function to set the value of the tags.
     */
    setValue(value: string[]): void;
    /**
     * Function to clear the value of the tags.
     */
    clearValue(id?: string): void;
    /**
     * Function to add a tag to the tags.
     */
    addValue(value: string): void;
    /**
     * Function to set the value of a tag at the given index.
     */
    setValueAtIndex(index: number, value: string): void;
    /**
     * Function to set the value of the tags entry input.
     */
    setInputValue(value: string): void;
    /**
     * Function to clear the value of the tags entry input.
     */
    clearInputValue(): void;
    /**
     * Function to focus the tags entry input.
     */
    focus(): void;
    /**
     * Returns the state of a tag
     */
    getItemState(props: ItemProps): ItemState;
    getRootProps(): T["element"];
    getLabelProps(): T["label"];
    getControlProps(): T["element"];
    getInputProps(): T["input"];
    getHiddenInputProps(): T["input"];
    getClearTriggerProps(): T["button"];
    getItemProps(options: ItemProps): T["element"];
    getItemPreviewProps(options: ItemProps): T["element"];
    getItemTextProps(options: ItemProps): T["element"];
    getItemInputProps(options: ItemProps): T["input"];
    getItemDeleteTriggerProps(options: ItemProps): T["button"];
}

declare function connect<T extends PropTypes>(service: Service<TagsInputSchema>, normalize: NormalizeProps<T>): TagsInputApi<T>;

declare const machine: _zag_js_core.Machine<TagsInputSchema>;

declare const props: (keyof TagsInputProps)[];
declare const splitProps: <Props extends Partial<TagsInputProps>>(props: Props) => [Partial<TagsInputProps>, Omit<Props, keyof TagsInputProps>];
declare const itemProps: (keyof ItemProps)[];
declare const splitItemProps: <Props extends ItemProps>(props: Props) => [ItemProps, Omit<Props, keyof ItemProps>];

export { type TagsInputApi as Api, type ElementIds, type HighlightChangeDetails, type InputValueChangeDetails, type IntlTranslations, type ItemProps, type ItemState, type TagsInputMachine as Machine, type TagsInputProps as Props, type TagsInputService as Service, type ValidateArgs, type ValidityChangeDetails, type ValueChangeDetails, anatomy, connect, itemProps, machine, props, splitItemProps, splitProps };
