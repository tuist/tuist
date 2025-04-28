'use strict';

const dom = require('@unhead/dom');
const shared = require('@unhead/shared');
const hookable = require('hookable');

const UsesMergeStrategy = /* @__PURE__ */ new Set(["templateParams", "htmlAttrs", "bodyAttrs"]);
const DedupePlugin = shared.defineHeadPlugin({
  hooks: {
    "tag:normalise": ({ tag }) => {
      if (tag.props.hid) {
        tag.key = tag.props.hid;
        delete tag.props.hid;
      }
      if (tag.props.vmid) {
        tag.key = tag.props.vmid;
        delete tag.props.vmid;
      }
      if (tag.props.key) {
        tag.key = tag.props.key;
        delete tag.props.key;
      }
      const generatedKey = shared.tagDedupeKey(tag);
      if (generatedKey && !generatedKey.startsWith("meta:og:") && !generatedKey.startsWith("meta:twitter:")) {
        delete tag.key;
      }
      const dedupe = generatedKey || (tag.key ? `${tag.tag}:${tag.key}` : false);
      if (dedupe)
        tag._d = dedupe;
    },
    "tags:resolve": (ctx) => {
      const deduping = /* @__PURE__ */ Object.create(null);
      for (const tag of ctx.tags) {
        const dedupeKey = (tag.key ? `${tag.tag}:${tag.key}` : tag._d) || shared.hashTag(tag);
        const dupedTag = deduping[dedupeKey];
        if (dupedTag) {
          let strategy = tag?.tagDuplicateStrategy;
          if (!strategy && UsesMergeStrategy.has(tag.tag))
            strategy = "merge";
          if (strategy === "merge") {
            const oldProps = dupedTag.props;
            if (oldProps.style && tag.props.style) {
              if (oldProps.style[oldProps.style.length - 1] !== ";") {
                oldProps.style += ";";
              }
              tag.props.style = `${oldProps.style} ${tag.props.style}`;
            }
            if (oldProps.class && tag.props.class) {
              tag.props.class = `${oldProps.class} ${tag.props.class}`;
            } else if (oldProps.class) {
              tag.props.class = oldProps.class;
            }
            deduping[dedupeKey].props = {
              ...oldProps,
              ...tag.props
            };
            continue;
          } else if (tag._e === dupedTag._e) {
            dupedTag._duped = dupedTag._duped || [];
            tag._d = `${dupedTag._d}:${dupedTag._duped.length + 1}`;
            dupedTag._duped.push(tag);
            continue;
          } else if (shared.tagWeight(tag) > shared.tagWeight(dupedTag)) {
            continue;
          }
        }
        const hasProps = tag.innerHTML || tag.textContent || Object.keys(tag.props).length !== 0;
        if (!hasProps && shared.HasElementTags.has(tag.tag)) {
          delete deduping[dedupeKey];
          continue;
        }
        deduping[dedupeKey] = tag;
      }
      const newTags = [];
      for (const key in deduping) {
        const tag = deduping[key];
        const dupes = tag._duped;
        newTags.push(tag);
        if (dupes) {
          delete tag._duped;
          newTags.push(...dupes);
        }
      }
      ctx.tags = newTags;
      ctx.tags = ctx.tags.filter((t) => !(t.tag === "meta" && (t.props.name || t.props.property) && !t.props.content));
    }
  }
});

