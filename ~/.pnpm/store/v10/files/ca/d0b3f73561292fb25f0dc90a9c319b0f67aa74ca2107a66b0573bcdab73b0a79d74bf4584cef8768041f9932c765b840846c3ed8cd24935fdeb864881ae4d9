'use strict';

var anatomy$1 = require('@zag-js/anatomy');
var domQuery = require('@zag-js/dom-query');
var core = require('@zag-js/core');
var types = require('@zag-js/types');
var utils = require('@zag-js/utils');

// src/collapsible.anatomy.ts
var anatomy = anatomy$1.createAnatomy("collapsible").parts("root", "trigger", "content", "indicator");
var parts = anatomy.build();

// src/collapsible.dom.ts
var getRootId = (ctx) => ctx.ids?.root ?? `collapsible:${ctx.id}`;
var getContentId = (ctx) => ctx.ids?.content ?? `collapsible:${ctx.id}:content`;
var getTriggerId = (ctx) => ctx.ids?.trigger ?? `collapsible:${ctx.id}:trigger`;
var getContentEl = (ctx) => ctx.getById(getContentId(ctx));

// src/collapsible.connect.ts
function connect(service, normalize) {
  const { state, send, context, scope, prop } = service;
  const visible = state.matches("open") || state.matches("closing");
  const open = state.matches("open");
  const { width, height } = context.get("size");
  const disabled = !!prop("disabled");
  const skip = !context.get("initial") && open;
  const dir = "ltr";
  return {
    disabled,
    visible,
    open,
    measureSize() {
      send({ type: "size.measure" });
    },
    setOpen(nextOpen) {
      const open2 = state.matches("open");
      if (open2 === nextOpen) return;
      send({ type: nextOpen ? "open" : "close" });
    },
    getRootProps() {
      return normalize.element({
        ...parts.root.attrs,
        "data-state": open ? "open" : "closed",
        dir,
        id: getRootId(scope)
      });
    },
    getContentProps() {
      return normalize.element({
        ...parts.content.attrs,
        "data-collapsible": "",
        "data-state": skip ? void 0 : open ? "open" : "closed",
        id: getContentId(scope),
        "data-disabled": domQuery.dataAttr(disabled),
        hidden: !visible,
        style: {
          "--height": height != null ? `${height}px` : void 0,
          "--width": width != null ? `${width}px` : void 0
        }
      });
    },
    getTriggerProps() {
      return normalize.element({
        ...parts.trigger.attrs,
        id: getTriggerId(scope),
        dir,
        type: "button",
        "data-state": open ? "open" : "closed",
        "data-disabled": domQuery.dataAttr(disabled),
        "aria-controls": getContentId(scope),
        "aria-expanded": visible || false,
        onClick(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          send({ type: open ? "close" : "open" });
        }
      });
    },
    getIndicatorProps() {
      return normalize.element({
        ...parts.indicator.attrs,
        dir,
        "data-state": open ? "open" : "closed",
        "data-disabled": domQuery.dataAttr(disabled)
      });
    }
  };
}
var machine = core.createMachine({
  initialState({ prop }) {
    const open = prop("open") || prop("defaultOpen");
    return open ? "open" : "closed";
  },
  context({ bindable }) {
    return {
      size: bindable(() => ({ defaultValue: { height: 0, width: 0 } })),
      initial: bindable(() => ({ defaultValue: false }))
    };
  },
  refs() {
    return {
      cleanup: void 0,
      stylesRef: void 0
    };
  },
  watch({ track, prop, action }) {
    track([() => prop("open")], () => {
      action(["setInitial", "computeSize", "toggleVisibility"]);
    });
  },
  exit: ["clearInitial", "cleanupNode"],
  states: {
    closed: {
      on: {
        "controlled.open": {
          target: "open"
        },
        open: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitial", "computeSize", "invokeOnOpen"]
          }
        ]
      }
    },
    closing: {
      effects: ["trackExitAnimation"],
      on: {
        "controlled.close": {
          target: "closed"
        },
        "controlled.open": {
          target: "open"
        },
        open: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitial", "invokeOnOpen"]
          }
        ],
        close: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnExitComplete"]
          },
          {
            target: "closed",
            actions: ["setInitial", "computeSize", "invokeOnExitComplete"]
          }
        ],
        "animation.end": {
          target: "closed",
          actions: ["invokeOnExitComplete", "clearInitial"]
        }
      }
    },
    open: {
      effects: ["trackEnterAnimation"],
      on: {
        "controlled.close": {
          target: "closing"
        },
        close: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closing",
            actions: ["setInitial", "computeSize", "invokeOnClose"]
          }
        ],
        "size.measure": {
          actions: ["measureSize"]
        },
        "animation.end": {
          actions: ["clearInitial"]
        }
      }
    }
  },
  implementations: {
    guards: {
      isOpenControlled: ({ prop }) => prop("open") != void 0
    },
    effects: {
      trackEnterAnimation: ({ send, scope }) => {
        let cleanup;
        const rafCleanup = domQuery.raf(() => {
          const contentEl = getContentEl(scope);
          if (!contentEl) return;
          const animationName = domQuery.getComputedStyle(contentEl).animationName;
          const hasNoAnimation = !animationName || animationName === "none";
          if (hasNoAnimation) {
            send({ type: "animation.end" });
            return;
          }
          const onEnd = (event) => {
            const target = domQuery.getEventTarget(event);
            if (target === contentEl) {
              send({ type: "animation.end" });
            }
          };
          contentEl.addEventListener("animationend", onEnd);
          cleanup = () => {
            contentEl.removeEventListener("animationend", onEnd);
          };
        });
        return () => {
          rafCleanup();
          cleanup?.();
        };
      },
      trackExitAnimation: ({ send, scope }) => {
        let cleanup;
        const rafCleanup = domQuery.raf(() => {
          const contentEl = getContentEl(scope);
          if (!contentEl) return;
          const animationName = domQuery.getComputedStyle(contentEl).animationName;
          const hasNoAnimation = !animationName || animationName === "none";
          if (hasNoAnimation) {
            send({ type: "animation.end" });
            return;
          }
          const onEnd = (event) => {
            const target = domQuery.getEventTarget(event);
            if (target === contentEl) {
              send({ type: "animation.end" });
            }
          };
          contentEl.addEventListener("animationend", onEnd);
          const restoreStyles = domQuery.setStyle(contentEl, {
            animationFillMode: "forwards"
          });
          cleanup = () => {
            contentEl.removeEventListener("animationend", onEnd);
            domQuery.nextTick(() => restoreStyles());
          };
        });
        return () => {
          rafCleanup();
          cleanup?.();
        };
      }
    },
    actions: {
      setInitial: ({ context }) => {
        context.set("initial", true);
      },
      clearInitial: ({ context }) => {
        context.set("initial", false);
      },
      cleanupNode: ({ refs }) => {
        refs.set("stylesRef", null);
      },
      measureSize: ({ context, flush, scope }) => {
        const contentEl = getContentEl(scope);
        if (!contentEl) return;
        const { height, width } = contentEl.getBoundingClientRect();
        flush(() => {
          context.set("size", { height, width });
        });
      },
      computeSize: ({ refs, scope, flush, context }) => {
        refs.get("cleanup")?.();
        const rafCleanup = domQuery.raf(() => {
          const contentEl = getContentEl(scope);
          if (!contentEl) return;
          const hidden = contentEl.hidden;
          contentEl.style.animationName = "none";
          contentEl.style.animationDuration = "0s";
          contentEl.hidden = false;
          const rect = contentEl.getBoundingClientRect();
          flush(() => {
            context.set("size", { height: rect.height, width: rect.width });
          });
          if (context.get("initial")) {
            contentEl.style.animationName = "";
            contentEl.style.animationDuration = "";
          }
          contentEl.hidden = hidden;
        });
        refs.set("cleanup", rafCleanup);
      },
      invokeOnOpen: ({ prop }) => {
        prop("onOpenChange")?.({ open: true });
      },
      invokeOnClose: ({ prop }) => {
        prop("onOpenChange")?.({ open: false });
      },
      invokeOnExitComplete: ({ prop }) => {
        prop("onExitComplete")?.();
      },
      toggleVisibility: ({ prop, send }) => {
        send({ type: prop("open") ? "controlled.open" : "controlled.close" });
      }
    }
  }
});
var props = types.createProps()([
  "dir",
  "disabled",
  "getRootNode",
  "id",
  "ids",
  "onExitComplete",
  "onOpenChange",
  "defaultOpen",
  "open"
]);
var splitProps = utils.createSplitProps(props);

exports.anatomy = anatomy;
exports.connect = connect;
exports.machine = machine;
exports.props = props;
exports.splitProps = splitProps;
