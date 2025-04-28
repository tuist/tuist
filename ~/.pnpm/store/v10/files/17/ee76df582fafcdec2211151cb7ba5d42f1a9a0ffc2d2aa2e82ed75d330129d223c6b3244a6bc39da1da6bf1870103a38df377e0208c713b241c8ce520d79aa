/**
 * Item you are currently dragging over
 */
export type HoveredItem = {
    id: string;
    parentId: string | null;
    /**
     * Offset is used when adding back an item, also for the highlight classes
     * 0 = above      | .dragover-above
     * 1 = below      | .dragover-below
     * 2 = as a child | .dragover-asChild
     */
    offset: number;
};
/**
 * Item you are currently dragging
 */
export type DraggingItem = Omit<HoveredItem, 'offset'>;
/**
 * Item you are currently dragging
 */
export declare const draggingItem: import("vue").Ref<{
    id: string;
    parentId: string | null;
} | null, DraggingItem | {
    id: string;
    parentId: string | null;
} | null>;
/**
 * Item you are currently dragging over
 */
export declare const hoveredItem: import("vue").Ref<{
    id: string;
    parentId: string | null;
    offset: number;
} | null, HoveredItem | {
    id: string;
    parentId: string | null;
    offset: number;
} | null>;
//# sourceMappingURL=store.d.ts.map