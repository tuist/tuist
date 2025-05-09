import { createAnatomy } from '@zag-js/anatomy';
import { ariaHidden } from '@zag-js/aria-hidden';
import { createMachine } from '@zag-js/core';
import { trackDismissableElement } from '@zag-js/dismissable';
import { raf, getComputedStyle } from '@zag-js/dom-query';
import { trapFocus } from '@zag-js/focus-trap';
import { preventBodyScroll } from '@zag-js/remove-scroll';
import { createProps } from '@zag-js/types';
import { createSplitProps } from '@zag-js/utils';

// src/dialog.anatomy.ts
var anatomy = createAnatomy("dialog").parts(
  "trigger",
  "backdrop",
  "positioner",
  "content",
  "title",
  "description",
  "closeTrigger"
);
var parts = anatomy.build();

// src/dialog.dom.ts
var getPositionerId = (ctx) => ctx.ids?.positioner ?? `dialog:${ctx.id}:positioner`;
var getBackdropId = (ctx) => ctx.ids?.backdrop ?? `dialog:${ctx.id}:backdrop`;
var getContentId = (ctx) => ctx.ids?.content ?? `dialog:${ctx.id}:content`;
var getTriggerId = (ctx) => ctx.ids?.trigger ?? `dialog:${ctx.id}:trigger`;
var getTitleId = (ctx) => ctx.ids?.title ?? `dialog:${ctx.id}:title`;
var getDescriptionId = (ctx) => ctx.ids?.description ?? `dialog:${ctx.id}:description`;
var getCloseTriggerId = (ctx) => ctx.ids?.closeTrigger ?? `dialog:${ctx.id}:close`;
var getContentEl = (ctx) => ctx.getById(getContentId(ctx));
var getPositionerEl = (ctx) => ctx.getById(getPositionerId(ctx));
var getBackdropEl = (ctx) => ctx.getById(getBackdropId(ctx));
var getTriggerEl = (ctx) => ctx.getById(getTriggerId(ctx));
var getTitleEl = (ctx) => ctx.getById(getTitleId(ctx));
var getDescriptionEl = (ctx) => ctx.getById(getDescriptionId(ctx));
var getCloseTriggerEl = (ctx) => ctx.getById(getCloseTriggerId(ctx));

