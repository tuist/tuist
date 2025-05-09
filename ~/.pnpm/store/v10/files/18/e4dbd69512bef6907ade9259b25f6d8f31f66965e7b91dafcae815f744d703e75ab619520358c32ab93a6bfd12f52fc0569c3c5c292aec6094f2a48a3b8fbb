'use strict';

var anatomy$1 = require('@zag-js/anatomy');
var domQuery = require('@zag-js/dom-query');
var popper = require('@zag-js/popper');
var ariaHidden = require('@zag-js/aria-hidden');
var core = require('@zag-js/core');
var dismissable = require('@zag-js/dismissable');
var focusTrap = require('@zag-js/focus-trap');
var removeScroll = require('@zag-js/remove-scroll');
var types = require('@zag-js/types');
var utils = require('@zag-js/utils');

// src/popover.anatomy.ts
var anatomy = anatomy$1.createAnatomy("popover").parts(
  "arrow",
  "arrowTip",
  "anchor",
  "trigger",
  "indicator",
  "positioner",
  "content",
  "title",
  "description",
  "closeTrigger"
);
var parts = anatomy.build();
var getAnchorId = (scope) => scope.ids?.anchor ?? `popover:${scope.id}:anchor`;
var getTriggerId = (scope) => scope.ids?.trigger ?? `popover:${scope.id}:trigger`;
var getContentId = (scope) => scope.ids?.content ?? `popover:${scope.id}:content`;
var getPositionerId = (scope) => scope.ids?.positioner ?? `popover:${scope.id}:popper`;
var getArrowId = (scope) => scope.ids?.arrow ?? `popover:${scope.id}:arrow`;
var getTitleId = (scope) => scope.ids?.title ?? `popover:${scope.id}:title`;
var getDescriptionId = (scope) => scope.ids?.description ?? `popover:${scope.id}:desc`;
var getCloseTriggerId = (scope) => scope.ids?.closeTrigger ?? `popover:${scope.id}:close`;
var getAnchorEl = (scope) => scope.getById(getAnchorId(scope));
var getTriggerEl = (scope) => scope.getById(getTriggerId(scope));
var getContentEl = (scope) => scope.getById(getContentId(scope));
var getPositionerEl = (scope) => scope.getById(getPositionerId(scope));
var getTitleEl = (scope) => scope.getById(getTitleId(scope));
var getDescriptionEl = (scope) => scope.getById(getDescriptionId(scope));

