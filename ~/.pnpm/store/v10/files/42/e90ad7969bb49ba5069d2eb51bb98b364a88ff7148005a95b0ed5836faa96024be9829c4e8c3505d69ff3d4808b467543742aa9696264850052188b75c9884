import { type DraggingItem, type HoveredItem } from './store';
export type DraggableProps = {
    /**
     * Upper threshold (gets multiplied with height)
     *
     * @default 0.8
     */
    ceiling?: number;
    /**
     * Lower threshold (gets multiplied with height)
     *
     * @default 0.2
     */
    floor?: number;
    /**
     * Disable dragging by setting to false
     *
     * @default true
     */
    isDraggable?: boolean;
    /**
     * Prevents items from being hovered and dropped into. Can be either a function or a boolean
     *
     * @default true
     */
    isDroppable?: boolean | ((draggingItem: DraggingItem, hoveredItem: HoveredItem) => boolean);
    /**
     * We pass an array of parents to make it easier to reverse traverse
     */
    parentIds: string[];
    /**
     * ID for the current item
     */
    id: string;
};
declare function __VLS_template(): {
    attrs: Partial<{}>;
    slots: {
        default?(_: {}): any;
    };
    refs: {};
    rootEl: HTMLDivElement;
};
type __VLS_TemplateResult = ReturnType<typeof __VLS_template>;
declare const __VLS_component: import("vue").DefineComponent<DraggableProps, {
    draggingItem: import("vue").Ref<{
        id: string;
        parentId: string | null;
    } | null, DraggingItem | {
        id: string;
        parentId: string | null;
    } | null>;
    hoveredItem: import("vue").Ref<{
        id: string;
        parentId: string | null;
        offset: number;
    } | null, HoveredItem | {
        id: string;
        parentId: string | null;
        offset: number;
    } | null>;
}, {}, {}, {}, import("vue").ComponentOptionsMixin, import("vue").ComponentOptionsMixin, {
    onDragEnd: (draggingItem: DraggingItem, hoveredItem: HoveredItem) => any;
    onDragStart: (draggingItem: DraggingItem) => any;
}, string, import("vue").PublicProps, Readonly<DraggableProps> & Readonly<{
    onOnDragEnd?: (draggingItem: DraggingItem, hoveredItem: HoveredItem) => any;
    onOnDragStart?: (draggingItem: DraggingItem) => any;
}>, {}, {}, {}, {}, string, import("vue").ComponentProvideOptions, false, {}, HTMLDivElement>;
declare const _default: __VLS_WithTemplateSlots<typeof __VLS_component, __VLS_TemplateResult["slots"]>;
export default _default;
type __VLS_WithTemplateSlots<T, S> = T & {
    new (): {
        $slots: S;
    };
};
//# sourceMappingURL=Draggable.vue.d.ts.map