const ValidEventTags = /* @__PURE__ */ new Set(["script", "link", "bodyAttrs"]);
const EventHandlersPlugin = shared.defineHeadPlugin((head) => ({
  hooks: {
    "tags:resolve": (ctx) => {
      for (const tag of ctx.tags) {
        if (!ValidEventTags.has(tag.tag)) {
          continue;
        }
        const props = tag.props;
        for (const key in props) {
          if (key[0] !== "o" || key[1] !== "n") {
            continue;
          }
          if (!Object.prototype.hasOwnProperty.call(props, key)) {
            continue;
          }
          const value = props[key];
          if (typeof value !== "function") {
            continue;
          }
          if (head.ssr && shared.NetworkEvents.has(key)) {
            props[key] = `this.dataset.${key}fired = true`;
          } else {
            delete props[key];
          }
          tag._eventHandlers = tag._eventHandlers || {};
          tag._eventHandlers[key] = value;
        }
        if (head.ssr && tag._eventHandlers && (tag.props.src || tag.props.href)) {
          tag.key = tag.key || shared.hashCode(tag.props.src || tag.props.href);
        }
      }
    },
    "dom:renderTag": ({ $el, tag }) => {
      const dataset = $el?.dataset;
      if (!dataset) {
        return;
      }
      for (const k in dataset) {
        if (!k.endsWith("fired")) {
          continue;
        }
        const ek = k.slice(0, -5);
        if (!shared.NetworkEvents.has(ek)) {
          continue;
        }
        tag._eventHandlers?.[ek]?.call($el, new Event(ek.substring(2)));
      }
    }
  }
}));

const DupeableTags = /* @__PURE__ */ new Set(["link", "style", "script", "noscript"]);
const HashKeyedPlugin = shared.defineHeadPlugin({
  hooks: {
    "tag:normalise": ({ tag }) => {
      if (tag.key && DupeableTags.has(tag.tag)) {
        tag.props["data-hid"] = tag._h = shared.hashCode(tag.key);
      }
    }
  }
});

const PayloadPlugin = shared.defineHeadPlugin({
  mode: "server",
  hooks: {
    "tags:beforeResolve": (ctx) => {
      const payload = {};
      let hasPayload = false;
      for (const tag of ctx.tags) {
        if (tag._m !== "server" || tag.tag !== "titleTemplate" && tag.tag !== "templateParams" && tag.tag !== "title") {
          continue;
        }
        payload[tag.tag] = tag.tag === "title" || tag.tag === "titleTemplate" ? tag.textContent : tag.props;
        hasPayload = true;
      }
      if (hasPayload) {
        ctx.tags.push({
          tag: "script",
          innerHTML: JSON.stringify(payload),
          props: { id: "unhead:payload", type: "application/json" }
        });
      }
    }
  }
});

const SortPlugin = shared.defineHeadPlugin({
  hooks: {
    "tags:resolve": (ctx) => {
      for (const tag of ctx.tags) {
        if (typeof tag.tagPriority !== "string") {
          continue;
        }
        for (const { prefix, offset } of shared.SortModifiers) {
          if (!tag.tagPriority.startsWith(prefix)) {
            continue;
          }
          const key = tag.tagPriority.substring(prefix.length);
          const position = ctx.tags.find((tag2) => tag2._d === key)?._p;
          if (position !== void 0) {
            tag._p = position + offset;
            break;
          }
        }
      }
      ctx.tags.sort((a, b) => {
        const aWeight = shared.tagWeight(a);
        const bWeight = shared.tagWeight(b);
        if (aWeight < bWeight) {
          return -1;
        } else if (aWeight > bWeight) {
          return 1;
        }
        return a._p - b._p;
      });
    }
  }
});

const SupportedAttrs = {
  meta: "content",
  link: "href",
  htmlAttrs: "lang"
};
const contentAttrs = ["innerHTML", "textContent"];
const TemplateParamsPlugin = shared.defineHeadPlugin((head) => ({
  hooks: {
    "tags:resolve": (ctx) => {
      const { tags } = ctx;
      let templateParams;
      for (let i = 0; i < tags.length; i += 1) {
        const tag = tags[i];
        if (tag.tag !== "templateParams") {
          continue;
        }
        templateParams = ctx.tags.splice(i, 1)[0].props;
        i -= 1;
      }
      const params = templateParams || {};
      const sep = params.separator || "|";
      delete params.separator;
      params.pageTitle = shared.processTemplateParams(
        // find templateParams
        params.pageTitle || tags.find((tag) => tag.tag === "title")?.textContent || "",
        params,
        sep
      );
      for (const tag of tags) {
        if (tag.processTemplateParams === false) {
          continue;
        }
        const v = SupportedAttrs[tag.tag];
        if (v && typeof tag.props[v] === "string") {
          tag.props[v] = shared.processTemplateParams(tag.props[v], params, sep);
        } else if (tag.processTemplateParams || tag.tag === "titleTemplate" || tag.tag === "title") {
          for (const p of contentAttrs) {
            if (typeof tag[p] === "string")
              tag[p] = shared.processTemplateParams(tag[p], params, sep, tag.tag === "script" && tag.props.type.endsWith("json"));
          }
        }
      }
      head._templateParams = params;
      head._separator = sep;
    },
    "tags:afterResolve": ({ tags }) => {
      let title;
      for (let i = 0; i < tags.length; i += 1) {
        const tag = tags[i];
        if (tag.tag === "title" && tag.processTemplateParams !== false) {
          title = tag;
        }
      }
      if (title?.textContent) {
        title.textContent = shared.processTemplateParams(title.textContent, head._templateParams, head._separator);
      }
    }
  }
}));

