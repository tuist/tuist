import { ComputedRef, Ref } from 'vue';
import { Direction } from '../shared/types';
import { PrimitiveProps } from '../Primitive';
export type AcceptableValue = string | number | boolean | Record<string, any>;
type ArrayOrWrapped<T> = T extends any[] ? T : Array<T>;
type ComboboxRootContext<T> = {
    modelValue: Ref<T | Array<T>>;
    onValueChange: (val: T) => void;
    searchTerm: Ref<string>;
    multiple: Ref<boolean>;
    disabled: Ref<boolean>;
    open: Ref<boolean>;
    onOpenChange: (value: boolean) => void;
    isUserInputted: Ref<boolean>;
    filteredOptions: Ref<Array<T>>;
    contentId: string;
    contentElement: Ref<HTMLElement | undefined>;
    onContentElementChange: (el: HTMLElement) => void;
    inputElement: Ref<HTMLInputElement | undefined>;
    onInputElementChange: (el: HTMLInputElement) => void;
    onInputNavigation: (dir: 'up' | 'down' | 'home' | 'end') => void;
    onInputEnter: (event: InputEvent) => void;
    onCompositionStart: () => void;
    onCompositionEnd: () => void;
    selectedValue: Ref<T | undefined>;
    selectedElement: ComputedRef<HTMLElement | undefined>;
    onSelectedValueChange: (val: T) => void;
    parentElement: Ref<HTMLElement | undefined>;
};
export declare const injectComboboxRootContext: <T extends ComboboxRootContext<AcceptableValue> | null | undefined = ComboboxRootContext<AcceptableValue>>(fallback?: T | undefined) => T extends null ? ComboboxRootContext<AcceptableValue> | null : ComboboxRootContext<AcceptableValue>, provideComboboxRootContext: (contextValue: ComboboxRootContext<AcceptableValue>) => ComboboxRootContext<AcceptableValue>;
export type ComboboxRootEmits<T = AcceptableValue> = {
    /** Event handler called when the value changes. */
    'update:modelValue': [value: T];
    /** Event handler called when the open state of the combobox changes. */
    'update:open': [value: boolean];
    /** Event handler called when the searchTerm of the combobox changes. */
    'update:searchTerm': [value: string];
    /** Event handler called when the highlighted value of the combobox changes */
    'update:selectedValue': [value: T | undefined];
};
export interface ComboboxRootProps<T = AcceptableValue> extends PrimitiveProps {
    /** The controlled value of the Combobox. Can be binded with with `v-model`. */
    modelValue?: T | Array<T>;
    /** The value of the combobox when initially rendered. Use when you do not need to control the state of the Combobox */
    defaultValue?: T | Array<T>;
    /** The controlled open state of the Combobox. Can be binded with with `v-model:open`. */
    open?: boolean;
    /** The open state of the combobox when it is initially rendered. <br> Use when you do not need to control its open state. */
    defaultOpen?: boolean;
    /** The controlled search term of the Combobox. Can be binded with with v-model:searchTerm. */
    searchTerm?: string;
    /** The current highlighted value of the COmbobox. Can be binded with `v-model:selectedValue`. */
    selectedValue?: T;
    /** Whether multiple options can be selected or not. */
    multiple?: boolean;
    /** When `true`, prevents the user from interacting with Combobox */
    disabled?: boolean;
    /** The name of the Combobox. Submitted with its owning form as part of a name/value pair. */
    name?: string;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** The custom filter function for filtering `ComboboxItem`. */
    filterFunction?: (val: ArrayOrWrapped<T>, term: string) => ArrayOrWrapped<T>;
    /** The display value of input for selected item. Does not work with `multiple`. */
    displayValue?: (val: T) => string;
    /**
     * Whether to reset the searchTerm when the Combobox input blurred
     * @defaultValue `true`
     */
    resetSearchTermOnBlur?: boolean;
    /**
     * Whether to reset the searchTerm when the Combobox value is selected
     * @defaultValue `true`
     */
    resetSearchTermOnSelect?: boolean;
}
declare const _default: <T extends AcceptableValue = AcceptableValue>(__VLS_props: {
    "onUpdate:open"?: ((value: boolean) => any) | undefined;
    "onUpdate:modelValue"?: ((value: T) => any) | undefined;
    "onUpdate:searchTerm"?: ((value: string) => any) | undefined;
    "onUpdate:selectedValue"?: ((value: T | undefined) => any) | undefined;
    modelValue?: T | T[] | undefined;
    defaultValue?: T | T[] | undefined;
    open?: boolean | undefined;
    defaultOpen?: boolean | undefined;
    searchTerm?: string | undefined;
    selectedValue?: T | undefined;
    multiple?: boolean | undefined;
    disabled?: boolean | undefined;
    name?: string | undefined;
    dir?: Direction | undefined;
    filterFunction?: ((val: ArrayOrWrapped<T>, term: string) => ArrayOrWrapped<T>) | undefined;
    displayValue?: ((val: T) => string) | undefined;
    resetSearchTermOnBlur?: boolean | undefined;
    resetSearchTermOnSelect?: boolean | undefined;
    asChild?: boolean | undefined;
    as?: import('../Primitive').AsTag | import('vue').Component | undefined;
} & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps, __VLS_ctx?: {
    slots: Readonly<{
        default: (props: {
            /** Current open state */
            open: boolean;
            /** Current active value */
            modelValue: T | T[];
        }) => any;
    }> & {
        default: (props: {
            /** Current open state */
            open: boolean;
            /** Current active value */
            modelValue: T | T[];
        }) => any;
    };
    attrs: any;
    emit: ((evt: "update:open", value: boolean) => void) & ((evt: "update:modelValue", value: T) => void) & ((evt: "update:searchTerm", value: string) => void) & ((evt: "update:selectedValue", value: T | undefined) => void);
} | undefined, __VLS_expose?: ((exposed: import('vue').ShallowUnwrapRef<{}>) => void) | undefined, __VLS_setup?: Promise<{
    props: {
        "onUpdate:open"?: ((value: boolean) => any) | undefined;
        "onUpdate:modelValue"?: ((value: T) => any) | undefined;
        "onUpdate:searchTerm"?: ((value: string) => any) | undefined;
        "onUpdate:selectedValue"?: ((value: T | undefined) => any) | undefined;
        modelValue?: T | T[] | undefined;
        defaultValue?: T | T[] | undefined;
        open?: boolean | undefined;
        defaultOpen?: boolean | undefined;
        searchTerm?: string | undefined;
        selectedValue?: T | undefined;
        multiple?: boolean | undefined;
        disabled?: boolean | undefined;
        name?: string | undefined;
        dir?: Direction | undefined;
        filterFunction?: ((val: ArrayOrWrapped<T>, term: string) => ArrayOrWrapped<T>) | undefined;
        displayValue?: ((val: T) => string) | undefined;
        resetSearchTermOnBlur?: boolean | undefined;
        resetSearchTermOnSelect?: boolean | undefined;
        asChild?: boolean | undefined;
        as?: import('../Primitive').AsTag | import('vue').Component | undefined;
    } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
    expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
    attrs: any;
    slots: Readonly<{
        default: (props: {
            /** Current open state */
            open: boolean;
            /** Current active value */
            modelValue: T | T[];
        }) => any;
    }> & {
        default: (props: {
            /** Current open state */
            open: boolean;
            /** Current active value */
            modelValue: T | T[];
        }) => any;
    };
    emit: ((evt: "update:open", value: boolean) => void) & ((evt: "update:modelValue", value: T) => void) & ((evt: "update:searchTerm", value: string) => void) & ((evt: "update:selectedValue", value: T | undefined) => void);
}>) => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}> & {
    __ctx?: {
        props: {
            "onUpdate:open"?: ((value: boolean) => any) | undefined;
            "onUpdate:modelValue"?: ((value: T) => any) | undefined;
            "onUpdate:searchTerm"?: ((value: string) => any) | undefined;
            "onUpdate:selectedValue"?: ((value: T | undefined) => any) | undefined;
            modelValue?: T | T[] | undefined;
            defaultValue?: T | T[] | undefined;
            open?: boolean | undefined;
            defaultOpen?: boolean | undefined;
            searchTerm?: string | undefined;
            selectedValue?: T | undefined;
            multiple?: boolean | undefined;
            disabled?: boolean | undefined;
            name?: string | undefined;
            dir?: Direction | undefined;
            filterFunction?: ((val: ArrayOrWrapped<T>, term: string) => ArrayOrWrapped<T>) | undefined;
            displayValue?: ((val: T) => string) | undefined;
            resetSearchTermOnBlur?: boolean | undefined;
            resetSearchTermOnSelect?: boolean | undefined;
            asChild?: boolean | undefined;
            as?: import('../Primitive').AsTag | import('vue').Component | undefined;
        } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
        expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
        attrs: any;
        slots: Readonly<{
            default: (props: {
                /** Current open state */
                open: boolean;
                /** Current active value */
                modelValue: T | T[];
            }) => any;
        }> & {
            default: (props: {
                /** Current open state */
                open: boolean;
                /** Current active value */
                modelValue: T | T[];
            }) => any;
        };
        emit: ((evt: "update:open", value: boolean) => void) & ((evt: "update:modelValue", value: T) => void) & ((evt: "update:searchTerm", value: string) => void) & ((evt: "update:selectedValue", value: T | undefined) => void);
    } | undefined;
};
export default _default;
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