// src/dialog.connect.ts
function connect(service, normalize) {
  const { state, send, context, prop, scope } = service;
  const ariaLabel = prop("aria-label");
  const open = state.matches("open");
  return {
    open,
    setOpen(nextOpen) {
      const open2 = state.matches("open");
      if (open2 === nextOpen) return;
      send({ type: nextOpen ? "OPEN" : "CLOSE" });
    },
    getTriggerProps() {
      return normalize.button({
        ...parts.trigger.attrs,
        dir: prop("dir"),
        id: getTriggerId(scope),
        "aria-haspopup": "dialog",
        type: "button",
        "aria-expanded": open,
        "data-state": open ? "open" : "closed",
        "aria-controls": getContentId(scope),
        onClick(event) {
          if (event.defaultPrevented) return;
          send({ type: "TOGGLE" });
        }
      });
    },
    getBackdropProps() {
      return normalize.element({
        ...parts.backdrop.attrs,
        dir: prop("dir"),
        hidden: !open,
        id: getBackdropId(scope),
        "data-state": open ? "open" : "closed"
      });
    },
    getPositionerProps() {
      return normalize.element({
        ...parts.positioner.attrs,
        dir: prop("dir"),
        id: getPositionerId(scope),
        style: {
          pointerEvents: open ? void 0 : "none"
        }
      });
    },
    getContentProps() {
      const rendered = context.get("rendered");
      return normalize.element({
        ...parts.content.attrs,
        dir: prop("dir"),
        role: prop("role"),
        hidden: !open,
        id: getContentId(scope),
        tabIndex: -1,
        "data-state": open ? "open" : "closed",
        "aria-modal": true,
        "aria-label": ariaLabel || void 0,
        "aria-labelledby": ariaLabel || !rendered.title ? void 0 : getTitleId(scope),
        "aria-describedby": rendered.description ? getDescriptionId(scope) : void 0
      });
    },
    getTitleProps() {
      return normalize.element({
        ...parts.title.attrs,
        dir: prop("dir"),
        id: getTitleId(scope)
      });
    },
    getDescriptionProps() {
      return normalize.element({
        ...parts.description.attrs,
        dir: prop("dir"),
        id: getDescriptionId(scope)
      });
    },
    getCloseTriggerProps() {
      return normalize.button({
        ...parts.closeTrigger.attrs,
        dir: prop("dir"),
        id: getCloseTriggerId(scope),
        type: "button",
        onClick(event) {
          if (event.defaultPrevented) return;
          event.stopPropagation();
          send({ type: "CLOSE" });
        }
      });
    }
  };
}
var machine = createMachine({
  props({ props: props2, scope }) {
    const alertDialog = props2.role === "alertdialog";
    const initialFocusEl = alertDialog ? () => getCloseTriggerEl(scope) : void 0;
    return {
      role: "dialog",
      modal: true,
      trapFocus: true,
      preventScroll: true,
      closeOnInteractOutside: !alertDialog,
      closeOnEscape: true,
      restoreFocus: true,
      initialFocusEl,
      ...props2
    };
  },
  initialState({ prop }) {
    const open = prop("open") || prop("defaultOpen");
    return open ? "open" : "closed";
  },
  context({ bindable }) {
    return {
      rendered: bindable(() => ({
        defaultValue: { title: true, description: true }
      }))
    };
  },
  watch({ track, action, prop }) {
    track([() => prop("open")], () => {
      action(["toggleVisibility"]);
    });
  },
  states: {
    open: {
      entry: ["checkRenderedElements", "syncZIndex"],
      effects: ["trackDismissableElement", "trapFocus", "preventScroll", "hideContentBelow"],
      on: {
        "CONTROLLED.CLOSE": {
          target: "closed"
        },
        CLOSE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        TOGGLE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ]
      }
    },
    closed: {
      on: {
        "CONTROLLED.OPEN": {
          target: "open"
        },
        OPEN: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen"]
          }
        ],
        TOGGLE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen"]
          }
        ]
      }
    }
  },
  implementations: {
    guards: {
      isOpenControlled: ({ prop }) => prop("open") != void 0
    },
    effects: {
      trackDismissableElement({ scope, send, prop }) {
        const getContentEl2 = () => getContentEl(scope);
        return trackDismissableElement(getContentEl2, {
          defer: true,
          pointerBlocking: prop("modal"),
          exclude: [getTriggerEl(scope)],
          onInteractOutside(event) {
            prop("onInteractOutside")?.(event);
            if (!prop("closeOnInteractOutside")) {
              event.preventDefault();
            }
          },
          persistentElements: prop("persistentElements"),
          onFocusOutside: prop("onFocusOutside"),
          onPointerDownOutside: prop("onPointerDownOutside"),
          onEscapeKeyDown(event) {
            prop("onEscapeKeyDown")?.(event);
            if (!prop("closeOnEscape")) {
              event.preventDefault();
            }
          },
          onDismiss() {
            send({ type: "CLOSE", src: "interact-outside" });
          }
        });
      },
      preventScroll({ scope, prop }) {
        if (!prop("preventScroll")) return;
        return preventBodyScroll(scope.getDoc());
      },
      trapFocus({ scope, prop }) {
        if (!prop("trapFocus") || !prop("modal")) return;
        const contentEl = () => getContentEl(scope);
        return trapFocus(contentEl, {
          preventScroll: true,
          returnFocusOnDeactivate: !!prop("restoreFocus"),
          initialFocus: prop("initialFocusEl"),
          setReturnFocus: (el) => prop("finalFocusEl")?.() ?? el
        });
      },
      hideContentBelow({ scope, prop }) {
        if (!prop("modal")) return;
        const getElements = () => [getContentEl(scope)];
        return ariaHidden(getElements, { defer: true });
      }
    },
    actions: {
      checkRenderedElements({ context, scope }) {
        raf(() => {
          context.set("rendered", {
            title: !!getTitleEl(scope),
            description: !!getDescriptionEl(scope)
          });
        });
      },
      syncZIndex({ scope }) {
        raf(() => {
          const contentEl = getContentEl(scope);
          if (!contentEl) return;
          const styles = getComputedStyle(contentEl);
          const elems = [getPositionerEl(scope), getBackdropEl(scope)];
          elems.forEach((node) => {
            node?.style.setProperty("--z-index", styles.zIndex);
          });
        });
      },
      invokeOnClose({ prop }) {
        prop("onOpenChange")?.({ open: false });
      },
      invokeOnOpen({ prop }) {
        prop("onOpenChange")?.({ open: true });
      },
      toggleVisibility({ prop, send, event }) {
        send({
          type: prop("open") ? "CONTROLLED.OPEN" : "CONTROLLED.CLOSE",
          previousEvent: event
        });
      }
    }
  }
});
var props = createProps()([
  "aria-label",
  "closeOnEscape",
  "closeOnInteractOutside",
  "dir",
  "finalFocusEl",
  "getRootNode",
  "getRootNode",
  "id",
  "id",
  "ids",
  "initialFocusEl",
  "modal",
  "onEscapeKeyDown",
  "onFocusOutside",
  "onInteractOutside",
  "onOpenChange",
  "onPointerDownOutside",
  "defaultOpen",
  "open",
  "persistentElements",
  "preventScroll",
  "restoreFocus",
  "role",
  "trapFocus"
]);
var splitProps = createSplitProps(props);

export { anatomy, connect, machine, props, splitProps };