const TitleTemplatePlugin = shared.defineHeadPlugin({
  hooks: {
    "tags:resolve": (ctx) => {
      const { tags } = ctx;
      let titleTag;
      let titleTemplateTag;
      for (let i = 0; i < tags.length; i += 1) {
        const tag = tags[i];
        if (tag.tag === "title") {
          titleTag = tag;
        } else if (tag.tag === "titleTemplate") {
          titleTemplateTag = tag;
        }
      }
      if (titleTemplateTag && titleTag) {
        const newTitle = shared.resolveTitleTemplate(
          titleTemplateTag.textContent,
          titleTag.textContent
        );
        if (newTitle !== null) {
          titleTag.textContent = newTitle || titleTag.textContent;
        } else {
          ctx.tags.splice(ctx.tags.indexOf(titleTag), 1);
        }
      } else if (titleTemplateTag) {
        const newTitle = shared.resolveTitleTemplate(
          titleTemplateTag.textContent
        );
        if (newTitle !== null) {
          titleTemplateTag.textContent = newTitle;
          titleTemplateTag.tag = "title";
          titleTemplateTag = void 0;
        }
      }
      if (titleTemplateTag) {
        ctx.tags.splice(ctx.tags.indexOf(titleTemplateTag), 1);
      }
    }
  }
});

const XSSPlugin = shared.defineHeadPlugin({
  hooks: {
    "tags:afterResolve": (ctx) => {
      for (const tag of ctx.tags) {
        if (typeof tag.innerHTML === "string") {
          if (tag.innerHTML && (tag.props.type === "application/ld+json" || tag.props.type === "application/json")) {
            tag.innerHTML = tag.innerHTML.replace(/</g, "\\u003C");
          } else {
            tag.innerHTML = tag.innerHTML.replace(new RegExp(`</${tag.tag}`, "g"), `<\\/${tag.tag}`);
          }
        }
      }
    }
  }
});

