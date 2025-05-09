export type CheckedState = boolean | 'indeterminate';
export type Direction = 'ltr' | 'rtl';
export declare const ITEM_NAME = "MenuItem";
export declare const ITEM_SELECT = "menu.itemSelect";
export declare const SELECTION_KEYS: string[];
export declare const FIRST_KEYS: string[];
export declare const LAST_KEYS: string[];
export declare const FIRST_LAST_KEYS: string[];
export declare const SUB_OPEN_KEYS: Record<Direction, string[]>;
export declare const SUB_CLOSE_KEYS: Record<Direction, string[]>;
export declare function getOpenState(open: boolean): "open" | "closed";
export declare function isIndeterminate(checked?: CheckedState): checked is 'indeterminate';
export declare function getCheckedState(checked: CheckedState): "indeterminate" | "checked" | "unchecked";
export declare function focusFirst(candidates: HTMLElement[]): void;
export interface Point {
    x: number;
    y: number;
}
export type Polygon = Point[];
export type Side = 'left' | 'right';
export interface GraceIntent {
    area: Polygon;
    side: Side;
}
export declare function isPointInPolygon(point: Point, polygon: Polygon): boolean;
export declare function isPointerInGraceArea(event: PointerEvent, area?: Polygon): boolean;
export declare function isMouseEvent(event: PointerEvent): boolean;
