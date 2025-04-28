import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Direction, Orientation } from './utils';
export interface NavigationMenuRootProps extends PrimitiveProps {
    /** The controlled value of the menu item to activate. Can be used as `v-model`. */
    modelValue?: string;
    /**
     * The value of the menu item that should be active when initially rendered.
     *
     * Use when you do not need to control the value state.
     */
    defaultValue?: string;
    /**
     * The reading direction of the combobox when applicable.
     *
     *  If omitted, inherits globally from `ConfigProvider` or assumes LTR (left-to-right) reading mode.
     */
    dir?: Direction;
    /** The orientation of the menu. */
    orientation?: Orientation;
    /**
     * The duration from when the pointer enters the trigger until the tooltip gets opened.
     * @defaultValue 200
     */
    delayDuration?: number;
    /**
     * How much time a user has to enter another trigger without incurring a delay again.
     * @defaultValue 300
     */
    skipDelayDuration?: number;
    /**
     * If `true`, menu cannot be open by click on trigger
     * @defaultValue false
     */
    disableClickTrigger?: boolean;
    /**
     * If `true`, menu cannot be open by hover on trigger
     * @defaultValue false
     */
    disableHoverTrigger?: boolean;
}
export type NavigationMenuRootEmits = {
    /** Event handler called when the value changes. */
    'update:modelValue': [value: string];
};
export interface NavigationMenuContext {
    isRootMenu: boolean;
    modelValue: Ref<string>;
    previousValue: Ref<string>;
    baseId: string;
    dir: Ref<Direction>;
    orientation: Orientation;
    disableClickTrigger: Ref<boolean>;
    disableHoverTrigger: Ref<boolean>;
    rootNavigationMenu: Ref<HTMLElement | undefined>;
    indicatorTrack: Ref<HTMLElement | undefined>;
    onIndicatorTrackChange: (indicatorTrack: HTMLElement | undefined) => void;
    viewport: Ref<HTMLElement | undefined>;
    onViewportChange: (viewport: HTMLElement | undefined) => void;
    onTriggerEnter: (itemValue: string) => void;
    onTriggerLeave: () => void;
    onContentEnter: (itemValue: string) => void;
    onContentLeave: () => void;
    onItemSelect: (itemValue: string) => void;
    onItemDismiss: () => void;
}
export declare const injectNavigationMenuContext: <T extends NavigationMenuContext | null | undefined = NavigationMenuContext>(fallback?: T | undefined) => T extends null ? NavigationMenuContext | null : NavigationMenuContext, provideNavigationMenuContext: (contextValue: NavigationMenuContext) => NavigationMenuContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuRootProps>, {
    modelValue: undefined;
    delayDuration: number;
    skipDelayDuration: number;
    orientation: string;
    disableClickTrigger: boolean;
    disableHoverTrigger: boolean;
    as: string;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    "update:modelValue": (value: string) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<NavigationMenuRootProps>, {
    modelValue: undefined;
    delayDuration: number;
    skipDelayDuration: number;
    orientation: string;
    disableClickTrigger: boolean;
    disableHoverTrigger: boolean;
    as: string;
}>>> & {
    "onUpdate:modelValue"?: ((value: string) => any) | undefined;
}, {
    as: import('../Primitive').AsTag | import('vue').Component;
    modelValue: string;
    orientation: Orientation;
    delayDuration: number;
    skipDelayDuration: number;
    disableClickTrigger: boolean;
    disableHoverTrigger: boolean;
}, {}>, Readonly<{
    default: (props: {
        /** Current input values */
        modelValue: string;
    }) => any;
}> & {
    default: (props: {
        /** Current input values */
        modelValue: string;
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
