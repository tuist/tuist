import { createAnatomy } from '@zag-js/anatomy';
import { addDomEvent, getOverflowAncestors, isComposingEvent, dataAttr } from '@zag-js/dom-query';
import { trackFocusVisible, isFocusVisible } from '@zag-js/focus-visible';
import { getPlacement, getPlacementStyles } from '@zag-js/popper';
import { proxy, subscribe } from '@zag-js/store';
import { createGuards, createMachine } from '@zag-js/core';
import { createProps } from '@zag-js/types';
import { createSplitProps } from '@zag-js/utils';

// src/tooltip.anatomy.ts
var anatomy = createAnatomy("tooltip").parts("trigger", "arrow", "arrowTip", "positioner", "content");
var parts = anatomy.build();

// src/tooltip.dom.ts
var getTriggerId = (scope) => scope.ids?.trigger ?? `tooltip:${scope.id}:trigger`;
var getContentId = (scope) => scope.ids?.content ?? `tooltip:${scope.id}:content`;
var getArrowId = (scope) => scope.ids?.arrow ?? `tooltip:${scope.id}:arrow`;
var getPositionerId = (scope) => scope.ids?.positioner ?? `tooltip:${scope.id}:popper`;
var getTriggerEl = (scope) => scope.getById(getTriggerId(scope));
var getPositionerEl = (scope) => scope.getById(getPositionerId(scope));
var store = proxy({ id: null });