let activeHead;
// @__NO_SIDE_EFFECTS__
function createHead(options = {}) {
  const head = createHeadCore(options);
  head.use(dom.DomPlugin());
  return activeHead = head;
}
// @__NO_SIDE_EFFECTS__
function createServerHead(options = {}) {
  return activeHead = createHeadCore(options);
}
function filterMode(mode, ssr) {
  return !mode || mode === "server" && ssr || mode === "client" && !ssr;
}
function createHeadCore(options = {}) {
  const hooks = hookable.createHooks();
  hooks.addHooks(options.hooks || {});
  options.document = options.document || (shared.IsBrowser ? document : void 0);
  const ssr = !options.document;
  const updated = () => {
    head.dirty = true;
    hooks.callHook("entries:updated", head);
  };
  let entryCount = 0;
  let entries = [];
  const plugins = [];
  const head = {
    plugins,
    dirty: false,
    resolvedOptions: options,
    hooks,
    headEntries() {
      return entries;
    },
    use(p) {
      const plugin = typeof p === "function" ? p(head) : p;
      if (!plugin.key || !plugins.some((p2) => p2.key === plugin.key)) {
        plugins.push(plugin);
        filterMode(plugin.mode, ssr) && hooks.addHooks(plugin.hooks || {});
      }
    },
    push(input, entryOptions) {
      delete entryOptions?.head;
      const entry = {
        _i: entryCount++,
        input,
        ...entryOptions
      };
      if (filterMode(entry.mode, ssr)) {
        entries.push(entry);
        updated();
      }
      return {
        dispose() {
          entries = entries.filter((e) => e._i !== entry._i);
          updated();
        },
        // a patch is the same as creating a new entry, just a nice DX
        patch(input2) {
          for (const e of entries) {
            if (e._i === entry._i) {
              e.input = entry.input = input2;
            }
          }
          updated();
        }
      };
    },
    async resolveTags() {
      const resolveCtx = { tags: [], entries: [...entries] };
      await hooks.callHook("entries:resolve", resolveCtx);
      for (const entry of resolveCtx.entries) {
        const resolved = entry.resolvedInput || entry.input;
        entry.resolvedInput = await (entry.transform ? entry.transform(resolved) : resolved);
        if (entry.resolvedInput) {
          for (const tag of await shared.normaliseEntryTags(entry)) {
            const tagCtx = { tag, entry, resolvedOptions: head.resolvedOptions };
            await hooks.callHook("tag:normalise", tagCtx);
            resolveCtx.tags.push(tagCtx.tag);
          }
        }
      }
      await hooks.callHook("tags:beforeResolve", resolveCtx);
      await hooks.callHook("tags:resolve", resolveCtx);
      await hooks.callHook("tags:afterResolve", resolveCtx);
      return resolveCtx.tags;
    },
    ssr
  };
  [
    DedupePlugin,
    PayloadPlugin,
    EventHandlersPlugin,
    HashKeyedPlugin,
    SortPlugin,
    TemplateParamsPlugin,
    TitleTemplatePlugin,
    XSSPlugin,
    ...options?.plugins || []
  ].forEach((p) => head.use(p));
  head.hooks.callHook("init", head);
  return head;
}

const unheadComposablesImports = [
  {
    from: "unhead",
    imports: shared.composableNames
  }
];

function getActiveHead() {
  return activeHead;
}

function useHead(input, options = {}) {
  const head = options.head || getActiveHead();
  return head?.push(input, options);
}

function useHeadSafe(input, options) {
  return useHead(input, {
    ...options,
    transform: shared.whitelistSafeInput
  });
}

