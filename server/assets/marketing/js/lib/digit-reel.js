/*
 * Odometer figures: renders a formatted number into `el` as one column per
 * character, where each digit column holds a reel of glyphs (0-9 twice) slid
 * by the CSS custom property --i. Changing the figure rolls each digit up
 * (rising values) or down (falling values) the shortest way to its new
 * glyph, rippling from the rightmost digit. While a reel moves it carries
 * data-rolling, so the stylesheet can blur it slightly in motion.
 *
 * The figure's columns are rebuilt only when the shape changes (digit count
 * or separator positions), showing the new value at once; otherwise the
 * existing reels roll in place.
 *
 * Modelled on the cache globe page's region counters.
 */

const ROLL_MS = 600;
const STAGGER_MS = 30;

function snapReel(reel, index) {
  reel.dataset.snap = "";
  reel.style.setProperty("--i", String(index));
  reel.getBoundingClientRect();
  delete reel.dataset.snap;
}

function build(el, chars) {
  el.replaceChildren(
    ...chars.map((char) => {
      const column = document.createElement("span");
      column.dataset.part = "char";
      if (/\d/.test(char)) {
        column.dataset.digit = "";
        const reel = document.createElement("span");
        reel.dataset.part = "reel";
        reel.style.setProperty("--i", "0");
        for (let i = 0; i < 20; i++) {
          const glyph = document.createElement("span");
          glyph.textContent = String(i % 10);
          reel.appendChild(glyph);
        }
        column.appendChild(reel);
      } else {
        column.textContent = char === " " ? " " : char;
      }
      return column;
    }),
  );
}

export function setReel(el, text) {
  if (!el) return;
  const chars = Array.from(text);
  const shape = chars.map((char) => (/\d/.test(char) ? "#" : char)).join("");
  const digits = chars.filter((char) => /\d/.test(char));
  const figure = digits.join("");
  if (el.dataset.shape !== shape) {
    // A freshly built figure (first render, or a new digit count) shows its
    // value at once; only later changes roll, so it never counts up from 0.
    el.dataset.shape = shape;
    el.dataset.figure = figure;
    build(el, chars);
    el.querySelectorAll('[data-part="reel"]').forEach((reel, index) => snapReel(reel, Number(digits[index])));
    return;
  }

  const reels = el.querySelectorAll('[data-part="reel"]');
  const previous = el.dataset.figure || "";
  el.dataset.figure = figure;
  const rising = figure.length !== previous.length ? figure.length > previous.length : figure >= previous;

  reels.forEach((reel, index) => {
    const target = Number(digits[index]);
    const current = Number(reel.style.getPropertyValue("--i")) || 0;
    const shown = current % 10;
    if (target === shown) return;
    let next;
    if (rising) {
      next = current + ((target - shown + 10) % 10);
      if (next >= 20) {
        snapReel(reel, current - 10);
        next -= 10;
      }
    } else {
      next = current - ((shown - target + 10) % 10);
      if (next < 0) {
        snapReel(reel, current + 10);
        next += 10;
      }
    }
    const delay = (reels.length - 1 - index) * STAGGER_MS;
    reel.style.transitionDelay = `${delay}ms`;
    reel.style.setProperty("--i", String(next));
    reel.dataset.rolling = "";
    clearTimeout(reel.rollTimer);
    reel.rollTimer = setTimeout(() => delete reel.dataset.rolling, delay + ROLL_MS * 0.6);
  });
}
