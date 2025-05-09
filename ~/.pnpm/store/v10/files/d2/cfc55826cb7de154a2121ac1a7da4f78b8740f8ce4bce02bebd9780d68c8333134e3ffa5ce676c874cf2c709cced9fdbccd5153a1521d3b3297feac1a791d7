import { PointerHitAreaMargins } from './utils/registry';
import { PrimitiveProps } from '../Primitive';
export interface SplitterResizeHandleProps extends PrimitiveProps {
    /** Resize handle id (unique within group); falls back to `useId` when not provided */
    id?: string;
    /** Allow this much margin when determining resizable handle hit detection */
    hitAreaMargins?: PointerHitAreaMargins;
    /** Tabindex for the handle */
    tabindex?: number;
    /** Disable drag handle */
    disabled?: boolean;
}
export type PanelResizeHandleOnDragging = (isDragging: boolean) => void;
export type ResizeHandlerState = 'drag' | 'hover' | 'inactive';
export type SplitterResizeHandleEmits = {
    /** Event handler called when dragging the handler. */
    dragging: [isDragging: boolean];
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SplitterResizeHandleProps>, {
    tabindex: number;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    dragging: (isDragging: boolean) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SplitterResizeHandleProps>, {
    tabindex: number;
}>>> & {
    onDragging?: ((isDragging: boolean) => any) | undefined;
}, {
    tabindex: number;
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
