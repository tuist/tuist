// Floating header and horizontal scrollbar for tables.
//
// Both pin to the edges of the element that actually scrolls the table (the app's content pane,
// or the window when nothing else scrolls — see `findScrollParent`), not to the window's edges,
// so they sit within the scroll area rather than over the navbar or chrome around it.
//
// Header: once the table's top scrolls past the scroll area's top, a fixed-position clone of the
// `thead` is pinned there, until the table's end pushes it back out. `position: fixed` is pinned
// by the compositor, so the header doesn't wobble during scrolling the way a JS-translated
// element does (scroll happens on the compositor thread; JS catches up a frame late). The clone
// lives on `document.body` so LiveView patches never touch it, and its column widths and
// horizontal scroll position are synced from the real table.
//
// Scrollbar: while a horizontally scrollable table is on screen but its own scrollbar is below
// the scroll area's bottom, a proxy scrollbar is fixed there and kept in sync with the table.
// Once the table's bottom (and its native scrollbar) scrolls into view, the proxy hides and the
// native scrollbar takes over.
//
// Both use `position: fixed` with measured coordinates instead of `position: sticky`, since
// sticky breaks whenever any ancestor has a non-visible overflow (as app layouts commonly do).
export default {
  mounted() {
    this.container = this.el.querySelector('[data-part="scroll-container"]');
    this.scrollbar = this.el.querySelector('[data-part="scrollbar"]');
    this.spacer = this.scrollbar?.querySelector(
      '[data-part="scrollbar-content"]',
    );
    this.thead = this.container?.querySelector("thead");
    this.overlayBar = this.el.querySelector('[data-part="overlay-scrollbar"]');
    this.overlayThumb = this.overlayBar?.querySelector(
      '[data-part="overlay-thumb"]',
    );
    // Whether the browser supports `::-webkit-scrollbar` styling (Chrome/Safari). Where it
    // doesn't (Firefox), the native bar cannot match the design and the custom bar takes over.
    this.webkitScrollbars = CSS.supports("selector(::-webkit-scrollbar)");
    if (!this.container || !this.scrollbar || !this.spacer) return;

    // The element that actually scrolls the table vertically — the app's content pane, not the
    // window, in the current shell. The floating header and scrollbar pin to this element's
    // viewport edges (just below a fixed navbar, say), not to the window's, so they don't land
    // on top of the chrome around the scroll area. Cached here and refreshed on patch.
    this.scrollParent = this.findScrollParent();

    if (this.overlayThumb) {
      this.onThumbDown = (e) => {
        e.preventDefault();
        this.thumbDrag = {
          x: e.clientX,
          scrollLeft: this.container.scrollLeft,
        };
        this.overlayThumb.setPointerCapture(e.pointerId);
      };
      this.onThumbMove = (e) => {
        if (!this.thumbDrag) return;
        const maxScroll =
          this.container.scrollWidth - this.container.clientWidth;
        const maxLeft =
          this.overlayBar.clientWidth - this.overlayThumb.offsetWidth;
        if (maxLeft <= 0) return;
        this.container.scrollLeft =
          this.thumbDrag.scrollLeft +
          (e.clientX - this.thumbDrag.x) * (maxScroll / maxLeft);
      };
      this.onThumbUp = () => {
        this.thumbDrag = null;
      };
      this.overlayThumb.addEventListener("pointerdown", this.onThumbDown);
      this.overlayThumb.addEventListener("pointermove", this.onThumbMove);
      this.overlayThumb.addEventListener("pointerup", this.onThumbUp);
    }

    this.header = document.createElement("div");
    this.header.className = "noora-table noora-table-floating-header";
    // The clone is purely decorative — the real header stays the accessible, interactive one.
    // `inert` removes the clone's cloned sort links/controls from the focus order and a11y tree
    // and blocks pointer events on them (without it, focus could land on AT-hidden controls, and
    // a cloned `patch` link — living outside the LiveView root — would full-navigate on click).
    // `aria-hidden` stays as a fallback for engines without `inert`.
    this.header.setAttribute("aria-hidden", "true");
    this.header.inert = true;
    document.body.appendChild(this.header);

    this.onContainerScroll = () => {
      if (this.scrollbar.scrollLeft !== this.container.scrollLeft) {
        this.scrollbar.scrollLeft = this.container.scrollLeft;
      }
      this.syncHeaderScroll();
      this.syncOverlayThumb();
    };
    this.onScrollbarScroll = () => {
      if (this.container.scrollLeft !== this.scrollbar.scrollLeft) {
        this.container.scrollLeft = this.scrollbar.scrollLeft;
      }
    };
    this.container.addEventListener("scroll", this.onContainerScroll, {
      passive: true,
    });
    this.scrollbar.addEventListener("scroll", this.onScrollbarScroll, {
      passive: true,
    });

    // Capture-phase listener so scrolling any ancestor (not just the window) re-positions the
    // floating elements. Throttled to one sync per frame.
    this.onViewportChange = () => {
      if (this.frame) return;
      this.frame = requestAnimationFrame(() => {
        this.frame = null;
        this.sync();
      });
    };
    window.addEventListener("scroll", this.onViewportChange, {
      capture: true,
      passive: true,
    });

    // A resize can change which ancestor scrolls — content that fit at load (so the window was
    // the scroller) can start overflowing the content pane when the window shrinks, making the
    // pane the scroller. Re-resolve the scroll parent on resize (kept off the scroll path, which
    // must stay cheap, since scrolling never changes the scroller). Throttled to one frame.
    this.onResize = () => {
      if (this.resizeFrame) return;
      this.resizeFrame = requestAnimationFrame(() => {
        this.resizeFrame = null;
        this.scrollParent = this.findScrollParent();
        this.sync();
      });
    };
    window.addEventListener("resize", this.onResize, { passive: true });

    // Header widths only depend on horizontal geometry, and syncing them measures every header
    // cell and writes to the body-level clone — a forced full-page reflow. Height-only resizes
    // (a row expanding frame-by-frame, content loading in) must skip it, or the expand animation
    // pays an extra synchronous layout on every frame. `contentRect` comes with the entry, so
    // detecting the width change costs no layout read.
    this.observedWidths = new Map();
    this.resizeObserver = new ResizeObserver((entries) => {
      let widthChanged = false;
      for (const entry of entries) {
        const width = entry.contentRect.width;
        if (this.observedWidths.get(entry.target) !== width) {
          this.observedWidths.set(entry.target, width);
          widthChanged = true;
        }
      }
      if (widthChanged) this.syncHeaderWidths();
      this.sync();
    });
    this.resizeObserver.observe(this.container);
    const table = this.container.querySelector("table");
    if (table) this.resizeObserver.observe(table);

    this.applyColumnWidths();
    this.sync();
  },

  updated() {
    this.thead = this.container?.querySelector("thead");
    this.scrollParent = this.findScrollParent();
    this.applyColumnWidths();
    if (this.header?.hasAttribute("data-visible")) this.refreshHeader();
    this.sync();
  },

  // Nearest ancestor that actually scrolls vertically. The search starts above `.noora-table` so
  // it skips the table's own horizontal scroll container. Returns null when nothing between here
  // and the document scrolls — i.e. the window is the scroller — in which case the viewport edges
  // are used.
  //
  // Two false positives have to be filtered out, both stemming from the CSS rule that a non-
  // `visible` value on one axis forces the other axis from `visible` to `auto`: the table's own
  // `overflow-x: auto` container, and any ancestor with `overflow-x: hidden` (a card that only
  // clips horizontally). Both report a computed `overflow-y: auto` while having no vertical scroll
  // room. Requiring `scrollHeight > clientHeight` excludes them — otherwise the floating header
  // would pin to a box that merely scrolls away with the table and would never detach.
  findScrollParent() {
    let el = this.el.parentElement;
    while (el && el !== document.body && el !== document.documentElement) {
      const overflowY = getComputedStyle(el).overflowY;
      const scrollable =
        overflowY === "auto" ||
        overflowY === "scroll" ||
        overflowY === "overlay";
      if (scrollable && el.scrollHeight > el.clientHeight) {
        return el;
      }
      el = el.parentElement;
    }
    return null;
  },

  destroyed() {
    if (this.frame) cancelAnimationFrame(this.frame);
    if (this.resizeFrame) cancelAnimationFrame(this.resizeFrame);
    this.resizeObserver?.disconnect();
    this.container?.removeEventListener("scroll", this.onContainerScroll);
    this.scrollbar?.removeEventListener("scroll", this.onScrollbarScroll);
    window.removeEventListener("scroll", this.onViewportChange, {
      capture: true,
    });
    window.removeEventListener("resize", this.onResize);
    this.overlayThumb?.removeEventListener("pointerdown", this.onThumbDown);
    this.overlayThumb?.removeEventListener("pointermove", this.onThumbMove);
    this.overlayThumb?.removeEventListener("pointerup", this.onThumbUp);
    this.header?.remove();
  },

  // Keeps columns from shifting when a LiveView update swaps the rows (sorting, pagination):
  // auto table layout re-derives column widths from the new content, so columns jump left and
  // right. Each column's rendered width is ratcheted into a `min-width` that only grows —
  // columns never shrink back on an update, and longer content can still widen them, so nothing
  // is ever clipped. Runs after every patch since LiveView wipes the inline styles, and before
  // paint, so no shifted frame is visible.
  //
  // The pin is deliberately ONE-WAY (grow-only). It tracks the widest content a column has shown
  // for the lifetime of this hook instance and never lowers the pin, which is what stops the
  // back-and-forth jitter across stream/sort/filter updates. The trade-off: once a batch widens
  // a column, a later batch with narrower content stays at the wider width rather than tightening
  // back. That's intended — re-tightening is exactly the shift this is here to prevent — but it
  // means column widths reflect the widest data seen, not the current page's data. The pin only
  // resets when the hook remounts (full navigation) or the column count changes.
  applyColumnWidths() {
    const cells = this.thead?.rows[0]?.cells ?? [];
    if (cells.length === 0) return;
    if (this.columnWidths?.length !== cells.length) {
      this.columnWidths = new Array(cells.length).fill(0);
    }
    // Only engage once the table actually overflows its frame. In a fitting table the columns
    // are stretched to fill it, and pinning those slack-inflated widths would force a scrollbar
    // and break the fill behavior; in an overflowing one the rendered widths are the content
    // widths. Once engaged, the pins are kept (LiveView wipes the inline styles on each patch).
    const engaged =
      this.container.scrollWidth > this.container.clientWidth ||
      this.columnWidths.some((w) => w > 0);
    if (!engaged) return;
    const widths = Array.from(cells, (c) => c.getBoundingClientRect().width);
    for (let i = 0; i < cells.length; i++) {
      // Exact fractional widths, with jitter tolerance: rounding up would make the pinned sum
      // exceed the container and manufacture an overflow on its own.
      if (widths[i] > this.columnWidths[i] + 0.5) {
        this.columnWidths[i] = widths[i];
      }
      if (this.columnWidths[i] > 0) {
        cells[i].style.minWidth = `${this.columnWidths[i]}px`;
      }
    }
  },

  refreshHeader() {
    if (!this.thead) {
      this.header.replaceChildren();
      this.headerTable = null;
      return;
    }
    const table = document.createElement("table");
    table.style.tableLayout = "fixed";
    const clonedThead = this.thead.cloneNode(true);
    // Strip IDs from the decorative clone so it can't duplicate the real header's IDs (sort
    // indicators, icon SVGs), which would otherwise break ID lookups, ARIA references, and SVG
    // `<use href="#…">` resolution.
    if (clonedThead.id) clonedThead.removeAttribute("id");
    for (const node of clonedThead.querySelectorAll("[id]")) {
      node.removeAttribute("id");
    }
    table.appendChild(clonedThead);
    this.header.replaceChildren(table);
    this.headerTable = table;
    this.syncHeaderWidths();
    this.syncHeaderScroll();
  },

  syncHeaderWidths() {
    if (!this.headerTable || !this.thead) return;
    const sourceCells = this.thead.rows[0]?.cells ?? [];
    const cloneCells = this.headerTable.rows[0]?.cells ?? [];
    this.headerTable.style.width = `${this.container.querySelector("table").getBoundingClientRect().width}px`;
    for (let i = 0; i < cloneCells.length; i++) {
      cloneCells[i].style.boxSizing = "border-box";
      cloneCells[i].style.width =
        `${sourceCells[i]?.getBoundingClientRect().width ?? 0}px`;
    }
  },

  syncHeaderScroll() {
    if (!this.headerTable) return;
    this.headerTable.style.transform = `translateX(${-this.container.scrollLeft}px)`;
  },

  syncOverlayThumb() {
    if (!this.overlayBar?.hasAttribute("data-visible")) return;
    const track = this.overlayBar.clientWidth;
    const { scrollWidth, clientWidth, scrollLeft } = this.container;
    const width = Math.max((clientWidth / scrollWidth) * track, 24);
    const maxScroll = scrollWidth - clientWidth;
    const left = maxScroll > 0 ? (scrollLeft / maxScroll) * (track - width) : 0;
    this.overlayThumb.style.width = `${width}px`;
    this.overlayThumb.style.transform = `translateX(${left}px)`;
  },

  sync() {
    if (!this.container || !this.scrollbar || !this.spacer) return;
    const scrollable = this.container.scrollWidth > this.container.clientWidth;

    // The custom bar replaces the native one wherever native cannot match the webkit-styled
    // design: Firefox (no `::-webkit-scrollbar`, so no insets), and overlay-scrollbar platforms
    // (the bar paints over content and hides at rest).
    const custom =
      scrollable &&
      (!this.webkitScrollbars ||
        this.container.offsetHeight - this.container.clientHeight === 0);

    // Separate the last row from the scrollbar lane with real padding rather than scrollbar
    // styling, so every engine gets the same gap. Only applied when the table actually scrolls,
    // so non-scrolling tables keep their flush bottom edge. With the custom bar (native one
    // suppressed), the padding is the whole lane.
    // 16px + the root's 4px make a 20px strip, putting 6px on both sides of the 8px thumb —
    // the same spacing the webkit-styled native lane produces.
    const paddingBottom = scrollable
      ? custom
        ? "16px"
        : "var(--noora-spacing-2)"
      : "";
    if (this.container.style.paddingBottom !== paddingBottom) {
      this.container.style.paddingBottom = paddingBottom;
    }
    const nativeWidth = custom ? "none" : "";
    if (this.container.style.scrollbarWidth !== nativeWidth) {
      this.container.style.scrollbarWidth = nativeWidth;
    }
    // Matching padding below the scrollbar lane (on the root, since nothing can render below a
    // native scrollbar inside its own scroll container), so the pill sits vertically centered
    // between the last row and the table's bottom edge.
    const rootPadding = scrollable ? "var(--noora-spacing-2)" : "";
    if (this.el.style.paddingBottom !== rootPadding) {
      this.el.style.paddingBottom = rootPadding;
    }

    const rect = this.container.getBoundingClientRect();
    // The container's bottom edge includes the native scrollbar gutter; the content ends above it.
    const gutter = this.container.offsetHeight - this.container.clientHeight;
    const contentBottom = rect.bottom - gutter;

    // Top and bottom edges of the scrolling viewport, in viewport coordinates. When a content
    // pane scrolls (rather than the window), these are its edges — below the navbar and above
    // the window bottom — so the floating header and scrollbar stay within the scroll area
    // instead of pinning to the window and overlapping the surrounding chrome.
    let viewTop = 0;
    let viewBottom = window.innerHeight;
    if (this.scrollParent) {
      const parentRect = this.scrollParent.getBoundingClientRect();
      viewTop = parentRect.top;
      viewBottom = parentRect.bottom;
    }

    if (this.thead) {
      const floatingHeader = rect.top < viewTop && contentBottom > viewTop;
      if (floatingHeader) {
        if (!this.header.hasAttribute("data-visible")) this.refreshHeader();
        const headerHeight = this.thead.offsetHeight;
        this.header.style.left = `${rect.left}px`;
        this.header.style.width = `${rect.width}px`;
        // As the table's end scrolls up to meet the header, push the header up with it so it
        // leaves with the table rather than hovering over the content below. Its top can rise
        // above the scroll area's top edge — but the clone lives on `document.body`, where the
        // scroll area can't clip it, so it would otherwise paint over the navbar/chrome above.
        // Pin the top no higher than `viewTop` and clip the overshoot, so the header slides up
        // under the top edge instead.
        const top = contentBottom - headerHeight;
        const clipTop = Math.max(0, viewTop - top);
        this.header.style.top = `${Math.min(viewTop, top)}px`;
        this.header.style.clipPath =
          clipTop > 0 ? `inset(${clipTop}px 0 0 0)` : "";
        this.header.setAttribute("data-visible", "");
      } else {
        this.header.removeAttribute("data-visible");
      }
    }

    const floating =
      scrollable && contentBottom > viewBottom && rect.top < viewBottom;

    if (this.overlayBar) {
      if (custom) {
        // While the table extends below the viewport, pin the bar to the viewport bottom — the
        // same behavior the proxy scrollbar provides in webkit browsers. Otherwise it settles
        // into the lane below the body via its stylesheet position.
        if (floating) {
          this.overlayBar.style.position = "fixed";
          this.overlayBar.style.left = `${rect.left + 8}px`;
          this.overlayBar.style.right = "auto";
          this.overlayBar.style.width = `${rect.width - 16}px`;
          // `bottom` is measured from the window bottom; offset by the gap between the window
          // and the scroll area's bottom so the bar sits at the scroll area's edge.
          this.overlayBar.style.bottom = `${window.innerHeight - viewBottom + 2}px`;
        } else {
          this.overlayBar.style.position = "";
          this.overlayBar.style.left = "";
          this.overlayBar.style.right = "";
          this.overlayBar.style.width = "";
          this.overlayBar.style.bottom = "";
        }
        this.overlayBar.setAttribute("data-visible", "");
        this.syncOverlayThumb();
      } else {
        this.overlayBar.removeAttribute("data-visible");
      }
    }

    if (floating && !custom) {
      this.spacer.style.width = `${this.container.scrollWidth}px`;
      this.scrollbar.style.left = `${rect.left}px`;
      this.scrollbar.style.width = `${rect.width}px`;
      this.scrollbar.style.bottom = `${window.innerHeight - viewBottom}px`;
      this.scrollbar.setAttribute("data-visible", "");
      if (this.scrollbar.scrollLeft !== this.container.scrollLeft) {
        this.scrollbar.scrollLeft = this.container.scrollLeft;
      }
    } else {
      this.scrollbar.removeAttribute("data-visible");
    }
  },
};
