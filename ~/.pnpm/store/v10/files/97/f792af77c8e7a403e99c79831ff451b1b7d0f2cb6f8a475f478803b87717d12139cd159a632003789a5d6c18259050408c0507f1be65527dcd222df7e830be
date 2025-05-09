'use strict';

var __defProp = Object.defineProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

// src/affine-transform.ts
var AffineTransform = class _AffineTransform {
  constructor([m00, m01, m02, m10, m11, m12] = [0, 0, 0, 0, 0, 0]) {
    __publicField(this, "m00");
    __publicField(this, "m01");
    __publicField(this, "m02");
    __publicField(this, "m10");
    __publicField(this, "m11");
    __publicField(this, "m12");
    __publicField(this, "rotate", (...args) => {
      return this.prepend(_AffineTransform.rotate(...args));
    });
    __publicField(this, "scale", (...args) => {
      return this.prepend(_AffineTransform.scale(...args));
    });
    __publicField(this, "translate", (...args) => {
      return this.prepend(_AffineTransform.translate(...args));
    });
    this.m00 = m00;
    this.m01 = m01;
    this.m02 = m02;
    this.m10 = m10;
    this.m11 = m11;
    this.m12 = m12;
  }
  applyTo(point) {
    const { x, y } = point;
    const { m00, m01, m02, m10, m11, m12 } = this;
    return {
      x: m00 * x + m01 * y + m02,
      y: m10 * x + m11 * y + m12
    };
  }
  prepend(other) {
    return new _AffineTransform([
      this.m00 * other.m00 + this.m01 * other.m10,
      // m00
      this.m00 * other.m01 + this.m01 * other.m11,
      // m01
      this.m00 * other.m02 + this.m01 * other.m12 + this.m02,
      // m02
      this.m10 * other.m00 + this.m11 * other.m10,
      // m10
      this.m10 * other.m01 + this.m11 * other.m11,
      // m11
      this.m10 * other.m02 + this.m11 * other.m12 + this.m12
      // m12
    ]);
  }
  append(other) {
    return new _AffineTransform([
      other.m00 * this.m00 + other.m01 * this.m10,
      // m00
      other.m00 * this.m01 + other.m01 * this.m11,
      // m01
      other.m00 * this.m02 + other.m01 * this.m12 + other.m02,
      // m02
      other.m10 * this.m00 + other.m11 * this.m10,
      // m10
      other.m10 * this.m01 + other.m11 * this.m11,
      // m11
      other.m10 * this.m02 + other.m11 * this.m12 + other.m12
      // m12
    ]);
  }
  get determinant() {
    return this.m00 * this.m11 - this.m01 * this.m10;
  }
  get isInvertible() {
    const det = this.determinant;
    return isFinite(det) && isFinite(this.m02) && isFinite(this.m12) && det !== 0;
  }
  invert() {
    const det = this.determinant;
    return new _AffineTransform([
      this.m11 / det,
      // m00
      -this.m01 / det,
      // m01
      (this.m01 * this.m12 - this.m11 * this.m02) / det,
      // m02
      -this.m10 / det,
      // m10
      this.m00 / det,
      // m11
      (this.m10 * this.m02 - this.m00 * this.m12) / det
      // m12
    ]);
  }
  get array() {
    return [this.m00, this.m01, this.m02, this.m10, this.m11, this.m12, 0, 0, 1];
  }
  get float32Array() {
    return new Float32Array(this.array);
  }
  // Static
  static get identity() {
    return new _AffineTransform([1, 0, 0, 0, 1, 0]);
  }
  static rotate(theta, origin) {
    const rotation = new _AffineTransform([Math.cos(theta), -Math.sin(theta), 0, Math.sin(theta), Math.cos(theta), 0]);
    if (origin && (origin.x !== 0 || origin.y !== 0)) {
      return _AffineTransform.multiply(
        _AffineTransform.translate(origin.x, origin.y),
        rotation,
        _AffineTransform.translate(-origin.x, -origin.y)
      );
    }
    return rotation;
  }
  static scale(sx, sy = sx, origin = { x: 0, y: 0 }) {
    const scale = new _AffineTransform([sx, 0, 0, 0, sy, 0]);
    if (origin.x !== 0 || origin.y !== 0) {
      return _AffineTransform.multiply(
        _AffineTransform.translate(origin.x, origin.y),
        scale,
        _AffineTransform.translate(-origin.x, -origin.y)
      );
    }
    return scale;
  }
  static translate(tx, ty) {
    return new _AffineTransform([1, 0, tx, 0, 1, ty]);
  }
  static multiply(...[first, ...rest]) {
    if (!first) return _AffineTransform.identity;
    return rest.reduce((result, item) => result.prepend(item), first);
  }
  get a() {
    return this.m00;
  }
  get b() {
    return this.m10;
  }
  get c() {
    return this.m01;
  }
  get d() {
    return this.m11;
  }
  get tx() {
    return this.m02;
  }
  get ty() {
    return this.m12;
  }
  get scaleComponents() {
    return { x: this.a, y: this.d };
  }
  get translationComponents() {
    return { x: this.tx, y: this.ty };
  }
  get skewComponents() {
    return { x: this.c, y: this.b };
  }
  toString() {
    return `matrix(${this.a}, ${this.b}, ${this.c}, ${this.d}, ${this.tx}, ${this.ty})`;
  }
};

