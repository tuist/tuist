import { PrimitiveProps } from '../Primitive';
import { Direction } from '../shared/types';
import { Ref } from 'vue';
export type AcceptableInputValue = string | Record<string, any>;
export interface TagsInputRootProps<T = AcceptableInputValue> extends PrimitiveProps {
    /** The controlled value of the tags input. Can be bind as `v-model`. */
    modelValue?: Array<T>;
    /** The value of the tags that should be added. Use when you do not need to control the state of the tags input */
    defaultValue?: Array<T>;
    /** When `true`, allow adding tags on paste. Work in conjunction with delimiter prop. */
    addOnPaste?: boolean;
    /** When `true` allow adding tags on tab keydown */
    addOnTab?: boolean;
    /** When `true` allow adding tags blur input */
    addOnBlur?: boolean;
    /** When `true`, allow duplicated tags. */
    duplicate?: boolean;
    /** When `true`, prevents the user from interacting with the tags input. */
    disabled?: boolean;
    /** The character to trigger the addition of a new tag. Also used to split tags for `@paste` event */
    delimiter?: string;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** Maximum number of tags. */
    max?: number;
    /** When `true`, indicates that the user must add the tags input before the owning form can be submitted. */
    required?: boolean;
    /** The name of the tags input submitted with its owning form as part of a name/value pair. */
    name?: string;
    id?: string;
    /** Convert the input value to the desired type. Mandatory when using objects as values and using `TagsInputInput` */
    convertValue?: (value: string) => T;
    /** Display the value of the tag. Useful when you want to apply modifications to the value like adding a suffix or when using object as values */
    displayValue?: (value: T) => string;
}
export type TagsInputRootEmits<T = AcceptableInputValue> = {
    /** Event handler called when the value changes */
    'update:modelValue': [payload: Array<T>];
    /** Event handler called when the value is invalid */
    'invalid': [payload: T];
};
export interface TagsInputRootContext<T = AcceptableInputValue> {
    modelValue: Ref<Array<T>>;
    onAddValue: (payload: string) => boolean;
    onRemoveValue: (index: number) => void;
    onInputKeydown: (event: KeyboardEvent) => void;
    selectedElement: Ref<HTMLElement | undefined>;
    isInvalidInput: Ref<boolean>;
    addOnPaste: Ref<boolean>;
    addOnTab: Ref<boolean>;
    addOnBlur: Ref<boolean>;
    disabled: Ref<boolean>;
    delimiter: Ref<string>;
    dir: Ref<Direction>;
    max: Ref<number>;
    id: Ref<string | undefined> | undefined;
    displayValue: (value: T) => string;
}
export declare const injectTagsInputRootContext: <T extends TagsInputRootContext<AcceptableInputValue> | null | undefined = TagsInputRootContext<AcceptableInputValue>>(fallback?: T | undefined) => T extends null ? TagsInputRootContext<AcceptableInputValue> | null : TagsInputRootContext<AcceptableInputValue>, provideTagsInputRootContext: (contextValue: TagsInputRootContext<AcceptableInputValue>) => TagsInputRootContext<AcceptableInputValue>;
declare const _default: <T extends AcceptableInputValue = string>(__VLS_props: {
    onInvalid?: ((payload: T) => any) | undefined;
    "onUpdate:modelValue"?: ((payload: T[]) => any) | undefined;
    modelValue?: T[] | undefined;
    defaultValue?: T[] | undefined;
    addOnPaste?: boolean | undefined;
    addOnTab?: boolean | undefined;
    addOnBlur?: boolean | undefined;
    duplicate?: boolean | undefined;
    disabled?: boolean | undefined;
    delimiter?: string | undefined;
    dir?: Direction | undefined;
    max?: number | undefined;
    required?: boolean | undefined;
    name?: string | undefined;
    id?: string | undefined;
    convertValue?: ((value: string) => T) | undefined;
    displayValue?: ((value: T) => string) | undefined;
    asChild?: boolean | undefined;
    as?: import('../Primitive').AsTag | import('vue').Component | undefined;
} & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps, __VLS_ctx?: {
    slots: Readonly<{
        default: (props: {
            /** Current input values */
            modelValue: AcceptableInputValue[];
        }) => any;
    }> & {
        default: (props: {
            /** Current input values */
            modelValue: AcceptableInputValue[];
        }) => any;
    };
    attrs: any;
    emit: ((evt: "invalid", payload: T) => void) & ((evt: "update:modelValue", payload: T[]) => void);
} | undefined, __VLS_expose?: ((exposed: import('vue').ShallowUnwrapRef<{}>) => void) | undefined, __VLS_setup?: Promise<{
    props: {
        onInvalid?: ((payload: T) => any) | undefined;
        "onUpdate:modelValue"?: ((payload: T[]) => any) | undefined;
        modelValue?: T[] | undefined;
        defaultValue?: T[] | undefined;
        addOnPaste?: boolean | undefined;
        addOnTab?: boolean | undefined;
        addOnBlur?: boolean | undefined;
        duplicate?: boolean | undefined;
        disabled?: boolean | undefined;
        delimiter?: string | undefined;
        dir?: Direction | undefined;
        max?: number | undefined;
        required?: boolean | undefined;
        name?: string | undefined;
        id?: string | undefined;
        convertValue?: ((value: string) => T) | undefined;
        displayValue?: ((value: T) => string) | undefined;
        asChild?: boolean | undefined;
        as?: import('../Primitive').AsTag | import('vue').Component | undefined;
    } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
    expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
    attrs: any;
    slots: Readonly<{
        default: (props: {
            /** Current input values */
            modelValue: AcceptableInputValue[];
        }) => any;
    }> & {
        default: (props: {
            /** Current input values */
            modelValue: AcceptableInputValue[];
        }) => any;
    };
    emit: ((evt: "invalid", payload: T) => void) & ((evt: "update:modelValue", payload: T[]) => void);
}>) => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}> & {
    __ctx?: {
        props: {
            onInvalid?: ((payload: T) => any) | undefined;
            "onUpdate:modelValue"?: ((payload: T[]) => any) | undefined;
            modelValue?: T[] | undefined;
            defaultValue?: T[] | undefined;
            addOnPaste?: boolean | undefined;
            addOnTab?: boolean | undefined;
            addOnBlur?: boolean | undefined;
            duplicate?: boolean | undefined;
            disabled?: boolean | undefined;
            delimiter?: string | undefined;
            dir?: Direction | undefined;
            max?: number | undefined;
            required?: boolean | undefined;
            name?: string | undefined;
            id?: string | undefined;
            convertValue?: ((value: string) => T) | undefined;
            displayValue?: ((value: T) => string) | undefined;
            asChild?: boolean | undefined;
            as?: import('../Primitive').AsTag | import('vue').Component | undefined;
        } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
        expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
        attrs: any;
        slots: Readonly<{
            default: (props: {
                /** Current input values */
                modelValue: AcceptableInputValue[];
            }) => any;
        }> & {
            default: (props: {
                /** Current input values */
                modelValue: AcceptableInputValue[];
            }) => any;
        };
        emit: ((evt: "invalid", payload: T) => void) & ((evt: "update:modelValue", payload: T[]) => void);
    } | undefined;
};
export default _default;
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
