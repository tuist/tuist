import * as _zag_js_anatomy from '@zag-js/anatomy';
import { RequiredBy, DirectionProperty, CommonProperties, PropTypes, NormalizeProps } from '@zag-js/types';
import * as _zag_js_core from '@zag-js/core';
import { EventObject, Machine, Service } from '@zag-js/core';

declare const anatomy: _zag_js_anatomy.AnatomyInstance<"root" | "label" | "control" | "indicator">;

type CheckedState = boolean | "indeterminate";
interface CheckedChangeDetails {
    checked: CheckedState;
}
type ElementIds = Partial<{
    root: string;
    hiddenInput: string;
    control: string;
    label: string;
}>;
interface CheckboxProps extends DirectionProperty, CommonProperties {
    /**
     * The ids of the elements in the checkbox. Useful for composition.
     */
    ids?: ElementIds | undefined;
    /**
     * Whether the checkbox is disabled
     */
    disabled?: boolean | undefined;
    /**
     * Whether the checkbox is invalid
     */
    invalid?: boolean | undefined;
    /**
     * Whether the checkbox is required
     */
    required?: boolean | undefined;
    /**
     * The controlled checked state of the checkbox
     */
    checked?: CheckedState | undefined;
    /**
     * The initial checked state of the checkbox when rendered.
     * Use when you don't need to control the checked state of the checkbox.
     */
    defaultChecked?: CheckedState | undefined;
    /**
     * Whether the checkbox is read-only
     */
    readOnly?: boolean | undefined;
    /**
     * The callback invoked when the checked state changes.
     */
    onCheckedChange?: ((details: CheckedChangeDetails) => void) | undefined;
    /**
     * The name of the input field in a checkbox.
     * Useful for form submission.
     */
    name?: string | undefined;
    /**
     * The id of the form that the checkbox belongs to.
     */
    form?: string | undefined;
    /**
     * The value of checkbox input. Useful for form submission.
     * @default "on"
     */
    value?: string | undefined;
}
type PropsWithDefault = "value";
interface CheckboxSchema {
    state: "ready";
    props: RequiredBy<CheckboxProps, PropsWithDefault>;
    context: {
        checked: CheckedState;
        active: boolean;
        focused: boolean;
        focusVisible: boolean;
        hovered: boolean;
        fieldsetDisabled: boolean;
    };
    computed: {
        indeterminate: boolean;
        checked: boolean;
        disabled: boolean;
    };
    event: EventObject;
    action: string;
    effect: string;
    guard: string;
}
type CheckboxMachine = Machine<CheckboxSchema>;
interface CheckboxApi<T extends PropTypes = PropTypes> {
    /**
     * Whether the checkbox is checked
     */
    checked: boolean;
    /**
     * Whether the checkbox is disabled
     */
    disabled: boolean | undefined;
    /**
     * Whether the checkbox is indeterminate
     */
    indeterminate: boolean;
    /**
     * Whether the checkbox is focused
     */
    focused: boolean | undefined;
    /**
     *  The checked state of the checkbox
     */
    checkedState: CheckedState;
    /**
     * Function to set the checked state of the checkbox
     */
    setChecked(checked: CheckedState): void;
    /**
     * Function to toggle the checked state of the checkbox
     */
    toggleChecked(): void;
    getRootProps(): T["label"];
    getLabelProps(): T["element"];
    getControlProps(): T["element"];
    getHiddenInputProps(): T["input"];
    getIndicatorProps(): T["element"];
}

declare function connect<T extends PropTypes>(service: Service<CheckboxSchema>, normalize: NormalizeProps<T>): CheckboxApi<T>;

declare const machine: _zag_js_core.Machine<CheckboxSchema>;

declare const props: (keyof CheckboxProps)[];
declare const splitProps: <Props extends CheckboxProps>(props: Props) => [CheckboxProps, Omit<Props, keyof CheckboxProps>];

export { type CheckboxApi as Api, type CheckedChangeDetails, type CheckedState, type ElementIds, type CheckboxMachine as Machine, type CheckboxProps as Props, type CheckboxSchema as Schema, anatomy, connect, machine, props, splitProps };
