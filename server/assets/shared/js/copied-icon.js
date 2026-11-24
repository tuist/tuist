// Noora's check icon (noora/lib/noora/icons/check.svg). Copy buttons show it
// in place of their copy icon after a successful copy, like the code blocks
// on the blog and the docs.
const CHECK_ICON_PATH =
  '<path d="M19.4697 6.46967C19.7626 6.17678 20.2373 6.17678 20.5302 6.46967C20.8231 6.76256 20.8231 7.23732 20.5302 7.53022L10.5302 17.5302C10.2373 17.8231 9.76256 17.8231 9.46967 17.5302L4.46967 12.5302C4.17678 12.2373 4.17678 11.7626 4.46967 11.4697C4.76256 11.1768 5.23732 11.1768 5.53022 11.4697L9.99994 15.9394L19.4697 6.46967Z" fill="currentColor"/>';

const timers = new WeakMap();

/**
 * Swaps the first Noora copy icon inside `container` for a check for
 * `durationMs`, and marks the container with `data-copied` meanwhile.
 * Repeated calls restart the timer instead of restoring mid-flash.
 */
export function flashCopiedIcon(container, durationMs = 2000) {
  const icon = container?.querySelector("svg.icon-tabler-copy");
  if (!icon) return;

  const state = timers.get(container);
  if (state) {
    clearTimeout(state.timer);
  } else {
    timers.set(container, { markup: icon.innerHTML });
    icon.innerHTML = CHECK_ICON_PATH;
  }
  container.setAttribute("data-copied", "");

  timers.get(container).timer = setTimeout(() => {
    const { markup } = timers.get(container);
    timers.delete(container);
    container.removeAttribute("data-copied");
    icon.innerHTML = markup;
  }, durationMs);
}