// src/align.ts
function hAlign(a, ref, h) {
  let x = ref.minX;
  if (h === "left-inside") x = ref.minX;
  if (h === "left-outside") x = ref.minX - ref.width;
  if (h === "right-inside") x = ref.maxX - ref.width;
  if (h === "right-outside") x = ref.maxX;
  if (h === "center") x = ref.midX - ref.width / 2;
  return { ...a, x };
}
function vAlign(a, ref, v) {
  let y = ref.minY;
  if (v === "top-inside") y = ref.minY;
  if (v === "top-outside") y = ref.minY - a.height;
  if (v === "bottom-inside") y = ref.maxY - a.height;
  if (v === "bottom-outside") y = ref.maxY;
  if (v === "center") y = ref.midY - a.height / 2;
  return { ...a, y };
}
function alignRect(a, ref, options) {
  const { h, v } = options;
  return vAlign(hAlign(a, ref, h), ref, v);
}

// src/angle.ts
function getPointAngle(rect, point, reference = rect.center) {
  const x = point.x - reference.x;
  const y = point.y - reference.y;
  const deg = Math.atan2(x, y) * (180 / Math.PI) + 180;
  return 360 - deg;
}

// src/clamp.ts
var clamp = (value, min3, max2) => Math.min(Math.max(value, min3), max2);
var clampPoint = (position, size, boundaryRect) => {
  const x = clamp(position.x, boundaryRect.x, boundaryRect.x + boundaryRect.width - size.width);
  const y = clamp(position.y, boundaryRect.y, boundaryRect.y + boundaryRect.height - size.height);
  return { x, y };
};
var defaultMinSize = {
  width: 0,
  height: 0
};
var defaultMaxSize = {
  width: Infinity,
  height: Infinity
};
var clampSize = (size, minSize = defaultMinSize, maxSize = defaultMaxSize) => {
  return {
    width: Math.min(Math.max(size.width, minSize.width), maxSize.width),
    height: Math.min(Math.max(size.height, minSize.height), maxSize.height)
  };
};

// src/rect.ts
var createPoint = (x, y) => ({ x, y });
var subtractPoints = (a, b) => {
  if (!b) return a;
  return createPoint(a.x - b.x, a.y - b.y);
};
var addPoints = (a, b) => createPoint(a.x + b.x, a.y + b.y);
function isPoint(v) {
  return Reflect.has(v, "x") && Reflect.has(v, "y");
}
function createRect(r) {
  const { x, y, width, height } = r;
  const midX = x + width / 2;
  const midY = y + height / 2;
  return {
    x,
    y,
    width,
    height,
    minX: x,
    minY: y,
    maxX: x + width,
    maxY: y + height,
    midX,
    midY,
    center: createPoint(midX, midY)
  };
}
function isRect(v) {
  return Reflect.has(v, "x") && Reflect.has(v, "y") && Reflect.has(v, "width") && Reflect.has(v, "height");
}
function getRectCenters(v) {
  const top = createPoint(v.midX, v.minY);
  const right = createPoint(v.maxX, v.midY);
  const bottom = createPoint(v.midX, v.maxY);
  const left = createPoint(v.minX, v.midY);
  return { top, right, bottom, left };
}
function getRectCorners(v) {
  const top = createPoint(v.minX, v.minY);
  const right = createPoint(v.maxX, v.minY);
  const bottom = createPoint(v.maxX, v.maxY);
  const left = createPoint(v.minX, v.maxY);
  return { top, right, bottom, left };
}
function getRectEdges(v) {
  const c = getRectCorners(v);
  const top = [c.top, c.right];
  const right = [c.right, c.bottom];
  const bottom = [c.left, c.bottom];
  const left = [c.top, c.left];
  return { top, right, bottom, left };
}

