import { Direction, DragState, ResizeEvent } from './types';
import { PanelData } from '../SplitterPanel';
export declare function calculateDragOffsetPercentage(event: ResizeEvent, dragHandleId: string, direction: Direction, initialDragState: DragState, panelGroupElement: HTMLElement): number;
export declare function calculateDeltaPercentage(event: ResizeEvent, dragHandleId: string, direction: Direction, initialDragState: DragState | null, keyboardResizeBy: number | null, panelGroupElement: HTMLElement): number;
export declare function calculateAriaValues({ layout, panelsArray, pivotIndices, }: {
    layout: number[];
    panelsArray: PanelData[];
    pivotIndices: number[];
}): {
    valueMax: number;
    valueMin: number;
    valueNow: number;
};
export declare function calculateUnsafeDefaultLayout({ panelDataArray, }: {
    panelDataArray: PanelData[];
}): number[];
