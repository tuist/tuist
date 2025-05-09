import { PrimitiveProps } from '../Primitive';
import { PopperContentProps } from '../Popper';
export type TooltipContentImplEmits = {
    /** Event handler called when focus moves to the destructive action after opening. It can be prevented by calling `event.preventDefault` */
    escapeKeyDown: [event: KeyboardEvent];
    /** Event handler called when a pointer event occurs outside the bounds of the component. It can be prevented by calling `event.preventDefault`. */
    pointerDownOutside: [event: Event];
};
export interface TooltipContentImplProps extends PrimitiveProps, Pick<PopperContentProps, 'side' | 'sideOffset' | 'align' | 'alignOffset' | 'avoidCollisions' | 'collisionBoundary' | 'collisionPadding' | 'arrowPadding' | 'sticky' | 'hideWhenDetached'> {
    /**
     * By default, screenreaders will announce the content inside
     * the component. If this is not descriptive enough, or you have
     * content that cannot be announced, use aria-label as a more
     * descriptive label.
     *
     * @defaultValue String
     */
    ariaLabel?: string;
}
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<TooltipContentImplProps>, {
    side: string;
    sideOffset: number;
    align: string;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    arrowPadding: number;
    sticky: string;
    hideWhenDetached: boolean;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    escapeKeyDown: (event: KeyboardEvent) => void;
    pointerDownOutside: (event: Event) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<TooltipContentImplProps>, {
    side: string;
    sideOffset: number;
    align: string;
    avoidCollisions: boolean;
    collisionBoundary: () => never[];
    collisionPadding: number;
    arrowPadding: number;
    sticky: string;
    hideWhenDetached: boolean;
}>>> & {
    onEscapeKeyDown?: ((event: KeyboardEvent) => any) | undefined;
    onPointerDownOutside?: ((event: Event) => any) | undefined;
}, {
    side: "right" | "left" | "top" | "bottom";
    align: "center" | "end" | "start";
    sticky: "partial" | "always";
    sideOffset: number;
    avoidCollisions: boolean;
    collisionBoundary: Element | (Element | null)[] | null;
    collisionPadding: number | Partial<Record<"right" | "left" | "top" | "bottom", number>>;
    arrowPadding: number;
    hideWhenDetached: boolean;
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
