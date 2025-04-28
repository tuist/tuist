import { Ref } from 'vue';
import { PrimitiveProps } from '../Primitive';
import { Direction, Orientation } from './utils';
export interface RovingFocusGroupProps extends PrimitiveProps {
    /**
     * The orientation of the group.
     * Mainly so arrow navigation is done accordingly (left & right vs. up & down)
     */
    orientation?: Orientation;
    /**
     * The direction of navigation between items.
     */
    dir?: Direction;
    /**
     * Whether keyboard navigation should loop around
     * @defaultValue false
     */
    loop?: boolean;
    currentTabStopId?: string | null;
    defaultCurrentTabStopId?: string;
    preventScrollOnEntryFocus?: boolean;
}
export type RovingFocusGroupEmits = {
    'entryFocus': [event: Event];
    'update:currentTabStopId': [value: string | null | undefined];
};
interface RovingContext {
    orientation: Ref<Orientation | undefined>;
    dir: Ref<Direction>;
    loop: Ref<boolean>;
    currentTabStopId: Ref<string | null | undefined>;
    onItemFocus: (tabStopId: string) => void;
    onItemShiftTab: () => void;
    onFocusableItemAdd: () => void;
    onFocusableItemRemove: () => void;
}
export declare const injectRovingFocusGroupContext: <T extends RovingContext | null | undefined = RovingContext>(fallback?: T | undefined) => T extends null ? RovingContext | null : RovingContext, provideRovingFocusGroupContext: (contextValue: RovingContext) => RovingContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<RovingFocusGroupProps>, {
    loop: boolean;
    orientation: undefined;
    preventScrollOnEntryFocus: boolean;
}>, {
    getItems: () => {
        ref: HTMLElement;
        value?: any;
    }[];
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    entryFocus: (event: Event) => void;
    "update:currentTabStopId": (value: string | null | undefined) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<RovingFocusGroupProps>, {
    loop: boolean;
    orientation: undefined;
    preventScrollOnEntryFocus: boolean;
}>>> & {
    onEntryFocus?: ((event: Event) => any) | undefined;
    "onUpdate:currentTabStopId"?: ((value: string | null | undefined) => any) | undefined;
}, {
    loop: boolean;
    orientation: Orientation;
    preventScrollOnEntryFocus: boolean;
}, {}>, {
    default?(_: {}): any;
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
