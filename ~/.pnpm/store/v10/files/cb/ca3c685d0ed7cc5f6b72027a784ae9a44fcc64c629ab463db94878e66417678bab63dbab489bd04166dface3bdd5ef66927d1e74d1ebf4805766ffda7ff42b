import { PrimitiveProps } from '../Primitive';
export interface SplitterPanelProps extends PrimitiveProps {
    /** The size of panel when it is collapsed. */
    collapsedSize?: number;
    /** Should panel collapse when resized beyond its `minSize`. When `true`, it will be collapsed to `collapsedSize`. */
    collapsible?: boolean;
    /** Initial size of panel (numeric value between 1-100) */
    defaultSize?: number;
    /** Panel id (unique within group); falls back to `useId` when not provided */
    id?: string;
    /** The maximum allowable size of panel (numeric value between 1-100); defaults to `100` */
    maxSize?: number;
    /** The minimum allowable size of panel (numeric value between 1-100); defaults to `10` */
    minSize?: number;
    /** The order of panel within group; required for groups with conditionally rendered panels */
    order?: number;
}
export type SplitterPanelEmits = {
    /** Event handler called when panel is collapsed. */
    collapse: [];
    /** Event handler called when panel is expanded. */
    expand: [];
    /** Event handler called when panel is resized; size parameter is a numeric value between 1-100.  */
    resize: [size: number, prevSize: number | undefined];
};
export type PanelOnCollapse = () => void;
export type PanelOnExpand = () => void;
export type PanelOnResize = (size: number, prevSize: number | undefined) => void;
export type PanelCallbacks = {
    onCollapse?: PanelOnCollapse;
    onExpand?: PanelOnExpand;
    onResize?: PanelOnResize;
};
export type PanelConstraints = {
    collapsedSize?: number | undefined;
    collapsible?: boolean | undefined;
    defaultSize?: number | undefined;
    /** Panel id (unique within group); falls back to useId when not provided */
    maxSize?: number | undefined;
    minSize?: number | undefined;
};
export type PanelData = {
    callbacks: PanelCallbacks;
    constraints: PanelConstraints;
    id: string;
    idIsFromProps: boolean;
    order: number | undefined;
};
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_TypePropsToOption<SplitterPanelProps>, {
    /** If panel is `collapsible`, collapse it fully. */
    collapse: () => void;
    /** If panel is currently collapsed, expand it to its most recent size. */
    expand: () => void;
    /** Gets the current size of the panel as a percentage (1 - 100). */
    getSize(): number;
    /** Resize panel to the specified percentage (1 - 100). */
    resize: (size: number) => void;
    /** Returns `true` if the panel is currently collapsed */
    isCollapsed: import('vue').ComputedRef<boolean>;
    /** Returns `true` if the panel is currently not collapsed */
    isExpanded: import('vue').ComputedRef<boolean>;
}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    resize: (size: number, prevSize: number | undefined) => void;
    collapse: () => void;
    expand: () => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_TypePropsToOption<SplitterPanelProps>>> & {
    onResize?: ((size: number, prevSize: number | undefined) => any) | undefined;
    onCollapse?: (() => any) | undefined;
    onExpand?: (() => any) | undefined;
}, {}, {}>, Readonly<{
    default: (props: {
        /** Is the panel collapsed */
        isCollapsed: boolean;
        /** Is the panel expanded */
        isExpanded: boolean;
    }) => any;
}> & {
    default: (props: {
        /** Is the panel collapsed */
        isCollapsed: boolean;
        /** Is the panel expanded */
        isExpanded: boolean;
    }) => any;
}>;
export default _default;
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