// src/intersection.ts
function intersects(a, b) {
  return a.x < b.maxX && a.y < b.maxY && a.maxX > b.x && a.maxY > b.y;
}
function intersection(a, b) {
  const x = Math.max(a.x, b.x);
  const y = Math.max(a.y, b.y);
  const x2 = Math.min(a.x + a.width, b.x + b.width);
  const y2 = Math.min(a.y + a.height, b.y + b.height);
  return createRect({ x, y, width: x2 - x, height: y2 - y });
}
function collisions(a, b) {
  return {
    top: a.minY <= b.minY,
    right: a.maxX >= b.maxX,
    bottom: a.maxY >= b.maxY,
    left: a.minX <= b.minX
  };
}

// src/distance.ts
function distance(a, b = { x: 0, y: 0 }) {
  return Math.sqrt(Math.pow(a.x - b.x, 2) + Math.pow(a.y - b.y, 2));
}
function distanceFromPoint(r, p) {
  let x = 0;
  let y = 0;
  if (p.x < r.x) x = r.x - p.x;
  else if (p.x > r.maxX) x = p.x - r.maxX;
  if (p.y < r.y) y = r.y - p.y;
  else if (p.y > r.maxY) y = p.y - r.maxY;
  return { x, y, value: distance({ x, y }) };
}
function distanceFromRect(a, b) {
  if (intersects(a, b)) return { x: 0, y: 0, value: 0 };
  const left = a.x < b.x ? a : b;
  const right = b.x < a.x ? a : b;
  const upper = a.y < b.y ? a : b;
  const lower = b.y < a.y ? a : b;
  let x = left.x === right.x ? 0 : right.x - left.maxX;
  x = Math.max(0, x);
  let y = upper.y === lower.y ? 0 : lower.y - upper.maxY;
  y = Math.max(0, y);
  return { x, y, value: distance({ x, y }) };
}
function distanceBtwEdges(a, b) {
  return {
    left: b.x - a.x,
    top: b.y - a.y,
    right: a.maxX - b.maxX,
    bottom: a.maxY - b.maxY
  };
}

// src/closest.ts
function closest(...pts) {
  return (a) => {
    const ds = pts.map((b) => distance(b, a));
    const c = Math.min.apply(Math, ds);
    return pts[ds.indexOf(c)];
  };
}
function closestSideToRect(ref, r) {
  if (r.maxX <= ref.minX) return "left";
  if (r.minX >= ref.maxX) return "right";
  if (r.maxY <= ref.minY) return "top";
  if (r.minY >= ref.maxY) return "bottom";
  return "left";
}
function closestSideToPoint(ref, p) {
  const { x, y } = p;
  const dl = x - ref.minX;
  const dr = ref.maxX - x;
  const dt = y - ref.minY;
  const db = ref.maxY - y;
  let closest2 = dl;
  let side = "left";
  if (dr < closest2) {
    closest2 = dr;
    side = "right";
  }
  if (dt < closest2) {
    closest2 = dt;
    side = "top";
  }
  if (db < closest2) {
    side = "bottom";
  }
  return side;
}

// src/constrain.ts
var constrainRect = (rect, boundary) => {
  const left = Math.max(boundary.x, Math.min(rect.x, boundary.x + boundary.width - rect.width));
  const top = Math.max(boundary.y, Math.min(rect.y, boundary.y + boundary.height - rect.height));
  return {
    x: left,
    y: top,
    width: Math.min(rect.width, boundary.width),
    height: Math.min(rect.height, boundary.height)
  };
};

// src/contains.ts
function containsPoint(r, p) {
  return r.minX <= p.x && p.x <= r.maxX && r.minY <= p.y && p.y <= r.maxY;
}
function containsRect(a, b) {
  return Object.values(getRectCorners(b)).every((c) => containsPoint(a, c));
}
function contains(r, v) {
  return isRect(v) ? containsRect(r, v) : containsPoint(r, v);
}

