interface Point {
    x: number;
    y: number;
}
interface Size {
    width: number;
    height: number;
}
interface Bounds {
    minX: number;
    midX: number;
    maxX: number;
    minY: number;
    midY: number;
    maxY: number;
}
interface CenterPoint {
    center: Point;
}
interface RectInit extends Point, Size {
}
interface Rect extends Point, Size, Bounds, CenterPoint {
}
type RectSide = "top" | "right" | "bottom" | "left";
type RectPoint = "top-left" | "top-center" | "top-right" | "right-center" | "left-center" | "bottom-left" | "bottom-right" | "bottom-center" | "center";
type RectEdge = [Point, Point];
type RectPoints = [Point, Point, Point, Point];
type RectEdges = Record<RectSide, RectEdge> & {
    value: RectEdge[];
};
type RectCorner = "topLeft" | "topRight" | "bottomLeft" | "bottomRight";
type RectCorners = Record<RectCorner, Point> & {
    value: RectPoints;
};
type RectCenter = "topCenter" | "rightCenter" | "leftCenter" | "bottomCenter";
type RectCenters = Record<RectCenter, Point> & {
    value: RectPoints;
};
type RectInset = Partial<Record<RectSide, number>>;
interface SymmetricRectInset {
    dx?: number | undefined;
    dy?: number | undefined;
}
interface ScalingOptions {
    scalingOriginMode: "center" | "extent";
    lockAspectRatio: boolean;
}
interface AlignOptions {
    h: HAlign;
    v: VAlign;
}
type HAlign = "left-inside" | "left-outside" | "center" | "right-inside" | "right-outside";
type VAlign = "top-inside" | "top-outside" | "center" | "bottom-inside" | "bottom-outside";

declare class AffineTransform {
    m00: number;
    m01: number;
    m02: number;
    m10: number;
    m11: number;
    m12: number;
    constructor([m00, m01, m02, m10, m11, m12]?: Iterable<number>);
    applyTo(point: Point): Point;
    prepend(other: AffineTransform): AffineTransform;
    append(other: AffineTransform): AffineTransform;
    get determinant(): number;
    get isInvertible(): boolean;
    invert(): AffineTransform;
    get array(): number[];
    get float32Array(): Float32Array;
    static get identity(): AffineTransform;
    static rotate(theta: number, origin?: Point): AffineTransform;
    rotate: (typeof AffineTransform)["rotate"];
    static scale(sx: number, sy?: number, origin?: Point): AffineTransform;
    scale: (typeof AffineTransform)["scale"];
    static translate(tx: number, ty: number): AffineTransform;
    translate: (typeof AffineTransform)["translate"];
    static multiply(...[first, ...rest]: AffineTransform[]): AffineTransform;
    get a(): number;
    get b(): number;
    get c(): number;
    get d(): number;
    get tx(): number;
    get ty(): number;
    get scaleComponents(): Point;
    get translationComponents(): Point;
    get skewComponents(): Point;
    toString(): string;
}

declare function alignRect(a: Rect, ref: Rect, options: AlignOptions): Rect;

declare function getPointAngle(rect: Rect, point: Point, reference?: Point): number;

declare const clampPoint: (position: Point, size: Size, boundaryRect: RectInit) => {
    x: number;
    y: number;
};
declare const clampSize: (size: Size, minSize?: Size, maxSize?: Size) => {
    width: number;
    height: number;
};

declare function closest(...pts: Point[]): (a: Point) => Point;
declare function closestSideToRect(ref: Rect, r: Rect): RectSide;
declare function closestSideToPoint(ref: Rect, p: Point): RectSide;

declare const constrainRect: (rect: RectInit, boundary: RectInit) => RectInit;

declare function containsPoint(r: Rect, p: Point): boolean;
declare function containsRect(a: Rect, b: Rect): boolean;
declare function contains(r: Rect, v: Rect | Point): boolean;

interface DistanceValue extends Point {
    value: number;
}
declare function distance(a: Point, b?: Point): number;
declare function distanceFromPoint(r: Rect, p: Point): DistanceValue;
declare function distanceFromRect(a: Rect, b: Rect): DistanceValue;
declare function distanceBtwEdges(a: Rect, b: Rect): Record<RectSide, number>;

declare const isSizeEqual: (a: Size, b: Size | undefined) => boolean;
declare const isPointEqual: (a: Point, b: Point | undefined) => boolean;
declare const isRectEqual: (a: RectInit, b: RectInit | undefined) => boolean;

