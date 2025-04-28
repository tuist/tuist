import { ComputedRef, Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { DataOrientation, Direction, SingleOrMultipleProps, SingleOrMultipleType } from '../shared/types';
export interface AccordionRootProps<ValidValue = string | string[], ExplicitType = SingleOrMultipleType> extends PrimitiveProps, SingleOrMultipleProps<ValidValue, ExplicitType> {
    /**
     * When type is "single", allows closing content when clicking trigger for an open item.
     * When type is "multiple", this prop has no effect.
     *
     * @defaultValue false
     */
    collapsible?: boolean;
    /**
     * When `true`, prevents the user from interacting with the accordion and all its items
     *
     * @defaultValue false
     */
    disabled?: boolean;
    /**
     * The reading direction of the accordion when applicable. If omitted, assumes LTR (left-to-right) reading mode.
     *
     * @defaultValue "ltr"
     */
    dir?: Direction;
    /**
     * The orientation of the accordion.
     *
     * @defaultValue "vertical"
     */
    orientation?: DataOrientation;
}
export type AccordionRootEmits<T extends SingleOrMultipleType = SingleOrMultipleType> = {
    /**
     * Event handler called when the expanded state of an item changes
     */
    'update:modelValue': [value: (T extends 'single' ? string : string[]) | undefined];
};
export type AccordionRootContext<P extends AccordionRootProps> = {
    disabled: Ref<P['disabled']>;
    direction: Ref<P['dir']>;
    orientation: P['orientation'];
    parentElement: Ref<HTMLElement | undefined>;
    changeModelValue: (value: string) => void;
    isSingle: ComputedRef<boolean>;
    modelValue: Ref<string | undefined | string[]>;
    collapsible: boolean;
};
export declare const injectAccordionRootContext: <T extends AccordionRootContext<AccordionRootProps<string | string[], SingleOrMultipleType>> | null | undefined = AccordionRootContext<AccordionRootProps<string | string[], SingleOrMultipleType>>>(fallback?: T | undefined) => T extends null ? AccordionRootContext<AccordionRootProps<string | string[], SingleOrMultipleType>> | null : AccordionRootContext<AccordionRootProps<string | string[], SingleOrMultipleType>>, provideAccordionRootContext: (contextValue: AccordionRootContext<AccordionRootProps<string | string[], SingleOrMultipleType>>) => AccordionRootContext<AccordionRootProps<string | string[], SingleOrMultipleType>>;
declare const _default: <ValidValue extends string | string[], ExplicitType extends SingleOrMultipleType>(__VLS_props: {
    "onUpdate:modelValue"?: ((value: (ExplicitType extends "single" ? string : string[]) | undefined) => any) | undefined;
    collapsible?: boolean | undefined;
    disabled?: boolean | undefined;
    dir?: Direction | undefined;
    orientation?: DataOrientation | undefined;
    asChild?: boolean | undefined;
    as?: import('../Primitive').AsTag | import('vue').Component | undefined;
    type?: (ValidValue extends string ? "single" : ValidValue extends string[] ? "multiple" : ExplicitType extends "single" ? "single" : ExplicitType extends "multiple" ? "multiple" : never) | undefined;
    modelValue?: ValidValue | undefined;
    defaultValue?: ValidValue | undefined;
} & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps, __VLS_ctx?: {
    slots: Readonly<{
        default: (props: {
            /** Current active value */
            modelValue: string | string[] | undefined;
        }) => any;
    }> & {
        default: (props: {
            /** Current active value */
            modelValue: string | string[] | undefined;
        }) => any;
    };
    attrs: any;
    emit: (evt: "update:modelValue", value: (ExplicitType extends "single" ? string : string[]) | undefined) => void;
} | undefined, __VLS_expose?: ((exposed: import('vue').ShallowUnwrapRef<{}>) => void) | undefined, __VLS_setup?: Promise<{
    props: {
        "onUpdate:modelValue"?: ((value: (ExplicitType extends "single" ? string : string[]) | undefined) => any) | undefined;
        collapsible?: boolean | undefined;
        disabled?: boolean | undefined;
        dir?: Direction | undefined;
        orientation?: DataOrientation | undefined;
        asChild?: boolean | undefined;
        as?: import('../Primitive').AsTag | import('vue').Component | undefined;
        type?: (ValidValue extends string ? "single" : ValidValue extends string[] ? "multiple" : ExplicitType extends "single" ? "single" : ExplicitType extends "multiple" ? "multiple" : never) | undefined;
        modelValue?: ValidValue | undefined;
        defaultValue?: ValidValue | undefined;
    } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
    expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
    attrs: any;
    slots: Readonly<{
        default: (props: {
            /** Current active value */
            modelValue: string | string[] | undefined;
        }) => any;
    }> & {
        default: (props: {
            /** Current active value */
            modelValue: string | string[] | undefined;
        }) => any;
    };
    emit: (evt: "update:modelValue", value: (ExplicitType extends "single" ? string : string[]) | undefined) => void;
}>) => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}> & {
    __ctx?: {
        props: {
            "onUpdate:modelValue"?: ((value: (ExplicitType extends "single" ? string : string[]) | undefined) => any) | undefined;
            collapsible?: boolean | undefined;
            disabled?: boolean | undefined;
            dir?: Direction | undefined;
            orientation?: DataOrientation | undefined;
            asChild?: boolean | undefined;
            as?: import('../Primitive').AsTag | import('vue').Component | undefined;
            type?: (ValidValue extends string ? "single" : ValidValue extends string[] ? "multiple" : ExplicitType extends "single" ? "single" : ExplicitType extends "multiple" ? "multiple" : never) | undefined;
            modelValue?: ValidValue | undefined;
            defaultValue?: ValidValue | undefined;
        } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
        expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
        attrs: any;
        slots: Readonly<{
            default: (props: {
                /** Current active value */
                modelValue: string | string[] | undefined;
            }) => any;
        }> & {
            default: (props: {
                /** Current active value */
                modelValue: string | string[] | undefined;
            }) => any;
        };
        emit: (evt: "update:modelValue", value: (ExplicitType extends "single" ? string : string[]) | undefined) => void;
    } | undefined;
};
export default _default;
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
