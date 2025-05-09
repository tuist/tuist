import { PanelConstraints, PanelData } from './SplitterPanel';
import { Direction, DragState, ResizeEvent, ResizeHandler } from './utils/types';
import { PrimitiveProps } from '../Primitive';
import { CSSProperties, Ref } from 'vue';
export interface SplitterGroupProps extends PrimitiveProps {
    /** Group id; falls back to `useId` when not provided. */
    id?: string | null;
    /** Unique id used to auto-save group arrangement via `localStorage`. */
    autoSaveId?: string | null;
    /** The group orientation of splitter. */
    direction: Direction;
    /** Step size when arrow key was pressed. */
    keyboardResizeBy?: number | null;
    /** Custom storage API; defaults to localStorage */
    storage?: PanelGroupStorage;
}
export type SplitterGroupEmits = {
    /** Event handler called when group layout changes */
    layout: [val: number[]];
};
export type PanelGroupStorage = {
    getItem: (name: string) => string | null;
    setItem: (name: string, value: string) => void;
};
export type PanelGroupContext = {
    direction: Ref<Direction>;
    dragState: DragState | null;
    groupId: string;
    reevaluatePanelConstraints: (panelData: PanelData, prevConstraints: PanelConstraints) => void;
    registerPanel: (panelData: PanelData) => void;
    registerResizeHandle: (dragHandleId: string) => ResizeHandler;
    resizePanel: (panelData: PanelData, size: number) => void;
    startDragging: (dragHandleId: string, event: ResizeEvent) => void;
    stopDragging: () => void;
    unregisterPanel: (panelData: PanelData) => void;
    panelGroupElement: Ref<ParentNode | null>;
    collapsePanel: (panelData: PanelData) => void;
    expandPanel: (panelData: PanelData) => void;
    isPanelCollapsed: (panelData: PanelData) => boolean;
    isPanelExpanded: (panelData: PanelData) => boolean;
    getPanelSize: (panelData: PanelData) => number;
    getPanelStyle: (panelData: PanelData, defaultSize: number | undefined) => CSSProperties;
};
export declare const injectPanelGroupContext: <T extends PanelGroupContext | null | undefined = PanelGroupContext>(fallback?: T | undefined) => T extends null ? PanelGroupContext | null : PanelGroupContext, providePanelGroupContext: (contextValue: PanelGroupContext) => PanelGroupContext;
declare const _default: __VLS_WithTemplateSlots<import('vue').DefineComponent<__VLS_WithDefaults<__VLS_TypePropsToOption<SplitterGroupProps>, {
    autoSaveId: null;
    keyboardResizeBy: number;
    storage: () => PanelGroupStorage;
}>, {}, unknown, {}, {}, import('vue').ComponentOptionsMixin, import('vue').ComponentOptionsMixin, {
    layout: (val: number[]) => void;
}, string, import('vue').PublicProps, Readonly<import('vue').ExtractPropTypes<__VLS_WithDefaults<__VLS_TypePropsToOption<SplitterGroupProps>, {
    autoSaveId: null;
    keyboardResizeBy: number;
    storage: () => PanelGroupStorage;
}>>> & {
    onLayout?: ((val: number[]) => any) | undefined;
}, {
    storage: PanelGroupStorage;
    autoSaveId: string | null;
    keyboardResizeBy: number | null;
}, {}>, Readonly<{
    default: (props: {
        /** Current size of layout */
        layout: number[];
    }) => any;
}> & {
    default: (props: {
        /** Current size of layout */
        layout: number[];
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
