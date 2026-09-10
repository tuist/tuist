/**
 * Mounts the layout's hooks (navbar, footer) the moment the bundle runs,
 * independent of LiveView.
 *
 * LiveView only runs a `phx-hook` inside a LiveView container once the
 * socket has joined, so on LiveView pages the navbar's menus stayed inert
 * for the whole join (seconds in dev, a round trip in production) while the
 * page already looked ready. The navbar and footer are static markup
 * (`phx-update="ignore"`), so their hooks don't need a LiveView at all:
 * they carry `data-static-hook` instead of `phx-hook`, and this mounts them
 * once per page load with the subset of the hook API they use (`el`,
 * `liveSocket`). Server-push callbacks are no-ops — the layout's hooks
 * are client-only, and Noora's dropdown only pushes when the element
 * declares a `data-on-*` handler, which the footer's doesn't.
 */
export function mountStaticHooks(hooks, liveSocket) {
  for (const el of document.querySelectorAll("[data-static-hook]")) {
    const name = el.dataset.staticHook;
    const hook = hooks[name];
    if (!hook) {
      console.warn(`static hook "${name}" is not registered`);
      continue;
    }
    const instance = Object.create(hook);
    instance.el = el;
    instance.liveSocket = liveSocket;
    instance.pushEvent = () => Promise.resolve();
    instance.pushEventTo = () => Promise.resolve();
    instance.handleEvent = () => () => {};
    instance.removeHandleEvent = () => {};
    instance.mounted?.();
  }
}
