import { resolve as i } from "@scalar/import";
import { redirectToProxy as f, fetchWithProxyFallback as d } from "@scalar/oas-utils/helpers";
import { reactive as h } from "vue";
import { isUrl as m } from "../../../libs/isUrl.js";
function y() {
  const n = h({
    state: "idle",
    content: null,
    url: null,
    input: null,
    error: null
  });
  async function u() {
    Object.assign(n, {
      state: "idle",
      content: null,
      url: null,
      input: null,
      error: null
    });
  }
  async function s(e, r) {
    if (!e)
      return {
        state: "idle",
        content: null,
        url: null,
        input: e,
        error: null
      };
    try {
      const t = await i(e, {
        fetch: (c) => fetch(r ? f(r, c) : c, {
          cache: "no-cache"
        })
      });
      if (typeof t == "object" && t !== null)
        return {
          state: "idle",
          content: JSON.stringify(t, null, 2),
          url: null,
          error: null
        };
      if (t === void 0)
        return {
          state: "idle",
          content: null,
          url: null,
          input: e,
          error: `Could not find an OpenAPI document in ${e}`
        };
      if (!m(t))
        return {
          state: "idle",
          content: null,
          url: null,
          input: e,
          error: "Oops, we got invalid content for the given URL."
        };
      const o = t, l = await d(o, {
        proxy: r,
        cache: "no-cache"
      });
      return l.ok ? {
        state: "idle",
        content: await l.text(),
        url: o,
        error: null
      } : {
        state: "idle",
        content: null,
        url: null,
        input: e,
        error: `Couldn't fetch ${o}, got error ${[l.status, l.statusText].join(" ").trim()}.`
      };
    } catch (t) {
      return console.error("[prefetchDocument]", t), {
        state: "idle",
        content: null,
        url: null,
        input: e,
        error: t.message
      };
    }
  }
  async function a(e, r) {
    Object.assign(n, {
      state: "loading",
      content: null,
      url: null,
      input: e,
      error: null
    });
    const t = await s(e, r);
    return Object.assign(n, t), t;
  }
  return {
    prefetchResult: n,
    prefetchUrl: a,
    resetPrefetchResult: u
  };
}
export {
  y as useUrlPrefetcher
};