// src/equality.ts
var isSizeEqual = (a, b) => {
  return a.width === b?.width && a.height === b?.height;
};
var isPointEqual = (a, b) => {
  return a.x === b?.x && a.y === b?.y;
};
var isRectEqual = (a, b) => {
  return isPointEqual(a, b) && isSizeEqual(a, b);
};

// src/from-element.ts
var styleCache = /* @__PURE__ */ new WeakMap();
function getCacheComputedStyle(el) {
  if (!styleCache.has(el)) {
    const win = el.ownerDocument.defaultView || window;
    styleCache.set(el, win.getComputedStyle(el));
  }
  return styleCache.get(el);
}
function getElementRect(el, opts = {}) {
  return createRect(getClientRect(el, opts));
}
function getClientRect(el, opts = {}) {
  const { excludeScrollbar = false, excludeBorders = false } = opts;
  const { x, y, width, height } = el.getBoundingClientRect();
  const r = { x, y, width, height };
  const style = getCacheComputedStyle(el);
  const { borderLeftWidth, borderTopWidth, borderRightWidth, borderBottomWidth } = style;
  const borderXWidth = sum(borderLeftWidth, borderRightWidth);
  const borderYWidth = sum(borderTopWidth, borderBottomWidth);
  if (excludeBorders) {
    r.width -= borderXWidth;
    r.height -= borderYWidth;
    r.x += px(borderLeftWidth);
    r.y += px(borderTopWidth);
  }
  if (excludeScrollbar) {
    const scrollbarWidth = el.offsetWidth - el.clientWidth - borderXWidth;
    const scrollbarHeight = el.offsetHeight - el.clientHeight - borderYWidth;
    r.width -= scrollbarWidth;
    r.height -= scrollbarHeight;
  }
  return r;
}
var px = (v) => parseFloat(v.replace("px", ""));
var sum = (...vals) => vals.reduce((sum2, v) => sum2 + (v ? px(v) : 0), 0);

// src/from-points.ts
function getRectFromPoints(...pts) {
  const xs = pts.map((p) => p.x);
  const ys = pts.map((p) => p.y);
  const x = Math.min(...xs);
  const y = Math.min(...ys);
  const width = Math.max(...xs) - x;
  const height = Math.max(...ys) - y;
  return createRect({ x, y, width, height });
}

// src/union.ts
var { min, max } = Math;
function union(...rs) {
  const pMin = {
    x: min(...rs.map((r) => r.minX)),
    y: min(...rs.map((r) => r.minY))
  };
  const pMax = {
    x: max(...rs.map((r) => r.maxX)),
    y: max(...rs.map((r) => r.maxY))
  };
  return getRectFromPoints(pMin, pMax);
}

// src/from-range.ts
function fromRange(range) {
  let rs = [];
  const rects = Array.from(range.getClientRects());
  if (rects.length) {
    rs = rs.concat(rects.map(createRect));
    return union.apply(void 0, rs);
  }
  let start = range.startContainer;
  if (start.nodeType === Node.TEXT_NODE) {
    start = start.parentNode;
  }
  if (start instanceof HTMLElement) {
    const r = getElementRect(start);
    rs.push({ ...r, x: r.maxX, width: 0 });
  }
  return union.apply(void 0, rs);
}

// src/from-rotation.ts
function toRad(d) {
  return d % 360 * Math.PI / 180;
}
function rotate(a, d, c) {
  const r = toRad(d);
  const sin = Math.sin(r);
  const cos = Math.cos(r);
  const x = a.x - c.x;
  const y = a.y - c.y;
  return {
    x: c.x + x * cos - y * sin,
    y: c.y + x * sin + y * cos
  };
}
function getRotationRect(r, deg) {
  const rr = Object.values(getRectCorners(r)).map((p) => rotate(p, deg, r.center));
  const xs = rr.map((p) => p.x);
  const ys = rr.map((p) => p.y);
  const minX = Math.min(...xs);
  const minY = Math.min(...ys);
  const maxX = Math.max(...xs);
  const maxY = Math.max(...ys);
  return createRect({
    x: minX,
    y: minY,
    width: maxX - minX,
    height: maxY - minY
  });
}