const ScriptProxyTarget = Symbol("ScriptProxyTarget");
function scriptProxy() {
}
scriptProxy[ScriptProxyTarget] = true;
function resolveScriptKey(input) {
  return input.key || shared.hashCode(input.src || (typeof input.innerHTML === "string" ? input.innerHTML : ""));
}
function useScript(_input, _options) {
  const input = typeof _input === "string" ? { src: _input } : _input;
  const options = _options || {};
  const head = options.head || getActiveHead();
  if (!head)
    throw new Error("Missing Unhead context.");
  const id = resolveScriptKey(input);
  const prevScript = head._scripts?.[id];
  if (prevScript) {
    prevScript.setupTriggerHandler(options.trigger);
    return prevScript;
  }
  options.beforeInit?.();
  const syncStatus = (s) => {
    script.status = s;
    head.hooks.callHook(`script:updated`, hookCtx);
  };
  shared.ScriptNetworkEvents.forEach((fn) => {
    const _fn = typeof input[fn] === "function" ? input[fn].bind(options.eventContext) : null;
    input[fn] = (e) => {
      syncStatus(fn === "onload" ? "loaded" : fn === "onerror" ? "error" : "loading");
      _fn?.(e);
    };
  });
  const _cbs = { loaded: [], error: [] };
  const _registerCb = (key, cb) => {
    if (_cbs[key]) {
      const i = _cbs[key].push(cb);
      return () => _cbs[key]?.splice(i - 1, 1);
    }
    cb(script.instance);
    return () => {
    };
  };
  const loadPromise = new Promise((resolve) => {
    if (head.ssr)
      return;
    const emit = (api) => requestAnimationFrame(() => resolve(api));
    const _ = head.hooks.hook("script:updated", ({ script: script2 }) => {
      const status = script2.status;
      if (script2.id === id && (status === "loaded" || status === "error")) {
        if (status === "loaded") {
          if (typeof options.use === "function") {
            const api = options.use();
            if (api) {
              emit(api);
            }
          } else {
            emit({});
          }
        } else if (status === "error") {
          resolve(false);
        }
        _();
      }
    });
  });
  const script = Object.assign(loadPromise, {
    instance: !head.ssr && options?.use?.() || null,
    proxy: null,
    id,
    status: "awaitingLoad",
    remove() {
      script._triggerAbortController?.abort();
      script._triggerPromises = [];
      if (script.entry) {
        script.entry.dispose();
        script.entry = void 0;
        syncStatus("removed");
        delete head._scripts?.[id];
        return true;
      }
      return false;
    },
    load(cb) {
      script._triggerAbortController?.abort();
      script._triggerPromises = [];
      if (!script.entry) {
        syncStatus("loading");
        const defaults = {
          defer: true,
          fetchpriority: "low"
        };
        if (input.src && (input.src.startsWith("http") || input.src.startsWith("//"))) {
          defaults.crossorigin = "anonymous";
          defaults.referrerpolicy = "no-referrer";
        }
        script.entry = head.push({
          script: [{ ...defaults, ...input, key: `script.${id}` }]
        }, options);
      }
      if (cb)
        _registerCb("loaded", cb);
      return loadPromise;
    },
    onLoaded(cb) {
      return _registerCb("loaded", cb);
    },
    onError(cb) {
      return _registerCb("error", cb);
    },
    setupTriggerHandler(trigger) {
      if (script.status !== "awaitingLoad") {
        return;
      }
      if ((typeof trigger === "undefined" || trigger === "client") && !head.ssr || trigger === "server") {
        script.load();
      } else if (trigger instanceof Promise) {
        if (head.ssr) {
          return;
        }
        if (!script._triggerAbortController) {
          script._triggerAbortController = new AbortController();
          script._triggerAbortPromise = new Promise((resolve) => {
            script._triggerAbortController.signal.addEventListener("abort", () => {
              script._triggerAbortController = null;
              resolve();
            });
          });
        }
        script._triggerPromises = script._triggerPromises || [];
        const idx = script._triggerPromises.push(Promise.race([
          trigger.then((v) => typeof v === "undefined" || v ? script.load : void 0),
          script._triggerAbortPromise
        ]).catch(() => {
        }).then((res2) => {
          res2?.();
        }).finally(() => {
          script._triggerPromises?.splice(idx, 1);
        }));
      } else if (typeof trigger === "function") {
        trigger(script.load);
      }
    },
    _cbs
  });
  loadPromise.then((api) => {
    if (api !== false) {
      script.instance = api;
      _cbs.loaded?.forEach((cb) => cb(api));
      _cbs.loaded = null;
    } else {
      _cbs.error?.forEach((cb) => cb());
      _cbs.error = null;
    }
  });
  const hookCtx = { script };
  script.setupTriggerHandler(options.trigger);
  script.$script = script;
  const proxyChain = (instance, accessor, accessors) => {
    return new Proxy((!accessor ? instance : instance?.[accessor]) || scriptProxy, {
      get(_, k, r) {
        head.hooks.callHook("script:instance-fn", { script, fn: k, exists: k in _ });
        if (!accessor) {
          const stub = options.stub?.({ script, fn: k });
          if (stub)
            return stub;
        }
        if (_ && k in _ && typeof _[k] !== "undefined") {
          return Reflect.get(_, k, r);
        }
        if (k === Symbol.iterator) {
          return [][Symbol.iterator];
        }
        return proxyChain(accessor ? instance?.[accessor] : instance, k, accessors || [k]);
      },
      async apply(_, _this, args) {
        if (head.ssr && _[ScriptProxyTarget])
          return;
        let instance2;
        const access = (fn2) => {
          instance2 = fn2 || instance2;
          for (let i = 0; i < (accessors || []).length; i++) {
            const k = (accessors || [])[i];
            fn2 = fn2?.[k];
          }
          return fn2;
        };
        let fn = access(script.instance);
        if (!fn) {
          fn = await new Promise((resolve) => {
            script.onLoaded((api) => {
              resolve(access(api));
            });
          });
        }
        return typeof fn === "function" ? Reflect.apply(fn, instance2, args) : fn;
      }
    });
  };
  script.proxy = proxyChain(script.instance);
  const res = new Proxy(script, {
    get(_, k) {
      const target = k in script || String(k)[0] === "_" ? script : script.proxy;
      if (k === "then" || k === "catch") {
        return script[k].bind(script);
      }
      return Reflect.get(target, k, target);
    }
  });
  head._scripts = Object.assign(head._scripts || {}, { [id]: res });
  return res;
}

