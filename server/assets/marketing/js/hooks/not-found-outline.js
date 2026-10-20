/*
 * Marketing 404: the eyebrow that turns the page into its outline view.
 *
 * The "Error 404" eyebrow is a button. Hovering it opens a spotlight
 * around the cursor in which the page shows as its outline view
 * (outline-mode.css: the navbar, the hero and the footer drawn as
 * strokes, like Figma's outline view); pressing it makes the spotlight
 * grow until it covers the page, which stays in outline view until
 * pressed again or Escape.
 *
 * The spotlight is an overlay: a copy of the three regions, cloned at the
 * positions they occupy on the page inside a wrapper the hook keeps
 * translated by the scroll, under a fixed, viewport-sized host (so the
 * mask is only ever rasterized over what can be seen, not the whole
 * page), carrying the outline attribute and
 * masked to a circle whose edge is an ordered dither (not-found-portal.js:
 * stepped discs intersected with Bayer tiles; the stylesheet's soft
 * gradient where mask compositing is missing) with its centre and radius
 * as custom properties; the hook eases the radius itself, frame by frame,
 * so it behaves the same everywhere. Along that edge the page's glyphs
 * dissolve into dither cells on a canvas over the overlay, more the
 * faster the circle moves (PortalDither). It
 * takes no pointer events and is inert, so the page under it keeps
 * working and nothing in the copy can be focused or reached; its copies
 * live in a shadow tree so their ids never duplicate the page's. It is
 * built once, on first use, and kept — at radius zero it is not rendered
 * at all — so opening the spotlight costs nothing but a few style writes; it is
 * rebuilt when the page resizes, and its copy of the sticky navbar is
 * kept where the real one is as the page scrolls. Subtrees that never
 * show in the outline view (menus, canvases) are left out of the copy.
 * Once the circle covers the page the outline
 * attribute goes on <html> instead — the same stylesheet draws the same
 * pixels — and the overlay hides. Unpinning does the reverse: the overlay
 * shows at full size over the normal page and shrinks away. In the
 * pinned view the navbar is inert — a drawing of a navbar, not a navbar:
 * nothing in it opens, focuses or follows a link.
 */

import { PortalDither, applyDitherMask, positionDitherMask, supportsDitherMask } from "./not-found-portal.js";

const ATTRIBUTE = "data-marketing-outline";
const OVERLAY_ID = "marketing-outline-overlay";
const NAVBAR = "#marketing-navbar";
const REGIONS = [NAVBAR, "#marketing-not-found", "#marketing-footer"];
// Never visible in the outline view, so not worth copying: menu panels,
// the mobile menu, dropdown positioners, every canvas and video.
const PRUNE = '[data-part="viewport"], [data-part="mobile-menus"], [data-part="positioner"], canvas, video, script';
// The hover spotlight: from the eyebrow it reaches the button but stops
// short of the dithered "404" below it, so its fading edge never blends
// strokes over the dither.
const SPOT_RADIUS = 170; // px (its edge dithers away over the last FEATHER px)
const FEATHER = 96; // px, set on the overlay as --marketing-outline-feather
// Timing. Every move is the spotlight's circle morphing on screen, so
// all of them are ease-in-out — a gentle start and a gentle settle — and
// all run on the circle's AREA rather than its radius: what the eye sees
// is how much of the page the skeleton covers, and area grows with the
// radius squared, so a radius eased the usual way looks finished a third
// of the way in. This is a marketing page's one flourish, so the moves
// take their time and read as deliberate: the hover spotlight blooms in
// under a second, the page-covering moves in about one. The hover
// spotlight also waits a beat before opening so a cursor merely passing
// over the eyebrow does not flash it, and its open runs on a steeper
// curve than the other moves: a long, slow lead-in where the first cells
// of the page barely start to peel, then the bloom, then a soft settle.
const HOVER_INTENT_MS = 140;
const SPOT_OPEN_MS = 900;
const SPOT_CLOSE_MS = 500;
const GROW_MS = 1200;
const SHRINK_MS = 1000;
const easeInOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
const easeInOutQuint = (t) => (t < 0.5 ? 16 * t ** 5 : 1 - (-2 * t + 2) ** 5 / 2);

