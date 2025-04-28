import { ComputedRef, Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { DataOrientation, Direction, SingleOrMultipleProps, SingleOrMultipleType } from '../shared/types';
export interface ToggleGroupRootProps<ValidValue = string | string[], ExplicitType = SingleOrMultipleType> extends PrimitiveProps, SingleOrMultipleProps<ValidValue, ExplicitType> {
    /** When `false`, navigating through the items using arrow keys will be disabled. */
    rovingFocus?: boolean;
    /** When `true`, prevents the user from interacting with the toggle group and all its items. */
    disabled?: boolean;
    /** The orientation of the component, which determines how focus moves: `horizontal` for left/right arrows and `vertical` for up/down arrows. */
    orientation?: DataOrientation;
    /** The reading direction of the combobox when applicable. <br> If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode. */
    dir?: Direction;
    /** When `loop` and `rovingFocus` is `true`, keyboard navigation will loop from last item to first, and vice versa. */
    loop?: boolean;
}
export type ToggleGroupRootEmits = {
    /** Event handler called when the value changes. */
    'update:modelValue': [payload: string | string[]];
};
interface ToggleGroupRootContext {
    isSingle: ComputedRef<boolean>;
    modelValue: Ref<string | string[] | undefined>;
    changeModelValue: (value: string) => void;
    dir?: Ref<Direction>;
    orientation?: DataOrientation;
    loop: Ref<boolean>;
    rovingFocus: Ref<boolean>;
    disabled?: Ref<boolean>;
}
export declare const injectToggleGroupRootContext: <T extends ToggleGroupRootContext | null | undefined = ToggleGroupRootContext>(fallback?: T | undefined) => T extends null ? ToggleGroupRootContext | null : ToggleGroupRootContext, provideToggleGroupRootContext: (contextValue: ToggleGroupRootContext) => ToggleGroupRootContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<ToggleGroupRootProps<string | string[], SingleOrMultipleType>>, {
    loop: boolean;
    rovingFocus: boolean;
    disabled: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (payload: string | string[]) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<ToggleGroupRootProps<string | string[], SingleOrMultipleType>>, {
    loop: boolean;
    rovingFocus: boolean;
    disabled: boolean;
}>>> & {
    "onUpdate:modelValue"?: ((payload: string | string[]) => any) | undefined;
}, {
    disabled: boolean;
    loop: boolean;
    rovingFocus: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current toggle values */
        modelValue: string | string[] | undefined;
    }) => any;
}> & {
    default: (props: {
        /** Current toggle values */
        modelValue: string | string[] | undefined;
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