function useSeoMeta(input, options) {
  const { title, titleTemplate, ...meta } = input;
  return useHead({
    title,
    titleTemplate,
    // we need to input the meta so the reactivity will be resolved
    // @ts-expect-error runtime type
    _flatMeta: meta
  }, {
    ...options,
    transform(t) {
      const meta2 = shared.unpackMeta({ ...t._flatMeta });
      delete t._flatMeta;
      return {
        // @ts-expect-error runtime type
        ...t,
        meta: meta2
      };
    }
  });
}

function useServerHead(input, options = {}) {
  return useHead(input, { ...options, mode: "server" });
}

function useServerHeadSafe(input, options = {}) {
  return useHeadSafe(input, { ...options, mode: "server" });
}

function useServerSeoMeta(input, options) {
  return useSeoMeta(input, {
    ...options,
    mode: "server"
  });
}

const importRe = /@import/;
// @__NO_SIDE_EFFECTS__
function CapoPlugin(options) {
  return shared.defineHeadPlugin({
    hooks: {
      "tags:beforeResolve": ({ tags }) => {
        for (const tag of tags) {
          if (tag.tagPosition && tag.tagPosition !== "head")
            continue;
          tag.tagPriority = tag.tagPriority || shared.tagWeight(tag);
          if (tag.tagPriority !== 100)
            continue;
          const isTruthy = (val) => val === "" || val === true;
          const isScript = tag.tag === "script";
          const isLink = tag.tag === "link";
          if (isScript && isTruthy(tag.props.async)) {
            tag.tagPriority = 30;
          } else if (tag.tag === "style" && tag.innerHTML && importRe.test(tag.innerHTML)) {
            tag.tagPriority = 40;
          } else if (isScript && tag.props.src && !isTruthy(tag.props.defer) && !isTruthy(tag.props.async) && tag.props.type !== "module" && !tag.props.type?.endsWith("json")) {
            tag.tagPriority = 50;
          } else if (isLink && tag.props.rel === "stylesheet" || tag.tag === "style") {
            tag.tagPriority = 60;
          } else if (isLink && (tag.props.rel === "preload" || tag.props.rel === "modulepreload")) {
            tag.tagPriority = 70;
          } else if (isScript && isTruthy(tag.props.defer) && tag.props.src && !isTruthy(tag.props.async)) {
            tag.tagPriority = 80;
          } else if (isLink && (tag.props.rel === "prefetch" || tag.props.rel === "dns-prefetch" || tag.props.rel === "prerender")) {
            tag.tagPriority = 90;
          }
        }
        options?.track && tags.push({
          tag: "htmlAttrs",
          props: {
            "data-capo": ""
          }
        });
      }
    }
  });
}

// @__NO_SIDE_EFFECTS__
function HashHydrationPlugin() {
  return shared.defineHeadPlugin({});
}

exports.composableNames = shared.composableNames;
exports.CapoPlugin = CapoPlugin;
exports.HashHydrationPlugin = HashHydrationPlugin;
exports.createHead = createHead;
exports.createHeadCore = createHeadCore;
exports.createServerHead = createServerHead;
exports.getActiveHead = getActiveHead;
exports.resolveScriptKey = resolveScriptKey;
exports.unheadComposablesImports = unheadComposablesImports;
exports.useHead = useHead;
exports.useHeadSafe = useHeadSafe;
exports.useScript = useScript;
exports.useSeoMeta = useSeoMeta;
exports.useServerHead = useServerHead;
exports.useServerHeadSafe = useServerHeadSafe;
exports.useServerSeoMeta = useServerSeoMeta;
