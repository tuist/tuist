import { VirtualElement, Placement, Boundary, AutoUpdateOptions, ComputePositionReturn } from '@floating-ui/dom';
export { AutoUpdateOptions, Boundary, ComputePositionReturn, Placement } from '@floating-ui/dom';

type MaybeRectElement = HTMLElement | VirtualElement | null;
type MaybeElement = HTMLElement | null;
type MaybeFn<T> = T | (() => T);
type PlacementSide = "top" | "right" | "bottom" | "left";
type PlacementAlign = "start" | "center" | "end";
interface AnchorRect {
    x?: number | undefined;
    y?: number | undefined;
    width?: number | undefined;
    height?: number | undefined;
}
interface PositioningOptions {
    /**
     * Whether the popover should be hidden when the reference element is detached
     */
    hideWhenDetached?: boolean | undefined;
    /**
     * The strategy to use for positioning
     */
    strategy?: "absolute" | "fixed" | undefined;
    /**
     * The initial placement of the floating element
     */
    placement?: Placement | undefined;
    /**
     * The offset of the floating element
     */
    offset?: {
        mainAxis?: number;
        crossAxis?: number;
    } | undefined;
    /**
     * The main axis offset or gap between the reference and floating elements
     */
    gutter?: number | undefined;
    /**
     * The secondary axis offset or gap between the reference and floating elements
     */
    shift?: number | undefined;
    /**
     * The virtual padding around the viewport edges to check for overflow
     */
    overflowPadding?: number | undefined;
    /**
     * The minimum padding between the arrow and the floating element's corner.
     * @default 4
     */
    arrowPadding?: number | undefined;
    /**
     * Whether to flip the placement
     */
    flip?: boolean | Placement[] | undefined;
    /**
     * Whether the popover should slide when it overflows.
     */
    slide?: boolean | undefined;
    /**
     * Whether the floating element can overlap the reference element
     * @default false
     */
    overlap?: boolean | undefined;
    /**
     * Whether to make the floating element same width as the reference element
     */
    sameWidth?: boolean | undefined;
    /**
     * Whether the popover should fit the viewport.
     */
    fitViewport?: boolean | undefined;
    /**
     * The overflow boundary of the reference element
     */
    boundary?: (() => Boundary) | undefined;
    /**
     * Options to activate auto-update listeners
     */
    listeners?: boolean | AutoUpdateOptions | undefined;
    /**
     * Function called when the placement is computed
     */
    onComplete?: ((data: ComputePositionReturn) => void) | undefined;
    /**
     * Function called when the floating element is positioned or not
     */
    onPositioned?: ((data: {
        placed: boolean;
    }) => void) | undefined;
    /**
     *  Function that returns the anchor rect
     */
    getAnchorRect?: ((element: HTMLElement | VirtualElement | null) => AnchorRect | null) | undefined;
    /**
     * A callback that will be called when the popover needs to calculate its
     * position.
     */
    updatePosition?: ((data: {
        updatePosition: () => Promise<void>;
    }) => void | Promise<void>) | undefined;
}

declare function getPlacement(referenceOrFn: MaybeFn<MaybeRectElement>, floatingOrFn: MaybeFn<MaybeElement>, opts?: PositioningOptions & {
    defer?: boolean;
}): () => void;

declare const cssVars: {
    arrowSize: {
        variable: string;
        reference: string;
    };
    arrowSizeHalf: {
        variable: string;
        reference: string;
    };
    arrowBg: {
        variable: string;
        reference: string;
    };
    transformOrigin: {
        variable: string;
        reference: string;
    };
    arrowOffset: {
        variable: string;
        reference: string;
    };
};

interface GetPlacementStylesOptions {
    placement?: Placement | undefined;
}
declare function getPlacementStyles(options?: Pick<PositioningOptions, "placement" | "sameWidth" | "fitViewport" | "strategy">): {
    arrow: {
        readonly [cssVars.arrowSizeHalf.variable]: `calc(${string} / 2)`;
        readonly [cssVars.arrowOffset.variable]: `calc(${string} * -1)`;
        readonly position: "absolute";
        readonly width: string;
        readonly height: string;
    };
    arrowTip: {
        readonly transform: any;
        readonly background: string;
        readonly top: "0";
        readonly left: "0";
        readonly width: "100%";
        readonly height: "100%";
        readonly position: "absolute";
        readonly zIndex: "inherit";
    };
    floating: {
        readonly position: "fixed" | "absolute";
        readonly isolation: "isolate";
        readonly minWidth: "max-content" | undefined;
        readonly width: "var(--reference-width)" | undefined;
        readonly maxWidth: "var(--available-width)" | undefined;
        readonly maxHeight: "var(--available-height)" | undefined;
        readonly pointerEvents: "none" | undefined;
        readonly top: "0px";
        readonly left: "0px";
        readonly transform: "translate3d(var(--x), var(--y), 0)" | "translate3d(0, -100vh, 0)";
        readonly zIndex: "var(--z-index)";
    };
};

declare function isValidPlacement(v: string): v is Placement;
declare function getPlacementSide(placement: Placement): PlacementSide;

export { type AnchorRect, type GetPlacementStylesOptions, type PlacementAlign, type PlacementSide, type PositioningOptions, getPlacement, getPlacementSide, getPlacementStyles, isValidPlacement };
