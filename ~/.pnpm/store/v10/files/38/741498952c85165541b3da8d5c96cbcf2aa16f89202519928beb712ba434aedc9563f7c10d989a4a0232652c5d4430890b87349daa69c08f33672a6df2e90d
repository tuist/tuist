import * as _zag_js_anatomy from '@zag-js/anatomy';
import * as _zag_js_core from '@zag-js/core';
import { EventObject, Service, Machine } from '@zag-js/core';
import { RequiredBy, DirectionProperty, CommonProperties, PropTypes, NormalizeProps } from '@zag-js/types';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"root" | "label" | "input" | "control">;

interface ValueChangeDetails {
    value: string[];
    valueAsString: string;
}
interface ValueInvalidDetails {
    value: string;
    index: number;
}
type IntlTranslations = {
    inputLabel: (index: number, length: number) => string;
};
type ElementIds = Partial<{
    root: string;
    hiddenInput: string;
    label: string;
    control: string;
    input(id: string): string;
}>;
interface PinInputProps extends DirectionProperty, CommonProperties {
    /**
     * The name of the input element. Useful for form submission.
     */
    name?: string | undefined;
    /**
     * The associate form of the underlying input element.
     */
    form?: string | undefined;
    /**
     * The regular expression that the user-entered input value is checked against.
     */
    pattern?: string | undefined;
    /**
     * The ids of the elements in the pin input. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * Whether the inputs are disabled
     */
    disabled?: boolean | undefined;
    /**
     * The placeholder text for the input
     * @default "○"
     */
    placeholder?: string | undefined;
    /**
     * Whether to auto-focus the first input.
     */
    autoFocus?: boolean | undefined;
    /**
     * Whether the pin input is in the invalid state
     */
    invalid?: boolean | undefined;
    /**
     * Whether the pin input is required
     */
    required?: boolean | undefined;
    /**
     * Whether the pin input is in the valid state
     */
    readOnly?: boolean | undefined;
    /**
     * If `true`, the pin input component signals to its fields that they should
     * use `autocomplete="one-time-code"`.
     */
    otp?: boolean | undefined;
    /**
     * The controlled value of the the pin input.
     */
    value?: string[] | undefined;
    /**
     * The initial value of the the pin input when rendered.
     * Use when you don't need to control the value of the pin input.
     */
    defaultValue?: string[] | undefined;
    /**
     * The type of value the pin-input should allow
     * @default "numeric"
     */
    type?: "alphanumeric" | "numeric" | "alphabetic" | undefined;
    /**
     * Function called when all inputs have valid values
     */
    onValueComplete?: ((details: ValueChangeDetails) => void) | undefined;
    /**
     * Function called on input change
     */
    onValueChange?: ((details: ValueChangeDetails) => void) | undefined;
    /**
     * Function called when an invalid value is entered
     */
    onValueInvalid?: ((details: ValueInvalidDetails) => void) | undefined;
    /**
     * If `true`, the input's value will be masked just like `type=password`
     */
    mask?: boolean | undefined;
    /**
     * Whether to blur the input when the value is complete
     */
    blurOnComplete?: boolean | undefined;
    /**
     * Whether to select input value when input is focused
     */
    selectOnFocus?: boolean | undefined;
    /**
     * Specifies the localized strings that identifies the accessibility elements and their states
     */
    translations?: IntlTranslations | undefined;
    /**
     * The number of inputs to render to improve SSR aria attributes.
     * This will be required in next major version.
     */
    count?: number | undefined;
}
type PropsWithDefault = "placeholder" | "otp" | "type" | "defaultValue";
interface PinInputSchema {
    state: "idle" | "focused";
    props: RequiredBy<PinInputProps, PropsWithDefault>;
    context: {
        value: string[];
        focusedIndex: number;
        count: number;
    };
    computed: {
        _value: string[];
        valueLength: number;
        filledValueLength: number;
        isValueComplete: boolean;
        valueAsString: string;
        focusedValue: string;
    };
    event: EventObject;
    action: string;
    effect: string;
    guard: string;
}
type PinInputService = Service<PinInputSchema>;
type PinInputMachine = Machine<PinInputSchema>;
interface InputProps {
    index: number;
}
interface PinInputApi<T extends PropTypes = PropTypes> {
    /**
     * The value of the input as an array of strings.
     */
    value: string[];
    /**
     * The value of the input as a string.
     */
    valueAsString: string;
    /**
     * Whether all inputs are filled.
     */
    complete: boolean;
    /**
     * The number of inputs to render
     */
    count: number;
    /**
     * The array of input values.
     */
    items: number[];
    /**
     * Function to set the value of the inputs.
     */
    setValue(value: string[]): void;
    /**
     * Function to clear the value of the inputs.
     */
    clearValue(): void;
    /**
     * Function to set the value of the input at a specific index.
     */
    setValueAtIndex(index: number, value: string): void;
    /**
     * Function to focus the pin-input. This will focus the first input.
     */
    focus: () => void;
    getRootProps(): T["element"];
    getLabelProps(): T["label"];
    getHiddenInputProps(): T["input"];
    getControlProps(): T["element"];
    getInputProps(props: InputProps): T["input"];
}

declare function connect<T extends PropTypes>(service: Service<PinInputSchema>, normalize: NormalizeProps<T>): PinInputApi<T>;

declare const machine: _zag_js_core.Machine<PinInputSchema>;

declare const props: (keyof PinInputProps)[];
declare const splitProps: <Props extends Partial<PinInputProps>>(props: Props) => [Partial<PinInputProps>, Omit<Props, keyof PinInputProps>];

export { type PinInputApi as Api, type ElementIds, type InputProps, type IntlTranslations, type PinInputMachine as Machine, type PinInputProps as Props, type PinInputService as Service, type ValueChangeDetails, type ValueInvalidDetails, anatomy, connect, machine, props, splitProps };
