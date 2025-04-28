import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Direction } from '../shared/types';
type ActivationMode = 'focus' | 'dblclick' | 'none';
type SubmitMode = 'blur' | 'enter' | 'none' | 'both';
type EditableRootContext = {
    id: Ref<string | undefined>;
    name: Ref<string | undefined>;
    maxLength: Ref<number | undefined>;
    disabled: Ref<boolean>;
    modelValue: Ref<string | undefined>;
    inputValue: Ref<string | undefined>;
    placeholder: Ref<{
        edit: string;
        preview: string;
    }>;
    isEditing: Ref<boolean>;
    submitMode: Ref<SubmitMode>;
    activationMode: Ref<ActivationMode>;
    selectOnFocus: Ref<boolean>;
    edit: () => void;
    cancel: () => void;
    submit: () => void;
    inputRef: Ref<HTMLInputElement | undefined>;
    startWithEditMode: Ref<boolean>;
    isEmpty: Ref<boolean>;
    readonly: Ref<boolean>;
    autoResize: Ref<boolean>;
};
export interface EditableRootProps extends PrimitiveProps {
    /** The default value of the editable field */
    defaultValue?: string;
    /** The value of the editable field */
    modelValue?: string;
    /** The placeholder for the editable field */
    placeholder?: string | {
        edit: string;
        preview: string;
    };
    /** The reading direction of the calendar when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** Whether the editable field is disabled */
    disabled?: boolean;
    /** Whether the editable field is read-only */
    readonly?: boolean;
    /** The activation event of the editable field */
    activationMode?: ActivationMode;
    /** Whether to select the text in the input when it is focused. */
    selectOnFocus?: boolean;
    /** The submit event of the editable field */
    submitMode?: SubmitMode;
    /** Whether to start with the edit mode active */
    startWithEditMode?: boolean;
    /** The maximum number of characters allowed */
    maxLength?: number;
    /** Whether the editable field should auto resize */
    autoResize?: boolean;
    /** The id of the field */
    id?: string;
    /** The name of the field */
    name?: string;
    /** When `true`, indicates that the user must set the value before the owning form can be submitted. */
    required?: boolean;
}
export type EditableRootEmits = {
    /** Event handler called whenever the model value changes */
    'update:modelValue': [value: string];
    /** Event handler called when a value is submitted */
    'submit': [value: string | undefined];
    /** Event handler called when the editable field changes state */
    'update:state': [state: 'edit' | 'submit' | 'cancel'];
};
export declare const injectEditableRootContext: <T extends EditableRootContext | null | undefined = EditableRootContext>(fallback?: T | undefined) => T extends null ? EditableRootContext | null : EditableRootContext, provideEditableRootContext: (contextValue: EditableRootContext) => EditableRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<EditableRootProps>, {
    as: string;
    disabled: boolean;
    submitMode: string;
    activationMode: string;
    selectOnFocus: boolean;
    placeholder: string;
    autoResize: boolean;
    required: boolean;
}>, {
    /** Function to submit the value of the editable */
    submit: () => void;
    /** Function to cancel the value of the editable */
    cancel: () => void;
    /** Function to set the editable in edit mode */
    edit: () => void;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    submit: (value: string | undefined) => void;
    "update:modelValue": (value: string) => void;
    "update:state": (state: "cancel" | "submit" | "edit") => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<EditableRootProps>, {
    as: string;
    disabled: boolean;
    submitMode: string;
    activationMode: string;
    selectOnFocus: boolean;
    placeholder: string;
    autoResize: boolean;
    required: boolean;
}>>> & {
    onSubmit?: ((value: string | undefined) => any) | undefined;
    "onUpdate:modelValue"?: ((value: string) => any) | undefined;
    "onUpdate:state"?: ((state: "cancel" | "submit" | "edit") => any) | undefined;
}, {
    disabled: boolean;
    as: import('../Primitive').AsTag | import('vue').Component;
    required: boolean;
    placeholder: string | {
        edit: string;
        preview: string;
    };
    activationMode: ActivationMode;
    selectOnFocus: boolean;
    submitMode: SubmitMode;
    autoResize: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Whether the editable field is in edit mode */
        isEditing: boolean;
        /** The value of the editable field */
        modelValue: string | undefined;
        /** Whether the editable field is empty */
        isEmpty: boolean;
        /** Function to submit the value of the editable */
        submit: () => void;
        /** Function to cancel the value of the editable */
        cancel: () => void;
        /** Function to set the editable in edit mode */
        edit: () => void;
    }) => any;
}> & {
    default: (props: {
        /** Whether the editable field is in edit mode */
        isEditing: boolean;
        /** The value of the editable field */
        modelValue: string | undefined;
        /** Whether the editable field is empty */
        isEmpty: boolean;
        /** Function to submit the value of the editable */
        submit: () => void;
        /** Function to cancel the value of the editable */
        cancel: () => void;
        /** Function to set the editable in edit mode */
        edit: () => void;
    }) => any;
}>;
export default _default;
type __VLS_WithDefaults<P, D> = {
    [K in keyof Pick<P, keyof P>]: K extends keyof D ? __VLS_PrettifyLocal<P[K] & {
        default: D[K];
    }> : P[K];
};
type __VLS_NonUndefinedable<T> = T extends undefined ? never : T;
type __VLS_TypePropsToOption<T> = {
    [K in keyof T]-?: {} extends Pick<T, K> ? {
        type: import('vue').PropType<__VLS_NonUndefinedable<T[K]>>;
    } : {
        type: import('vue').PropType<T[K]>;
        required: true;
    };
};
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