// src/from-window.ts
function getWindowRect(win, opts = {}) {
  return createRect(getViewportRect(win, opts));
}
function getViewportRect(win, opts) {
  const { excludeScrollbar = false } = opts;
  const { innerWidth, innerHeight, document: doc, visualViewport } = win;
  const width = visualViewport?.width || innerWidth;
  const height = visualViewport?.height || innerHeight;
  const rect = { x: 0, y: 0, width, height };
  if (excludeScrollbar) {
    const scrollbarWidth = innerWidth - doc.documentElement.clientWidth;
    const scrollbarHeight = innerHeight - doc.documentElement.clientHeight;
    rect.width -= scrollbarWidth;
    rect.height -= scrollbarHeight;
  }
  return rect;
}

// src/operations.ts
var isSymmetric = (v) => "dx" in v || "dy" in v;
function inset(r, i) {
  const v = isSymmetric(i) ? { left: i.dx, right: i.dx, top: i.dy, bottom: i.dy } : i;
  const { top = 0, right = 0, bottom = 0, left = 0 } = v;
  return createRect({
    x: r.x + left,
    y: r.y + top,
    width: r.width - left - right,
    height: r.height - top - bottom
  });
}
function expand(r, v) {
  const value = typeof v === "number" ? { dx: -v, dy: -v } : v;
  return inset(r, value);
}
function shrink(r, v) {
  const value = typeof v === "number" ? { dx: -v, dy: -v } : v;
  return inset(r, value);
}
function shift(r, o) {
  const { x = 0, y = 0 } = o;
  return createRect({
    x: r.x + x,
    y: r.y + y,
    width: r.width,
    height: r.height
  });
}

// src/polygon.ts
function getElementPolygon(rectValue, placement) {
  const rect = createRect(rectValue);
  const { top, right, left, bottom } = getRectCorners(rect);
  const [base] = placement.split("-");
  return {
    top: [left, top, right, bottom],
    right: [top, right, bottom, left],
    bottom: [top, left, bottom, right],
    left: [right, top, left, bottom]
  }[base];
}
function isPointInPolygon(polygon, point) {
  const { x, y } = point;
  let c = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i].x;
    const yi = polygon[i].y;
    const xj = polygon[j].x;
    const yj = polygon[j].y;
    if (yi > y !== yj > y && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      c = !c;
    }
  }
  return c;
}
function createPolygonElement() {
  const id = "debug-polygon";
  const existingPolygon = document.getElementById(id);
  if (existingPolygon) {
    return existingPolygon;
  }
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  Object.assign(svg.style, {
    top: "0",
    left: "0",
    width: "100%",
    height: "100%",
    opacity: "0.15",
    position: "fixed",
    pointerEvents: "none",
    fill: "red"
  });
  const polygon = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
  polygon.setAttribute("id", id);
  polygon.setAttribute("points", "0,0 0,0");
  svg.appendChild(polygon);
  document.body.appendChild(svg);
  return polygon;
}
function debugPolygon(polygon) {
  const el = createPolygonElement();
  const points = polygon.map((point) => `${point.x},${point.y}`).join(" ");
  el.setAttribute("points", points);
  return () => {
    el.remove();
  };
}

// src/compass.ts
var compassDirectionMap = {
  n: { x: 0.5, y: 0 },
  ne: { x: 1, y: 0 },
  e: { x: 1, y: 0.5 },
  se: { x: 1, y: 1 },
  s: { x: 0.5, y: 1 },
  sw: { x: 0, y: 1 },
  w: { x: 0, y: 0.5 },
  nw: { x: 0, y: 0 }
};
var oppositeDirectionMap = {
  n: "s",
  ne: "sw",
  e: "w",
  se: "nw",
  s: "n",
  sw: "ne",
  w: "e",
  nw: "se"
};

