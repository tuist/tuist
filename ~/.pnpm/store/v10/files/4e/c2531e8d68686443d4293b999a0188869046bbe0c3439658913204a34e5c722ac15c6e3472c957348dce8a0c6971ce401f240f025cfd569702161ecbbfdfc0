import { Ref } from 'vue';
import { GraceIntent } from './utils';
import { FocusScopeProps } from '../FocusScope';
import { RovingFocusGroupEmits } from '../RovingFocus';
import { DismissableLayerEmits, DismissableLayerProps } from '../DismissableLayer';
import { PopperContentProps } from '../Popper';
export interface MenuContentContext {
    onItemEnter: (event: PointerEvent) => boolean;
    onItemLeave: (event: PointerEvent) => void;
    onTriggerLeave: (event: PointerEvent) => boolean;
    searchRef: Ref<string>;
    pointerGraceTimerRef: Ref<number>;
    onPointerGraceIntentChange: (intent: GraceIntent | null) => void;
}
export declare const injectMenuContentContext: <T extends MenuContentContext | null | undefined = MenuContentContext>(fallback?: T | undefined) => T extends null ? MenuContentContext | null : MenuContentContext, provideMenuContentContext: (contextValue: MenuContentContext) => MenuContentContext;
export interface MenuContentImplPrivateProps {
    /**
     * When `true`, hover/focus/click interactions will be disabled on elements outside
     * the `DismissableLayer`. Users will need to click twice on outside elements to
     * interact with them: once to close the `DismissableLayer`, and again to trigger the element.
     */
    disableOutsidePointerEvents?: DismissableLayerProps['disableOutsidePointerEvents'];
    /**
     * Whether scrolling outside the `MenuContent` should be prevented
     * @defaultValue false
     */
    disableOutsideScroll?: boolean;
    /**
     * Whether focus should be trapped within the `MenuContent`
     * @defaultValue also
     */
    trapFocus?: FocusScopeProps['trapped'];
}
export type MenuContentImplEmits = DismissableLayerEmits & Omit<RovingFocusGroupEmits, 'update:currentTabStopId'> & {
    openAutoFocus: [event: Event];
    /**
     * Event handler called when auto-focusing on close.
     * Can be prevented.
     */
    closeAutoFocus: [event: Event];
};
export interface MenuContentImplProps extends MenuContentImplPrivateProps, Omit<PopperContentProps, 'dir'> {
    /**
     * When `true`, keyboard navigation will loop from last item to first, and vice versa.
     * @defaultValue false
     */
    loop?: boolean;
}
export interface MenuRootContentTypeProps extends Omit<MenuContentImplProps, 'disableOutsidePointerEvents' | 'disableOutsideScroll' | 'trapFocus'> {
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuContentImplProps>, {
    side: "right" | "left" | "top" | "bottom";
    sideOffset: number;
    align: "center" | "end" | "start";
    alignOffset: number;
    arrowPadding: number;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    sticky: "partial" | "always";
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent) => void;
    focusOutside: (event: import('../DismissableLayer').FocusOutsideEvent) => void;
    interactOutside: (event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => void;
    dismiss: () => void;
    openAutoFocus: (event: Event) => void;
    closeAutoFocus: (event: Event) => void;
    entryFocus: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<MenuContentImplProps>, {
    side: "right" | "left" | "top" | "bottom";
    sideOffset: number;
    align: "center" | "end" | "start";
    alignOffset: number;
    arrowPadding: number;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    sticky: "partial" | "always";
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
}>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent) => any) | undefined;
    onFocusOutside?: ((event: import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onInteractOutside?: ((event: import('../DismissableLayer').PointerDownOutsideEvent | import('../DismissableLayer').FocusOutsideEvent) => any) | undefined;
    onDismiss?: (() => any) | undefined;
    onOpenAutoFocus?: ((event: Event) => any) | undefined;
    onCloseAutoFocus?: ((event: Event) => any) | undefined;
    onEntryFocus?: ((event: Event) => any) | undefined;
}, {
    side: "right" | "left" | "top" | "bottom";
    align: "center" | "end" | "start";
    sticky: "partial" | "always";
    sideOffset: number;
    alignOffset: number;
    avoidCollisions: boolean;
    collisionBoundary: Element | (Element | null)[] | null;
    collisionPadding: number | Partial<Record<"right" | "left" | "top" | "bottom", number>>;
    arrowPadding: number;
    hideWhenDetached: boolean;
    updatePositionStrategy: "always" | "optimized";
    prioritizePosition: boolean;
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