export const NotFoundOutline = {
  mounted() {
    this.eyebrow = this.el.querySelector('[data-part="eyebrow"]');
    if (!this.eyebrow) return;
    this.pinned = false;
    this.hovering = false;
    this.overlay = null;
    this.navbarCopy = null;
    this.tween = null;
    this.intent = null;
    this.radius = 0;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // The dissolving glyphs: motion for its own sake, so none under
    // reduced motion (the dithered edge stays: it is a still pattern).
    this.portal = this.reduced ? null : new PortalDither();
    this.x = 0;
    this.y = 0;

    this.onEnter = (e) => {
      if (e.pointerType && e.pointerType !== "mouse") return;
      this.hovering = true;
      if (this.pinned) return;
      this.place(e);
      // The intent wait is time to measure the text the specks will need.
      if (this.portal) this.portal.prepare();
      clearTimeout(this.intent);
      this.intent = setTimeout(() => {
        this.intent = null;
        if (this.hovering && !this.pinned) this.openSpot();
      }, HOVER_INTENT_MS);
    };
    this.onMove = (e) => {
      if (!this.hovering || this.pinned) return;
      this.place(e);
      // Only the centre follows the pointer; the radius is the tween's
      // (re-clipping at the full radius here would snap the spotlight open
      // on the first move once the overlay exists).
      if (this.overlay && this.radius > 0) this.clip(this.radius);
    };
    this.onLeave = () => {
      this.hovering = false;
      clearTimeout(this.intent);
      this.intent = null;
      if (this.pinned) return;
      this.closeSpot();
    };
    this.onClick = (e) => {
      clearTimeout(this.intent);
      this.intent = null;
      this.place(e);
      if (this.pinned) this.unpin();
      else this.pin();
    };
    this.onKey = (e) => {
      if (e.key !== "Escape" || !this.pinned) return;
      this.placeAtEyebrow();
      this.unpin();
    };
    this.onScroll = () => {
      if (!this.overlay || this.radius === 0) return;
      this.syncNavbar();
      this.syncScroll();
      this.clip(this.radius);
    };
    this.eyebrow.addEventListener("pointerenter", this.onEnter);
    this.eyebrow.addEventListener("pointermove", this.onMove);
    this.eyebrow.addEventListener("pointerleave", this.onLeave);
    this.eyebrow.addEventListener("click", this.onClick);
    window.addEventListener("keydown", this.onKey);
    window.addEventListener("scroll", this.onScroll, { passive: true });
    // A resize moves everything: the copy is stale, so it goes; the next
    // use builds it again (at once if it is showing).
    this.resizer = new ResizeObserver(() => {
      if (this.portal) this.portal.invalidate();
      if (!this.overlay) return;
      const radius = this.radius;
      this.dropOverlay();
      if (radius > 0) {
        this.buildOverlay();
        this.clip(radius);
      }
    });
    this.resizer.observe(document.body);
  },

  destroyed() {
    if (!this.eyebrow) return;
    this.eyebrow.removeEventListener("pointerenter", this.onEnter);
    this.eyebrow.removeEventListener("pointermove", this.onMove);
    this.eyebrow.removeEventListener("pointerleave", this.onLeave);
    this.eyebrow.removeEventListener("click", this.onClick);
    window.removeEventListener("keydown", this.onKey);
    window.removeEventListener("scroll", this.onScroll);
    if (this.resizer) this.resizer.disconnect();
    clearTimeout(this.intent);
    this.dropOverlay();
    if (this.portal) this.portal.destroy();
    document.documentElement.removeAttribute(ATTRIBUTE);
    this.setNavbarInert(false);
  },

  // The lock follows the pinned state and nothing else, so it can never
  // outlive it.
  setNavbarInert(on) {
    const navbar = document.querySelector(NAVBAR);
    if (navbar) navbar.toggleAttribute("inert", on && this.pinned);
  },

  // ------------------------------------------------------------ pointer

  // The spotlight's centre, in page coordinates (the overlay's space).
  place(e) {
    if (typeof e.clientX !== "number" || (e.clientX === 0 && e.clientY === 0 && e.detail === 0)) {
      this.placeAtEyebrow();
      return;
    }
    this.x = e.clientX + window.scrollX;
    this.y = e.clientY + window.scrollY;
  },

  placeAtEyebrow() {
    const r = this.eyebrow.getBoundingClientRect();
    this.x = r.left + r.width / 2 + window.scrollX;
    this.y = r.top + r.height / 2 + window.scrollY;
  },

  // ------------------------------------------------------------ overlay

  // The page's three regions, cloned where they sit, under one masked,
  // pointer-transparent layer carrying the outline attribute.
  buildOverlay() {
    this.dropOverlay();
    const doc = document.documentElement;
    const width = Math.max(doc.scrollWidth, doc.clientWidth);
    const height = Math.max(doc.scrollHeight, doc.clientHeight);
    const overlay = document.createElement("div");
    overlay.id = OVERLAY_ID;
    overlay.setAttribute("aria-hidden", "true");
    // A drawing of the page, not the page: nothing in it can be focused,
    // clicked or reached by assistive tech.
    overlay.setAttribute("inert", "");
    overlay.style.setProperty("--marketing-outline-feather", `${FEATHER}px`);
    if (supportsDitherMask()) applyDitherMask(overlay, FEATHER);
    // The copies live in a shadow tree. Ids are scoped to it, so the copy
    // keeps the ids the stylesheets key layout off (the three regions, the
    // footer's theme switcher) without duplicating the page's, and label
    // and aria references on the page keep resolving to the real elements.
    // The page's stylesheets are linked into the tree (they come from
    // cache) so the copy lays out exactly like the original; the outline
    // attribute goes on a wrapper inside it, where those stylesheets can
    // see it. The mask and the custom properties stay on the host, which
    // the outline stylesheet styles by id from outside. The wrapper is
    // page-sized and translated by the scroll (syncScroll), so the copies
    // keep page coordinates while the host is only the viewport.
    const shadow = overlay.attachShadow({ mode: "open" });
    for (const link of document.querySelectorAll('link[rel="stylesheet"]')) shadow.append(link.cloneNode());
    const regions = document.createElement("div");
    regions.setAttribute(ATTRIBUTE, "");
    regions.style.position = "absolute";
    regions.style.top = "0";
    regions.style.left = "0";
    regions.style.width = `${width}px`;
    regions.style.height = `${height}px`;
    shadow.append(regions);
    this.regions = regions;
    for (const selector of REGIONS) {
      const el = document.querySelector(selector);
      if (!el) continue;
      const r = el.getBoundingClientRect();
      const copy = el.cloneNode(true);
      for (const node of copy.querySelectorAll(PRUNE)) node.remove();
      // Ids stay on the copy (see above): inside the shadow tree they clash
      // with nothing.
      copy.style.position = "absolute";
      copy.style.top = `${r.top + window.scrollY}px`;
      copy.style.left = `${r.left + window.scrollX}px`;
      copy.style.width = `${r.width}px`;
      copy.style.height = `${r.height}px`;
      copy.style.margin = "0";
      copy.style.boxSizing = "border-box";
      regions.append(copy);
      if (selector === NAVBAR) this.navbarCopy = copy;
    }
    document.body.append(overlay);
    this.overlay = overlay;
    this.syncScroll();
    return overlay;
  },

  ensureOverlay() {
    if (!this.overlay) this.buildOverlay();
    this.syncNavbar();
    this.syncScroll();
  },

  // The host is the viewport; the copies inside are the page. Keep them
  // lined up with the real page as it scrolls, and keep the dither tiles
  // on the page's grid rather than the viewport's.
  syncScroll() {
    if (!this.overlay) return;
    const sx = window.scrollX;
    const sy = window.scrollY;
    this.regions.style.transform = `translate(${-sx}px, ${-sy}px)`;
    if (supportsDitherMask()) positionDitherMask(this.overlay, sx, sy);
  },

  // The real navbar is sticky, so its place on the page depends on the
  // scroll; its copy follows it.
  syncNavbar() {
    const navbar = document.querySelector(NAVBAR);
    if (!navbar || !this.navbarCopy) return;
    const r = navbar.getBoundingClientRect();
    this.navbarCopy.style.top = `${r.top + window.scrollY}px`;
  },

  dropOverlay() {
    this.stopTween();
    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
      this.navbarCopy = null;
      this.regions = null;
    }
    this.radius = 0;
    if (!this.pinned) this.setNavbarInert(false);
  },

  // Invisible at radius zero, and kept for next time.
  hideOverlay() {
    this.stopTween();
    this.clip(0);
    if (!this.pinned) this.setNavbarInert(false);
  },

  // At radius zero the overlay is also taken out of rendering entirely:
  // kept in the DOM for next time, but not as a page-sized layer.
  clip(radius) {
    this.radius = radius;
    if (!this.overlay) return;
    this.overlay.style.display = radius > 0 ? "" : "none";
    // The centre is kept in page coordinates; the mask wants it in the
    // viewport's.
    this.overlay.style.setProperty("--marketing-outline-x", `${this.x - window.scrollX}px`);
    this.overlay.style.setProperty("--marketing-outline-y", `${this.y - window.scrollY}px`);
    this.overlay.style.setProperty("--marketing-outline-r", `${radius}px`);
    // Specks only at spotlight size: the moves over and off the page
    // leave no remnants behind.
    if (this.portal) this.portal.set(this.x, this.y, radius, FEATHER, radius <= SPOT_RADIUS + 1);
  },

  // Radius that covers the whole viewport from the spotlight's centre
  // (the overlay is only ever the viewport; once covered, the page itself
  // carries the outline view).
  coverRadius() {
    const x = this.x - window.scrollX;
    const y = this.y - window.scrollY;
    const w = window.innerWidth;
    const h = window.innerHeight;
    return Math.hypot(Math.max(x, w - x), Math.max(y, h - y)) + FEATHER + 8;
  },

  stopTween() {
    if (this.tween) cancelAnimationFrame(this.tween);
    this.tween = null;
  },

  // Ease the circle's area from where it is to `radius`'s over `ms`,
  // frame by frame (on `ease`, ease-in-out cubic unless given), then run
  // `then`. Retargetable: a new call starts from the current radius, so a
  // change of mind mid-move carries on from where the circle is. Under
  // reduced motion it just jumps.
  animateTo(radius, then, ms, ease = easeInOutCubic) {
    const overlay = this.overlay;
    if (!overlay) return;
    this.stopTween();
    if (this.reduced) {
      this.clip(radius);
      then();
      return;
    }
    const from = this.radius;
    const start = performance.now();
    const frame = (now) => {
      if (this.overlay !== overlay) return;
      const t = Math.min(1, (now - start) / ms);
      const eased = ease(t);
      this.clip(Math.sqrt(from * from + (radius * radius - from * from) * eased));
      if (t < 1) {
        this.tween = requestAnimationFrame(frame);
        return;
      }
      this.tween = null;
      then();
    };
    this.tween = requestAnimationFrame(frame);
  },

  // -------------------------------------------------------------- states

  openSpot() {
    this.ensureOverlay();
    this.animateTo(SPOT_RADIUS, () => {}, SPOT_OPEN_MS, easeInOutQuint);
  },

  closeSpot() {
    if (!this.overlay || this.radius === 0) return;
    this.animateTo(0, () => this.hideOverlay(), SPOT_CLOSE_MS);
  },

  // The spotlight grows over the page; then the page itself carries the
  // outline view. The navbar is locked from the first moment — on touch
  // there is no spotlight before this, and a menu opened during the grow
  // would be live under the drawing.
  pin() {
    this.pinned = true;
    this.eyebrow.setAttribute("aria-pressed", "true");
    this.setNavbarInert(true);
    this.ensureOverlay();
    this.animateTo(
      this.coverRadius(),
      () => {
        document.documentElement.setAttribute(ATTRIBUTE, "");
        this.hideOverlay();
      },
      GROW_MS,
    );
  },

  // The outline view goes back to being an overlay over the normal page
  // and shrinks away. The navbar comes back to life right here, not when
  // the shrink ends: a shrink can be cut short (the pointer leaving the
  // eyebrow retargets it), and its completion must not be what unlocks
  // the page.
  unpin() {
    this.pinned = false;
    this.eyebrow.setAttribute("aria-pressed", "false");
    this.ensureOverlay();
    this.clip(this.coverRadius());
    document.documentElement.removeAttribute(ATTRIBUTE);
    this.setNavbarInert(false);
    this.animateTo(
      this.hovering ? SPOT_RADIUS : 0,
      () => {
        if (!this.hovering) this.hideOverlay();
      },
      SHRINK_MS,
    );
  },
};
