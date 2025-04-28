import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { DataOrientation, Direction, StringOrNumber } from '../shared/types';
export interface TabsRootContext {
    modelValue: Ref<StringOrNumber | undefined>;
    changeModelValue: (value: StringOrNumber) => void;
    orientation: Ref<DataOrientation>;
    dir: Ref<Direction>;
    activationMode: 'automatic' | 'manual';
    baseId: string;
    tabsList: Ref<HTMLElement | undefined>;
}
export interface TabsRootProps<T extends StringOrNumber = StringOrNumber> extends PrimitiveProps {
    /**
     * The value of the tab that should be active when initially rendered. Use when you do not need to control the state of the tabs
     */
    defaultValue?: T;
    /**
     * The orientation the tabs are laid out.
     * Mainly so arrow navigation is done accordingly (left & right vs. up & down)
     * @defaultValue horizontal
     */
    orientation?: DataOrientation;
    /**
     * The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode.
     */
    dir?: Direction;
    /**
     * Whether a tab is activated automatically (on focus) or manually (on click).
     * @defaultValue automatic
     */
    activationMode?: 'automatic' | 'manual';
    /** The controlled value of the tab to activate. Can be bind as `v-model`. */
    modelValue?: T;
}
export type TabsRootEmits<T extends StringOrNumber = StringOrNumber> = {
    /** Event handler called when the value changes */
    'update:modelValue': [payload: T];
};
export declare const injectTabsRootContext: <T extends TabsRootContext | null | undefined = TabsRootContext>(fallback?: T | undefined) => T extends null ? TabsRootContext | null : TabsRootContext, provideTabsRootContext: (contextValue: TabsRootContext) => TabsRootContext;
declare const _default: <T extends StringOrNumber = StringOrNumber>(__VLS_props: {
    "onUpdate:modelValue"?: ((payload: T) => any) | undefined;
    defaultValue?: T | undefined;
    orientation?: DataOrientation | undefined;
    dir?: Direction | undefined;
    activationMode?: "manual" | "automatic" | undefined;
    modelValue?: T | undefined;
    asChild?: boolean | undefined;
    as?: import('../Primitive').AsTag | import('vue').Component | undefined;
} & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps, __VLS_ctx?: {
    slots: Readonly<{
        default: (props: {
            /** Current input values */
            modelValue: T | undefined;
        }) => any;
    }> & {
        default: (props: {
            /** Current input values */
            modelValue: T | undefined;
        }) => any;
    };
    attrs: any;
    emit: (evt: "update:modelValue", payload: T) => void;
} | undefined, __VLS_expose?: ((exposed: import('vue').ShallowUnwrapRef<{}>) => void) | undefined, __VLS_setup?: Promise<{
    props: {
        "onUpdate:modelValue"?: ((payload: T) => any) | undefined;
        defaultValue?: T | undefined;
        orientation?: DataOrientation | undefined;
        dir?: Direction | undefined;
        activationMode?: "manual" | "automatic" | undefined;
        modelValue?: T | undefined;
        asChild?: boolean | undefined;
        as?: import('../Primitive').AsTag | import('vue').Component | undefined;
    } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
    expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
    attrs: any;
    slots: Readonly<{
        default: (props: {
            /** Current input values */
            modelValue: T | undefined;
        }) => any;
    }> & {
        default: (props: {
            /** Current input values */
            modelValue: T | undefined;
        }) => any;
    };
    emit: (evt: "update:modelValue", payload: T) => void;
}>) => import('vue').VNode<import('vue').RendererNode, import('vue').RendererElement, {
    [key: string]: any;
}> & {
    __ctx?: {
        props: {
            "onUpdate:modelValue"?: ((payload: T) => any) | undefined;
            defaultValue?: T | undefined;
            orientation?: DataOrientation | undefined;
            dir?: Direction | undefined;
            activationMode?: "manual" | "automatic" | undefined;
            modelValue?: T | undefined;
            asChild?: boolean | undefined;
            as?: import('../Primitive').AsTag | import('vue').Component | undefined;
        } & import('vue').VNodeProps & import('vue').AllowedComponentProps & import('vue').ComponentCustomProps;
        expose(exposed: import('vue').ShallowUnwrapRef<{}>): void;
        attrs: any;
        slots: Readonly<{
            default: (props: {
                /** Current input values */
                modelValue: T | undefined;
            }) => any;
        }> & {
            default: (props: {
                /** Current input values */
                modelValue: T | undefined;
            }) => any;
        };
        emit: (evt: "update:modelValue", payload: T) => void;
    } | undefined;
};
export default _default;
type __VLS_PrettifyLocal<T> = {
    [K in keyof T]: T[K];
} & {};