declare function getElementRect(el: HTMLElement, opts?: ElementRectOptions): Rect;
type ElementRectOptions = {
    /**
     * Whether to exclude the element's scrollbar size from the calculation.
     */
    excludeScrollbar?: boolean;
    /**
     * Whether to exclude the element's borders from the calculation.
     */
    excludeBorders?: boolean;
};

declare function getRectFromPoints(...pts: Point[]): Rect;

declare function fromRange(range: Range): Rect;

declare function toRad(d: number): number;
declare function rotate(a: Point, d: number, c: Point): Point;
declare function getRotationRect(r: Rect, deg: number): Rect;

type WindowRectOptions = {
    /**
     * Whether to exclude the element's scrollbar size from the calculation.
     */
    excludeScrollbar?: boolean;
};
/**
 * Creates a rectangle from window object
 */
declare function getWindowRect(win: Window, opts?: WindowRectOptions): Rect;
/**
 * Get the rect of the window with the option to exclude the scrollbar
 */
declare function getViewportRect(win: Window, opts: WindowRectOptions): {
    x: number;
    y: number;
    width: number;
    height: number;
};

/**
 * Checks if a Rect intersects another Rect
 */
declare function intersects(a: Rect, b: Rect): boolean;
/**
 * Returns a new Rect that represents the intersection between two Rects
 */
declare function intersection(a: Rect, b: Rect): Rect;
/**
 * Returns whether two rects collide along each edge
 */
declare function collisions(a: Rect, b: Rect): Record<RectSide, boolean>;

declare const isSymmetric: (v: any) => v is SymmetricRectInset;
declare function inset(r: Rect, i: RectInset | SymmetricRectInset): Rect;
declare function expand(r: Rect, v: number | SymmetricRectInset): Rect;
declare function shrink(r: Rect, v: number | SymmetricRectInset): Rect;
declare function shift(r: Rect, o: Partial<Point>): Rect;

declare function getElementPolygon(rectValue: RectInit, placement: string): {
    x: number;
    y: number;
}[] | undefined;
declare function isPointInPolygon(polygon: Point[], point: Point): boolean;
declare function debugPolygon(polygon: Point[]): () => void;

declare const createPoint: (x: number, y: number) => {
    x: number;
    y: number;
};
declare const subtractPoints: (a: Point, b: Point | null) => Point;
declare const addPoints: (a: Point, b: Point) => {
    x: number;
    y: number;
};
declare function isPoint(v: any): v is Point;
declare function createRect(r: RectInit): Rect;
declare function isRect(v: any): v is Rect;
declare function getRectCenters(v: Rect): {
    top: {
        x: number;
        y: number;
    };
    right: {
        x: number;
        y: number;
    };
    bottom: {
        x: number;
        y: number;
    };
    left: {
        x: number;
        y: number;
    };
};
declare function getRectCorners(v: Rect): {
    top: {
        x: number;
        y: number;
    };
    right: {
        x: number;
        y: number;
    };
    bottom: {
        x: number;
        y: number;
    };
    left: {
        x: number;
        y: number;
    };
};
declare function getRectEdges(v: Rect): {
    top: RectEdge;
    right: RectEdge;
    bottom: RectEdge;
    left: RectEdge;
};

type CompassDirection = "n" | "ne" | "e" | "se" | "s" | "sw" | "w" | "nw";

declare function resizeRect(rect: Rect, offset: Point, direction: CompassDirection, opts: ScalingOptions): RectInit;

declare function union(...rs: Rect[]): Rect;

export { AffineTransform, type AlignOptions, type Bounds, type CenterPoint, type DistanceValue, type ElementRectOptions, type HAlign, type Point, type Rect, type RectCenter, type RectCenters, type RectCorner, type RectCorners, type RectEdge, type RectEdges, type RectInit, type RectInset, type RectPoint, type RectPoints, type RectSide, type ScalingOptions, type Size, type SymmetricRectInset, type VAlign, type WindowRectOptions, addPoints, alignRect, clampPoint, clampSize, closest, closestSideToPoint, closestSideToRect, collisions, constrainRect, contains, containsPoint, containsRect, createPoint, createRect, debugPolygon, distance, distanceBtwEdges, distanceFromPoint, distanceFromRect, expand, fromRange, getElementPolygon, getElementRect, getPointAngle, getRectCenters, getRectCorners, getRectEdges, getRectFromPoints, getRotationRect, getViewportRect, getWindowRect, inset, intersection, intersects, isPoint, isPointEqual, isPointInPolygon, isRect, isRectEqual, isSizeEqual, isSymmetric, resizeRect, rotate, shift, shrink, subtractPoints, toRad, union };