// src/tooltip.connect.ts
function connect(service, normalize) {
  const { state, context, send, scope, prop, event: _event } = service;
  const id = prop("id");
  const hasAriaLabel = !!prop("aria-label");
  const open = state.matches("open", "closing");
  const triggerId = getTriggerId(scope);
  const contentId = getContentId(scope);
  const disabled = prop("disabled");
  const popperStyles = getPlacementStyles({
    ...prop("positioning"),
    placement: context.get("currentPlacement")
  });
  return {
    open,
    setOpen(nextOpen) {
      const open2 = state.matches("open", "closing");
      if (open2 === nextOpen) return;
      send({ type: nextOpen ? "open" : "close" });
    },
    reposition(options = {}) {
      send({ type: "positioning.set", options });
    },
    getTriggerProps() {
      return normalize.button({
        ...parts.trigger.attrs,
        id: triggerId,
        dir: prop("dir"),
        "data-expanded": dataAttr(open),
        "data-state": open ? "open" : "closed",
        "aria-describedby": open ? contentId : void 0,
        onClick(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          if (!prop("closeOnClick")) return;
          send({ type: "close", src: "trigger.click" });
        },
        onFocus(event) {
          queueMicrotask(() => {
            if (event.defaultPrevented) return;
            if (disabled) return;
            if (_event.src === "trigger.pointerdown") return;
            if (!isFocusVisible()) return;
            send({ type: "open", src: "trigger.focus" });
          });
        },
        onBlur(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          if (id === store.id) {
            send({ type: "close", src: "trigger.blur" });
          }
        },
        onPointerDown(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          if (!prop("closeOnPointerDown")) return;
          if (id === store.id) {
            send({ type: "close", src: "trigger.pointerdown" });
          }
        },
        onPointerMove(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          if (event.pointerType === "touch") return;
          send({ type: "pointer.move" });
        },
        onPointerLeave() {
          if (disabled) return;
          send({ type: "pointer.leave" });
        },
        onPointerCancel() {
          if (disabled) return;
          send({ type: "pointer.leave" });
        }
      });
    },
    getArrowProps() {
      return normalize.element({
        id: getArrowId(scope),
        ...parts.arrow.attrs,
        dir: prop("dir"),
        style: popperStyles.arrow
      });
    },
    getArrowTipProps() {
      return normalize.element({
        ...parts.arrowTip.attrs,
        dir: prop("dir"),
        style: popperStyles.arrowTip
      });
    },
    getPositionerProps() {
      return normalize.element({
        id: getPositionerId(scope),
        ...parts.positioner.attrs,
        dir: prop("dir"),
        style: popperStyles.floating
      });
    },
    getContentProps() {
      return normalize.element({
        ...parts.content.attrs,
        dir: prop("dir"),
        hidden: !open,
        "data-state": open ? "open" : "closed",
        role: hasAriaLabel ? void 0 : "tooltip",
        id: hasAriaLabel ? void 0 : contentId,
        "data-placement": context.get("currentPlacement"),
        onPointerEnter() {
          send({ type: "content.pointer.move" });
        },
        onPointerLeave() {
          send({ type: "content.pointer.leave" });
        },
        style: {
          pointerEvents: prop("interactive") ? "auto" : "none"
        }
      });
    }
  };
}
var { and, not } = createGuards();
var machine = createMachine({
  initialState: ({ prop }) => {
    const open = prop("open") || prop("defaultOpen");
    return open ? "open" : "closed";
  },
  props({ props: props2 }) {
    return {
      id: "x",
      openDelay: 1e3,
      closeDelay: 500,
      closeOnPointerDown: true,
      closeOnEscape: true,
      interactive: false,
      closeOnScroll: true,
      closeOnClick: true,
      disabled: false,
      ...props2,
      positioning: {
        placement: "bottom",
        ...props2.positioning
      }
    };
  },
  effects: ["trackFocusVisible", "trackStore"],
  context: ({ bindable }) => ({
    currentPlacement: bindable(() => ({ defaultValue: void 0 })),
    hasPointerMoveOpened: bindable(() => ({ defaultValue: false }))
  }),
  watch({ track, action, prop }) {
    track([() => prop("disabled")], () => {
      action(["closeIfDisabled"]);
    });
    track([() => prop("open")], () => {
      action(["toggleVisibility"]);
    });
  },
  states: {
    closed: {
      entry: ["clearGlobalId"],
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
            actions: ["invokeOnOpen"]
          }
        ],
        "pointer.leave": {
          actions: ["clearPointerMoveOpened"]
        },
        "pointer.move": [
          {
            guard: and("noVisibleTooltip", not("hasPointerMoveOpened")),
            target: "opening"
          },
          {
            guard: not("hasPointerMoveOpened"),
            target: "open",
            actions: ["setPointerMoveOpened", "invokeOnOpen"]
          }
        ]
      }
    },
    opening: {
      effects: ["trackScroll", "trackPointerlockChange", "waitForOpenDelay"],
      on: {
        "after.openDelay": [
          {
            guard: "isOpenControlled",
            actions: ["setPointerMoveOpened", "invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setPointerMoveOpened", "invokeOnOpen"]
          }
        ],
        "controlled.open": {
          target: "open"
        },
        "controlled.close": {
          target: "closed"
        },
        open: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen"]
          }
        ],
        "pointer.leave": [
          {
            guard: "isOpenControlled",
            // We trigger toggleVisibility manually since the `ctx.open` has not changed yet (at this point)
            actions: ["clearPointerMoveOpened", "invokeOnClose", "toggleVisibility"]
          },
          {
            target: "closed",
            actions: ["clearPointerMoveOpened", "invokeOnClose"]
          }
        ],
        close: [
          {
            guard: "isOpenControlled",
            // We trigger toggleVisibility manually since the `ctx.open` has not changed yet (at this point)
            actions: ["invokeOnClose", "toggleVisibility"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ]
      }
    },
    open: {
      effects: ["trackEscapeKey", "trackScroll", "trackPointerlockChange", "trackPositioning"],
      entry: ["setGlobalId"],
      on: {
        "controlled.close": {
          target: "closed"
        },
        close: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        "pointer.leave": [
          {
            guard: "isVisible",
            target: "closing",
            actions: ["clearPointerMoveOpened"]
          },
          // == group ==
          {
            guard: "isOpenControlled",
            actions: ["clearPointerMoveOpened", "invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["clearPointerMoveOpened", "invokeOnClose"]
          }
        ],
        "content.pointer.leave": {
          guard: "isInteractive",
          target: "closing"
        },
        "positioning.set": {
          actions: ["reposition"]
        }
      }
    },
    closing: {
      effects: ["trackPositioning", "waitForCloseDelay"],
      on: {
        "after.closeDelay": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        "controlled.close": {
          target: "closed"
        },
        "controlled.open": {
          target: "open"
        },
        close: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        "pointer.move": [
          {
            guard: "isOpenControlled",
            // We trigger toggleVisibility manually since the `ctx.open` has not changed yet (at this point)
            actions: ["setPointerMoveOpened", "invokeOnOpen", "toggleVisibility"]
          },
          {
            target: "open",
            actions: ["setPointerMoveOpened", "invokeOnOpen"]
          }
        ],
        "content.pointer.move": {
          guard: "isInteractive",
          target: "open"
        },
        "positioning.set": {
          actions: ["reposition"]
        }
      }
    }
  },
  implementations: {
    guards: {
      noVisibleTooltip: () => store.id === null,
      isVisible: ({ prop }) => prop("id") === store.id,
      isInteractive: ({ prop }) => !!prop("interactive"),
      hasPointerMoveOpened: ({ context }) => context.get("hasPointerMoveOpened"),
      isOpenControlled: ({ prop }) => prop("open") !== void 0
    },
    actions: {
      setGlobalId: ({ prop }) => {
        store.id = prop("id");
      },
      clearGlobalId: ({ prop }) => {
        if (prop("id") === store.id) {
          store.id = null;
        }
      },
      invokeOnOpen: ({ prop }) => {
        prop("onOpenChange")?.({ open: true });
      },
      invokeOnClose: ({ prop }) => {
        prop("onOpenChange")?.({ open: false });
      },
      closeIfDisabled: ({ prop, send }) => {
        if (!prop("disabled")) return;
        send({ type: "close", src: "disabled.change" });
      },
      reposition: ({ context, event, prop, scope }) => {
        if (event.type !== "positioning.set") return;
        const getPositionerEl2 = () => getPositionerEl(scope);
        return getPlacement(getTriggerEl(scope), getPositionerEl2, {
          ...prop("positioning"),
          ...event.options,
          defer: true,
          listeners: false,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      toggleVisibility: ({ prop, event, send }) => {
        queueMicrotask(() => {
          send({
            type: prop("open") ? "controlled.open" : "controlled.close",
            previousEvent: event
          });
        });
      },
      setPointerMoveOpened: ({ context }) => {
        context.set("hasPointerMoveOpened", true);
      },
      clearPointerMoveOpened: ({ context }) => {
        context.set("hasPointerMoveOpened", false);
      }
    },
    effects: {
      trackFocusVisible: ({ scope }) => {
        return trackFocusVisible({ root: scope.getRootNode?.() });
      },
      trackPositioning: ({ context, prop, scope }) => {
        if (!context.get("currentPlacement")) {
          context.set("currentPlacement", prop("positioning").placement);
        }
        const getPositionerEl2 = () => getPositionerEl(scope);
        return getPlacement(getTriggerEl(scope), getPositionerEl2, {
          ...prop("positioning"),
          defer: true,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      trackPointerlockChange: ({ send, scope }) => {
        const doc = scope.getDoc();
        const onChange = () => send({ type: "close", src: "pointerlock:change" });
        return addDomEvent(doc, "pointerlockchange", onChange, false);
      },
      trackScroll: ({ send, prop, scope }) => {
        if (!prop("closeOnScroll")) return;
        const triggerEl = getTriggerEl(scope);
        if (!triggerEl) return;
        const overflowParents = getOverflowAncestors(triggerEl);
        const cleanups = overflowParents.map((overflowParent) => {
          const onScroll = () => {
            send({ type: "close", src: "scroll" });
          };
          return addDomEvent(overflowParent, "scroll", onScroll, {
            passive: true,
            capture: true
          });
        });
        return () => {
          cleanups.forEach((fn) => fn?.());
        };
      },
      trackStore: ({ prop, send }) => {
        let cleanup;
        queueMicrotask(() => {
          cleanup = subscribe(store, () => {
            if (store.id !== prop("id")) {
              send({ type: "close", src: "id.change" });
            }
          });
        });
        return () => cleanup?.();
      },
      trackEscapeKey: ({ send, prop }) => {
        if (!prop("closeOnEscape")) return;
        const onKeyDown = (event) => {
          if (isComposingEvent(event)) return;
          if (event.key !== "Escape") return;
          event.stopPropagation();
          send({ type: "close", src: "keydown.escape" });
        };
        return addDomEvent(document, "keydown", onKeyDown, true);
      },
      waitForOpenDelay: ({ send, prop }) => {
        const id = setTimeout(() => {
          send({ type: "after.openDelay" });
        }, prop("openDelay"));
        return () => clearTimeout(id);
      },
      waitForCloseDelay: ({ send, prop }) => {
        const id = setTimeout(() => {
          send({ type: "after.closeDelay" });
        }, prop("closeDelay"));
        return () => clearTimeout(id);
      }
    }
  }
});
var props = createProps()([
  "aria-label",
  "closeDelay",
  "closeOnEscape",
  "closeOnPointerDown",
  "closeOnScroll",
  "closeOnClick",
  "dir",
  "disabled",
  "getRootNode",
  "id",
  "ids",
  "interactive",
  "onOpenChange",
  "defaultOpen",
  "open",
  "openDelay",
  "positioning"
]);
var splitProps = createSplitProps(props);

export { anatomy, connect, machine, props, splitProps };