// src/popover.connect.ts
function connect(service, normalize) {
  const { state, context, send, computed, prop, scope } = service;
  const open = state.matches("open");
  const currentPlacement = context.get("currentPlacement");
  const portalled = computed("currentPortalled");
  const rendered = context.get("renderedElements");
  const popperStyles = popper.getPlacementStyles({
    ...prop("positioning"),
    placement: currentPlacement
  });
  return {
    portalled,
    open,
    setOpen(nextOpen) {
      const open2 = state.matches("open");
      if (open2 === nextOpen) return;
      send({ type: nextOpen ? "OPEN" : "CLOSE" });
    },
    reposition(options = {}) {
      send({ type: "POSITIONING.SET", options });
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
    getAnchorProps() {
      return normalize.element({
        ...parts.anchor.attrs,
        dir: prop("dir"),
        id: getAnchorId(scope)
      });
    },
    getTriggerProps() {
      return normalize.button({
        ...parts.trigger.attrs,
        dir: prop("dir"),
        type: "button",
        "data-placement": currentPlacement,
        id: getTriggerId(scope),
        "aria-haspopup": "dialog",
        "aria-expanded": open,
        "data-state": open ? "open" : "closed",
        "aria-controls": getContentId(scope),
        onPointerDown(event) {
          if (domQuery.isSafari()) {
            event.currentTarget.focus();
          }
        },
        onClick(event) {
          if (event.defaultPrevented) return;
          send({ type: "TOGGLE" });
        },
        onBlur(event) {
          send({ type: "TRIGGER_BLUR", target: event.relatedTarget });
        }
      });
    },
    getIndicatorProps() {
      return normalize.element({
        ...parts.indicator.attrs,
        dir: prop("dir"),
        "data-state": open ? "open" : "closed"
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
        id: getContentId(scope),
        tabIndex: -1,
        role: "dialog",
        hidden: !open,
        "data-state": open ? "open" : "closed",
        "data-expanded": domQuery.dataAttr(open),
        "aria-labelledby": rendered.title ? getTitleId(scope) : void 0,
        "aria-describedby": rendered.description ? getDescriptionId(scope) : void 0,
        "data-placement": currentPlacement
      });
    },
    getTitleProps() {
      return normalize.element({
        ...parts.title.attrs,
        id: getTitleId(scope),
        dir: prop("dir")
      });
    },
    getDescriptionProps() {
      return normalize.element({
        ...parts.description.attrs,
        id: getDescriptionId(scope),
        dir: prop("dir")
      });
    },
    getCloseTriggerProps() {
      return normalize.button({
        ...parts.closeTrigger.attrs,
        dir: prop("dir"),
        id: getCloseTriggerId(scope),
        type: "button",
        "aria-label": "close",
        onClick(event) {
          if (event.defaultPrevented) return;
          event.stopPropagation();
          send({ type: "CLOSE" });
        }
      });
    }
  };
}
var machine = core.createMachine({
  props({ props: props2 }) {
    return {
      closeOnInteractOutside: true,
      closeOnEscape: true,
      autoFocus: true,
      modal: false,
      portalled: true,
      ...props2,
      positioning: {
        placement: "bottom",
        ...props2.positioning
      }
    };
  },
  initialState({ prop }) {
    const open = prop("open") || prop("defaultOpen");
    return open ? "open" : "closed";
  },
  context({ bindable }) {
    return {
      currentPlacement: bindable(() => ({
        defaultValue: void 0
      })),
      renderedElements: bindable(() => ({
        defaultValue: { title: true, description: true }
      }))
    };
  },
  computed: {
    currentPortalled: ({ prop }) => !!prop("modal") || !!prop("portalled")
  },
  watch({ track, prop, action }) {
    track([() => prop("open")], () => {
      action(["toggleVisibility"]);
    });
  },
  entry: ["checkRenderedElements"],
  states: {
    closed: {
      on: {
        "CONTROLLED.OPEN": {
          target: "open",
          actions: ["setInitialFocus"]
        },
        TOGGLE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen", "setInitialFocus"]
          }
        ],
        OPEN: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen", "setInitialFocus"]
          }
        ]
      }
    },
    open: {
      effects: [
        "trapFocus",
        "preventScroll",
        "hideContentBelow",
        "trackPositioning",
        "trackDismissableElement",
        "proxyTabFocus"
      ],
      on: {
        "CONTROLLED.CLOSE": {
          target: "closed",
          actions: ["setFinalFocus"]
        },
        CLOSE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose", "setFinalFocus"]
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
        ],
        "POSITIONING.SET": {
          actions: ["reposition"]
        }
      }
    }
  },
  implementations: {
    guards: {
      isOpenControlled: ({ prop }) => prop("open") != void 0
    },
    effects: {
      trackPositioning({ context, prop, scope }) {
        context.set("currentPlacement", prop("positioning").placement);
        const anchorEl = getAnchorEl(scope) ?? getTriggerEl(scope);
        const getPositionerEl2 = () => getPositionerEl(scope);
        return popper.getPlacement(anchorEl, getPositionerEl2, {
          ...prop("positioning"),
          defer: true,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      trackDismissableElement({ send, prop, scope }) {
        const getContentEl2 = () => getContentEl(scope);
        let restoreFocus = true;
        return dismissable.trackDismissableElement(getContentEl2, {
          pointerBlocking: prop("modal"),
          exclude: getTriggerEl(scope),
          defer: true,
          onEscapeKeyDown(event) {
            prop("onEscapeKeyDown")?.(event);
            if (prop("closeOnEscape")) return;
            event.preventDefault();
          },
          onInteractOutside(event) {
            prop("onInteractOutside")?.(event);
            if (event.defaultPrevented) return;
            restoreFocus = !(event.detail.focusable || event.detail.contextmenu);
            if (!prop("closeOnInteractOutside")) {
              event.preventDefault();
            }
          },
          onPointerDownOutside: prop("onPointerDownOutside"),
          onFocusOutside: prop("onFocusOutside"),
          persistentElements: prop("persistentElements"),
          onDismiss() {
            send({ type: "CLOSE", src: "interact-outside", restoreFocus });
          }
        });
      },
      proxyTabFocus({ prop, scope }) {
        if (prop("modal") || !prop("portalled")) return;
        const getContentEl2 = () => getContentEl(scope);
        return domQuery.proxyTabFocus(getContentEl2, {
          triggerElement: getTriggerEl(scope),
          defer: true,
          onFocus(el) {
            el.focus({ preventScroll: true });
          }
        });
      },
      hideContentBelow({ prop, scope }) {
        if (!prop("modal")) return;
        const getElements = () => [getContentEl(scope), getTriggerEl(scope)];
        return ariaHidden.ariaHidden(getElements, { defer: true });
      },
      preventScroll({ prop, scope }) {
        if (!prop("modal")) return;
        return removeScroll.preventBodyScroll(scope.getDoc());
      },
      trapFocus({ prop, scope }) {
        if (!prop("modal")) return;
        const contentEl = () => getContentEl(scope);
        return focusTrap.trapFocus(contentEl, {
          initialFocus: () => domQuery.getInitialFocus({
            root: getContentEl(scope),
            getInitialEl: prop("initialFocusEl"),
            enabled: prop("autoFocus")
          })
        });
      }
    },
    actions: {
      reposition({ event, prop, scope, context }) {
        const anchorEl = getAnchorEl(scope) ?? getTriggerEl(scope);
        const getPositionerEl2 = () => getPositionerEl(scope);
        popper.getPlacement(anchorEl, getPositionerEl2, {
          ...prop("positioning"),
          ...event.options,
          defer: true,
          listeners: false,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      checkRenderedElements({ context, scope }) {
        domQuery.raf(() => {
          Object.assign(context.get("renderedElements"), {
            title: !!getTitleEl(scope),
            description: !!getDescriptionEl(scope)
          });
        });
      },
      setInitialFocus({ prop, scope }) {
        if (prop("modal")) return;
        domQuery.raf(() => {
          const element = domQuery.getInitialFocus({
            root: getContentEl(scope),
            getInitialEl: prop("initialFocusEl"),
            enabled: prop("autoFocus")
          });
          element?.focus({ preventScroll: true });
        });
      },
      setFinalFocus({ event, scope }) {
        const restoreFocus = event.restoreFocus ?? event.previousEvent?.restoreFocus;
        if (restoreFocus != null && !restoreFocus) return;
        domQuery.raf(() => {
          const element = getTriggerEl(scope);
          element?.focus({ preventScroll: true });
        });
      },
      invokeOnOpen({ prop }) {
        prop("onOpenChange")?.({ open: true });
      },
      invokeOnClose({ prop }) {
        prop("onOpenChange")?.({ open: false });
      },
      toggleVisibility({ event, send, prop }) {
        send({ type: prop("open") ? "CONTROLLED.OPEN" : "CONTROLLED.CLOSE", previousEvent: event });
      }
    }
  }
});
var props = types.createProps()([
  "autoFocus",
  "closeOnEscape",
  "closeOnInteractOutside",
  "dir",
  "getRootNode",
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
  "portalled",
  "positioning"
]);
var splitProps = utils.createSplitProps(props);

exports.anatomy = anatomy;
exports.connect = connect;
exports.machine = machine;
exports.props = props;
exports.splitProps = splitProps;