// src/resize.ts
var { sign, abs, min: min2 } = Math;
function getRectExtentPoint(rect, direction) {
  const { minX, minY, maxX, maxY, midX, midY } = rect;
  const x = direction.includes("w") ? minX : direction.includes("e") ? maxX : midX;
  const y = direction.includes("n") ? minY : direction.includes("s") ? maxY : midY;
  return { x, y };
}
function getOppositeDirection(direction) {
  return oppositeDirectionMap[direction];
}
function resizeRect(rect, offset, direction, opts) {
  const { scalingOriginMode, lockAspectRatio } = opts;
  const extent = getRectExtentPoint(rect, direction);
  const oppositeDirection = getOppositeDirection(direction);
  const oppositeExtent = getRectExtentPoint(rect, oppositeDirection);
  if (scalingOriginMode === "center") {
    offset = { x: offset.x * 2, y: offset.y * 2 };
  }
  const newExtent = {
    x: extent.x + offset.x,
    y: extent.y + offset.y
  };
  const multiplier = {
    x: compassDirectionMap[direction].x * 2 - 1,
    y: compassDirectionMap[direction].y * 2 - 1
  };
  const newSize = {
    width: newExtent.x - oppositeExtent.x,
    height: newExtent.y - oppositeExtent.y
  };
  const scaleX = multiplier.x * newSize.width / rect.width;
  const scaleY = multiplier.y * newSize.height / rect.height;
  const largestMagnitude = abs(scaleX) > abs(scaleY) ? scaleX : scaleY;
  const scale = lockAspectRatio ? { x: largestMagnitude, y: largestMagnitude } : {
    x: extent.x === oppositeExtent.x ? 1 : scaleX,
    y: extent.y === oppositeExtent.y ? 1 : scaleY
  };
  if (extent.y === oppositeExtent.y) {
    scale.y = abs(scale.y);
  } else if (sign(scale.y) !== sign(scaleY)) {
    scale.y *= -1;
  }
  if (extent.x === oppositeExtent.x) {
    scale.x = abs(scale.x);
  } else if (sign(scale.x) !== sign(scaleX)) {
    scale.x *= -1;
  }
  switch (scalingOriginMode) {
    case "extent":
      return transformRect(rect, AffineTransform.scale(scale.x, scale.y, oppositeExtent), false);
    case "center":
      return transformRect(
        rect,
        AffineTransform.scale(scale.x, scale.y, {
          x: rect.midX,
          y: rect.midY
        }),
        false
      );
  }
}
function createRectFromPoints(initialPoint, finalPoint, normalized = true) {
  if (normalized) {
    return {
      x: min2(finalPoint.x, initialPoint.x),
      y: min2(finalPoint.y, initialPoint.y),
      width: abs(finalPoint.x - initialPoint.x),
      height: abs(finalPoint.y - initialPoint.y)
    };
  }
  return {
    x: initialPoint.x,
    y: initialPoint.y,
    width: finalPoint.x - initialPoint.x,
    height: finalPoint.y - initialPoint.y
  };
}
function transformRect(rect, transform, normalized = true) {
  const p1 = transform.applyTo({ x: rect.minX, y: rect.minY });
  const p2 = transform.applyTo({ x: rect.maxX, y: rect.maxY });
  return createRectFromPoints(p1, p2, normalized);
}

exports.AffineTransform = AffineTransform;
exports.addPoints = addPoints;
exports.alignRect = alignRect;
exports.clampPoint = clampPoint;
exports.clampSize = clampSize;
exports.closest = closest;
exports.closestSideToPoint = closestSideToPoint;
exports.closestSideToRect = closestSideToRect;
exports.collisions = collisions;
exports.constrainRect = constrainRect;
exports.contains = contains;
exports.containsPoint = containsPoint;
exports.containsRect = containsRect;
exports.createPoint = createPoint;
exports.createRect = createRect;
exports.debugPolygon = debugPolygon;
exports.distance = distance;
exports.distanceBtwEdges = distanceBtwEdges;
exports.distanceFromPoint = distanceFromPoint;
exports.distanceFromRect = distanceFromRect;
exports.expand = expand;
exports.fromRange = fromRange;
exports.getElementPolygon = getElementPolygon;
exports.getElementRect = getElementRect;
exports.getPointAngle = getPointAngle;
exports.getRectCenters = getRectCenters;
exports.getRectCorners = getRectCorners;
exports.getRectEdges = getRectEdges;
exports.getRectFromPoints = getRectFromPoints;
exports.getRotationRect = getRotationRect;
exports.getViewportRect = getViewportRect;
exports.getWindowRect = getWindowRect;
exports.inset = inset;
exports.intersection = intersection;
exports.intersects = intersects;
exports.isPoint = isPoint;
exports.isPointEqual = isPointEqual;
exports.isPointInPolygon = isPointInPolygon;
exports.isRect = isRect;
exports.isRectEqual = isRectEqual;
exports.isSizeEqual = isSizeEqual;
exports.isSymmetric = isSymmetric;
exports.resizeRect = resizeRect;
exports.rotate = rotate;
exports.shift = shift;
exports.shrink = shrink;
exports.subtractPoints = subtractPoints;
exports.toRad = toRad;
exports.union = union;
