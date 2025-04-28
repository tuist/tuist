'use strict';

const shared = require('@unhead/shared');

async function renderDOMHead(head, options = {}) {
  const dom = options.document || head.resolvedOptions.document;
  if (!dom || !head.dirty)
    return;
  const beforeRenderCtx = { shouldRender: true, tags: [] };
  await head.hooks.callHook("dom:beforeRender", beforeRenderCtx);
  if (!beforeRenderCtx.shouldRender)
    return;
  if (head._domUpdatePromise) {
    return head._domUpdatePromise;
  }
  head._domUpdatePromise = new Promise(async (resolve) => {
    const tags = (await head.resolveTags()).map((tag) => ({
      tag,
      id: shared.HasElementTags.has(tag.tag) ? shared.hashTag(tag) : tag.tag,
      shouldRender: true
    }));
    let state = head._dom;
    if (!state) {
      state = {
        elMap: { htmlAttrs: dom.documentElement, bodyAttrs: dom.body }
      };
      const takenDedupeKeys = /* @__PURE__ */ new Set();
      for (const key of ["body", "head"]) {
        const children = dom[key]?.children;
        for (const c of children) {
          const tag = c.tagName.toLowerCase();
          if (!shared.HasElementTags.has(tag)) {
            continue;
          }
          const t = {
            tag,
            props: await shared.normaliseProps(
              c.getAttributeNames().reduce((props, name) => ({ ...props, [name]: c.getAttribute(name) }), {})
            ),
            innerHTML: c.innerHTML
          };
          const dedupeKey = shared.tagDedupeKey(t);
          let d = dedupeKey;
          let i = 1;
          while (d && takenDedupeKeys.has(d))
            d = `${dedupeKey}:${i++}`;
          if (d) {
            t._d = d;
            takenDedupeKeys.add(d);
          }
          state.elMap[c.getAttribute("data-hid") || shared.hashTag(t)] = c;
        }
      }
    }
    state.pendingSideEffects = { ...state.sideEffects };
    state.sideEffects = {};
    function track(id, scope, fn) {
      const k = `${id}:${scope}`;
      state.sideEffects[k] = fn;
      delete state.pendingSideEffects[k];
    }
    function trackCtx({ id, $el, tag }) {
      const isAttrTag = tag.tag.endsWith("Attrs");
      state.elMap[id] = $el;
      if (!isAttrTag) {
        if (tag.textContent && tag.textContent !== $el.textContent) {
          $el.textContent = tag.textContent;
        }
        if (tag.innerHTML && tag.innerHTML !== $el.innerHTML) {
          $el.innerHTML = tag.innerHTML;
        }
        track(id, "el", () => {
          state.elMap[id]?.remove();
          delete state.elMap[id];
        });
      }
      if (tag._eventHandlers) {
        for (const k in tag._eventHandlers) {
          if (!Object.prototype.hasOwnProperty.call(tag._eventHandlers, k)) {
            continue;
          }
          if ($el.getAttribute(`data-${k}`) !== "") {
            (tag.tag === "bodyAttrs" ? dom.defaultView : $el).addEventListener(
              // onload -> load
              k.substring(2),
              tag._eventHandlers[k].bind($el)
            );
            $el.setAttribute(`data-${k}`, "");
          }
        }
      }
      for (const k in tag.props) {
        if (!Object.prototype.hasOwnProperty.call(tag.props, k)) {
          continue;
        }
        const value = tag.props[k];
        const ck = `attr:${k}`;
        if (k === "class") {
          if (!value) {
            continue;
          }
          for (const c of value.split(" ")) {
            isAttrTag && track(id, `${ck}:${c}`, () => $el.classList.remove(c));
            !$el.classList.contains(c) && $el.classList.add(c);
          }
        } else if (k === "style") {
          if (!value) {
            continue;
          }
          for (const c of value.split(";")) {
            const propIndex = c.indexOf(":");
            const k2 = c.substring(0, propIndex).trim();
            const v = c.substring(propIndex + 1).trim();
            track(id, `${ck}:${k2}`, () => {
              $el.style.removeProperty(k2);
            });
            $el.style.setProperty(k2, v);
          }
        } else {
          $el.getAttribute(k) !== value && $el.setAttribute(k, value === true ? "" : String(value));
          isAttrTag && track(id, ck, () => $el.removeAttribute(k));
        }
      }
    }
    const pending = [];
    const frag = {
      bodyClose: void 0,
      bodyOpen: void 0,
      head: void 0
    };
    for (const ctx of tags) {
      const { tag, shouldRender, id } = ctx;
      if (!shouldRender)
        continue;
      if (tag.tag === "title") {
        dom.title = tag.textContent;
        continue;
      }
      ctx.$el = ctx.$el || state.elMap[id];
      if (ctx.$el) {
        trackCtx(ctx);
      } else if (shared.HasElementTags.has(tag.tag)) {
        pending.push(ctx);
      }
    }
    for (const ctx of pending) {
      const pos = ctx.tag.tagPosition || "head";
      ctx.$el = dom.createElement(ctx.tag.tag);
      trackCtx(ctx);
      frag[pos] = frag[pos] || dom.createDocumentFragment();
      frag[pos].appendChild(ctx.$el);
    }
    for (const ctx of tags)
      await head.hooks.callHook("dom:renderTag", ctx, dom, track);
    frag.head && dom.head.appendChild(frag.head);
    frag.bodyOpen && dom.body.insertBefore(frag.bodyOpen, dom.body.firstChild);
    frag.bodyClose && dom.body.appendChild(frag.bodyClose);
    for (const k in state.pendingSideEffects) {
      state.pendingSideEffects[k]();
    }
    head._dom = state;
    await head.hooks.callHook("dom:rendered", { renders: tags });
    resolve();
  }).finally(() => {
    head._domUpdatePromise = void 0;
    head.dirty = false;
  });
  return head._domUpdatePromise;
}

function debouncedRenderDOMHead(head, options = {}) {
  const fn = options.delayFn || ((fn2) => setTimeout(fn2, 10));
  return head._domDebouncedUpdatePromise = head._domDebouncedUpdatePromise || new Promise((resolve) => fn(() => {
    return renderDOMHead(head, options).then(() => {
      delete head._domDebouncedUpdatePromise;
      resolve();
    });
  }));
}

// @__NO_SIDE_EFFECTS__
function DomPlugin(options) {
  return shared.defineHeadPlugin((head) => {
    const initialPayload = head.resolvedOptions.document?.head.querySelector('script[id="unhead:payload"]')?.innerHTML || false;
    if (initialPayload) {
      head.push(JSON.parse(initialPayload));
    }
    return {
      mode: "client",
      hooks: {
        "entries:updated": (head2) => {
          debouncedRenderDOMHead(head2, options);
        }
      }
    };
  });
}

exports.DomPlugin = DomPlugin;
exports.debouncedRenderDOMHead = debouncedRenderDOMHead;
exports.renderDOMHead = renderDOMHead;
