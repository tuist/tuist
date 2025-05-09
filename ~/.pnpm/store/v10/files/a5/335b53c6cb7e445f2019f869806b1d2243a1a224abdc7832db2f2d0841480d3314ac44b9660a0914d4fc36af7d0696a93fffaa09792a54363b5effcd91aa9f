'use strict';

var anatomy$1 = require('@zag-js/anatomy');
var domQuery = require('@zag-js/dom-query');
var utils = require('@zag-js/utils');
var core = require('@zag-js/core');
var types = require('@zag-js/types');

// src/tabs.anatomy.ts
var anatomy = anatomy$1.createAnatomy("tabs").parts("root", "list", "trigger", "content", "indicator");
var parts = anatomy.build();
var getRootId = (ctx) => ctx.ids?.root ?? `tabs:${ctx.id}`;
var getListId = (ctx) => ctx.ids?.list ?? `tabs:${ctx.id}:list`;
var getContentId = (ctx, id) => ctx.ids?.content ?? `tabs:${ctx.id}:content-${id}`;
var getTriggerId = (ctx, id) => ctx.ids?.trigger ?? `tabs:${ctx.id}:trigger-${id}`;
var getIndicatorId = (ctx) => ctx.ids?.indicator ?? `tabs:${ctx.id}:indicator`;
var getListEl = (ctx) => ctx.getById(getListId(ctx));
var getContentEl = (ctx, id) => ctx.getById(getContentId(ctx, id));
var getTriggerEl = (ctx, id) => ctx.getById(getTriggerId(ctx, id));
var getIndicatorEl = (ctx) => ctx.getById(getIndicatorId(ctx));
var getElements = (ctx) => {
  const ownerId = CSS.escape(getListId(ctx));
  const selector = `[role=tab][data-ownedby='${ownerId}']:not([disabled])`;
  return domQuery.queryAll(getListEl(ctx), selector);
};
var getFirstTriggerEl = (ctx) => utils.first(getElements(ctx));
var getLastTriggerEl = (ctx) => utils.last(getElements(ctx));
var getNextTriggerEl = (ctx, opts) => domQuery.nextById(getElements(ctx), getTriggerId(ctx, opts.value), opts.loopFocus);
var getPrevTriggerEl = (ctx, opts) => domQuery.prevById(getElements(ctx), getTriggerId(ctx, opts.value), opts.loopFocus);
var getOffsetRect = (el) => {
  return {
    left: el?.offsetLeft ?? 0,
    top: el?.offsetTop ?? 0,
    width: el?.offsetWidth ?? 0,
    height: el?.offsetHeight ?? 0
  };
};
var getRectById = (ctx, id) => {
  const tab = domQuery.itemById(getElements(ctx), getTriggerId(ctx, id));
  return resolveRect(getOffsetRect(tab));
};
var resolveRect = (rect) => ({
  width: `${rect.width}px`,
  height: `${rect.height}px`,
  left: `${rect.left}px`,
  top: `${rect.top}px`
});

// src/tabs.connect.ts
function connect(service, normalize) {
  const { state, send, context, prop, scope } = service;
  const translations = prop("translations");
  const focused = state.matches("focused");
  const isVertical = prop("orientation") === "vertical";
  const isHorizontal = prop("orientation") === "horizontal";
  const composite = prop("composite");
  function getTriggerState(props2) {
    return {
      selected: context.get("value") === props2.value,
      focused: context.get("focusedValue") === props2.value,
      disabled: !!props2.disabled
    };
  }
  return {
    value: context.get("value"),
    focusedValue: context.get("focusedValue"),
    setValue(value) {
      send({ type: "SET_VALUE", value });
    },
    clearValue() {
      send({ type: "CLEAR_VALUE" });
    },
    setIndicatorRect(value) {
      const id = getTriggerId(scope, value);
      send({ type: "SET_INDICATOR_RECT", id });
    },
    syncTabIndex() {
      send({ type: "SYNC_TAB_INDEX" });
    },
    selectNext(fromValue) {
      send({ type: "TAB_FOCUS", value: fromValue, src: "selectNext" });
      send({ type: "ARROW_NEXT", src: "selectNext" });
    },
    selectPrev(fromValue) {
      send({ type: "TAB_FOCUS", value: fromValue, src: "selectPrev" });
      send({ type: "ARROW_PREV", src: "selectPrev" });
    },
    focus() {
      const value = context.get("value");
      if (!value) return;
      getTriggerEl(scope, value)?.focus();
    },
    getRootProps() {
      return normalize.element({
        ...parts.root.attrs,
        id: getRootId(scope),
        "data-orientation": prop("orientation"),
        "data-focus": domQuery.dataAttr(focused),
        dir: prop("dir")
      });
    },
    getListProps() {
      return normalize.element({
        ...parts.list.attrs,
        id: getListId(scope),
        role: "tablist",
        dir: prop("dir"),
        "data-focus": domQuery.dataAttr(focused),
        "aria-orientation": prop("orientation"),
        "data-orientation": prop("orientation"),
        "aria-label": translations?.listLabel,
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          if (!domQuery.isSelfTarget(event)) return;
          if (domQuery.isComposingEvent(event)) return;
          const keyMap = {
            ArrowDown() {
              if (isHorizontal) return;
              send({ type: "ARROW_NEXT", key: "ArrowDown" });
            },
            ArrowUp() {
              if (isHorizontal) return;
              send({ type: "ARROW_PREV", key: "ArrowUp" });
            },
            ArrowLeft() {
              if (isVertical) return;
              send({ type: "ARROW_PREV", key: "ArrowLeft" });
            },
            ArrowRight() {
              if (isVertical) return;
              send({ type: "ARROW_NEXT", key: "ArrowRight" });
            },
            Home() {
              send({ type: "HOME" });
            },
            End() {
              send({ type: "END" });
            },
            Enter() {
              send({ type: "ENTER" });
            }
          };
          let key = domQuery.getEventKey(event, {
            dir: prop("dir"),
            orientation: prop("orientation")
          });
          const exec = keyMap[key];
          if (exec) {
            event.preventDefault();
            exec(event);
          }
        }
      });
    },
    getTriggerState,
    getTriggerProps(props2) {
      const { value, disabled } = props2;
      const triggerState = getTriggerState(props2);
      return normalize.button({
        ...parts.trigger.attrs,
        role: "tab",
        type: "button",
        disabled,
        dir: prop("dir"),
        "data-orientation": prop("orientation"),
        "data-disabled": domQuery.dataAttr(disabled),
        "aria-disabled": disabled,
        "data-value": value,
        "aria-selected": triggerState.selected,
        "data-selected": domQuery.dataAttr(triggerState.selected),
        "data-focus": domQuery.dataAttr(triggerState.focused),
        "aria-controls": triggerState.selected ? getContentId(scope, value) : void 0,
        "data-ownedby": getListId(scope),
        "data-ssr": domQuery.dataAttr(context.get("ssr")),
        id: getTriggerId(scope, value),
        tabIndex: triggerState.selected && composite ? 0 : -1,
        onFocus() {
          send({ type: "TAB_FOCUS", value });
        },
        onBlur(event) {
          const target = event.relatedTarget;
          if (target?.getAttribute("role") !== "tab") {
            send({ type: "TAB_BLUR" });
          }
        },
        onClick(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          if (domQuery.isSafari()) {
            event.currentTarget.focus();
          }
          send({ type: "TAB_CLICK", value });
        }
      });
    },
    getContentProps(props2) {
      const { value } = props2;
      const selected = context.get("value") === value;
      return normalize.element({
        ...parts.content.attrs,
        dir: prop("dir"),
        id: getContentId(scope, value),
        tabIndex: composite ? 0 : -1,
        "aria-labelledby": getTriggerId(scope, value),
        role: "tabpanel",
        "data-ownedby": getListId(scope),
        "data-selected": domQuery.dataAttr(selected),
        "data-orientation": prop("orientation"),
        hidden: !selected
      });
    },
    getIndicatorProps() {
      const indicatorRect = context.get("indicatorRect");
      const indicatorTransition = context.get("indicatorTransition");
      return normalize.element({
        id: getIndicatorId(scope),
        ...parts.indicator.attrs,
        dir: prop("dir"),
        "data-orientation": prop("orientation"),
        style: {
          "--transition-property": "left, right, top, bottom, width, height",
          "--left": indicatorRect.left,
          "--top": indicatorRect.top,
          "--width": indicatorRect.width,
          "--height": indicatorRect.height,
          position: "absolute",
          willChange: "var(--transition-property)",
          transitionProperty: "var(--transition-property)",
          transitionDuration: indicatorTransition ? "var(--transition-duration, 150ms)" : "0ms",
          transitionTimingFunction: "var(--transition-timing-function)",
          [isHorizontal ? "left" : "top"]: isHorizontal ? "var(--left)" : "var(--top)"
        }
      });
    }
  };
}
var { not } = core.createGuards();
var machine = core.createMachine({
  props({ props: props2 }) {
    return {
      dir: "ltr",
      orientation: "horizontal",
      activationMode: "automatic",
      loopFocus: true,
      composite: true,
      navigate(details) {
        domQuery.clickIfLink(details.node);
      },
      defaultValue: null,
      ...props2
    };
  },
  initialState() {
    return "idle";
  },
  context({ prop, bindable }) {
    return {
      value: bindable(() => ({
        defaultValue: prop("defaultValue"),
        value: prop("value"),
        onChange(value) {
          prop("onValueChange")?.({ value });
        }
      })),
      focusedValue: bindable(() => ({
        defaultValue: prop("value") || prop("defaultValue"),
        sync: true,
        onChange(value) {
          prop("onFocusChange")?.({ focusedValue: value });
        }
      })),
      ssr: bindable(() => ({ defaultValue: true })),
      indicatorTransition: bindable(() => ({ defaultValue: false })),
      indicatorRect: bindable(() => ({
        defaultValue: { left: "0px", top: "0px", width: "0px", height: "0px" }
      }))
    };
  },
  watch({ context, prop, track, action }) {
    track([() => context.get("value")], () => {
      action(["allowIndicatorTransition", "syncIndicatorRect", "syncTabIndex", "navigateIfNeeded"]);
    });
    track([() => prop("dir"), () => prop("orientation")], () => {
      action(["syncIndicatorRect"]);
    });
  },
  on: {
    SET_VALUE: {
      actions: ["setValue"]
    },
    CLEAR_VALUE: {
      actions: ["clearValue"]
    },
    SET_INDICATOR_RECT: {
      actions: ["setIndicatorRect"]
    },
    SYNC_TAB_INDEX: {
      actions: ["syncTabIndex"]
    }
  },
  entry: ["syncIndicatorRect", "syncTabIndex", "syncSsr"],
  exit: ["cleanupObserver"],
  states: {
    idle: {
      on: {
        TAB_FOCUS: {
          target: "focused",
          actions: ["setFocusedValue"]
        },
        TAB_CLICK: {
          target: "focused",
          actions: ["setFocusedValue", "setValue"]
        }
      }
    },
    focused: {
      on: {
        TAB_CLICK: {
          target: "focused",
          actions: ["setFocusedValue", "setValue"]
        },
        ARROW_PREV: [
          {
            guard: "selectOnFocus",
            actions: ["focusPrevTab", "selectFocusedTab"]
          },
          {
            actions: ["focusPrevTab"]
          }
        ],
        ARROW_NEXT: [
          {
            guard: "selectOnFocus",
            actions: ["focusNextTab", "selectFocusedTab"]
          },
          {
            actions: ["focusNextTab"]
          }
        ],
        HOME: [
          {
            guard: "selectOnFocus",
            actions: ["focusFirstTab", "selectFocusedTab"]
          },
          {
            actions: ["focusFirstTab"]
          }
        ],
        END: [
          {
            guard: "selectOnFocus",
            actions: ["focusLastTab", "selectFocusedTab"]
          },
          {
            actions: ["focusLastTab"]
          }
        ],
        ENTER: {
          guard: not("selectOnFocus"),
          actions: ["selectFocusedTab"]
        },
        TAB_FOCUS: {
          actions: ["setFocusedValue"]
        },
        TAB_BLUR: {
          target: "idle",
          actions: ["clearFocusedValue"]
        }
      }
    }
  },
  implementations: {
    guards: {
      selectOnFocus: ({ prop }) => prop("activationMode") === "automatic"
    },
    actions: {
      selectFocusedTab({ context, prop }) {
        domQuery.raf(() => {
          const focusedValue = context.get("focusedValue");
          if (!focusedValue) return;
          const nullable = prop("deselectable") && context.get("value") === focusedValue;
          const value = nullable ? null : focusedValue;
          context.set("value", value);
        });
      },
      setFocusedValue({ context, event, flush }) {
        if (event.value == null) return;
        flush(() => {
          context.set("focusedValue", event.value);
        });
      },
      clearFocusedValue({ context }) {
        context.set("focusedValue", null);
      },
      setValue({ context, event, prop }) {
        const nullable = prop("deselectable") && context.get("value") === context.get("focusedValue");
        context.set("value", nullable ? null : event.value);
      },
      clearValue({ context }) {
        context.set("value", null);
      },
      focusFirstTab({ scope }) {
        domQuery.raf(() => {
          getFirstTriggerEl(scope)?.focus();
        });
      },
      focusLastTab({ scope }) {
        domQuery.raf(() => {
          getLastTriggerEl(scope)?.focus();
        });
      },
      focusNextTab({ context, prop, scope, event }) {
        const focusedValue = event.value ?? context.get("focusedValue");
        if (!focusedValue) return;
        const triggerEl = getNextTriggerEl(scope, {
          value: focusedValue,
          loopFocus: prop("loopFocus")
        });
        domQuery.raf(() => {
          if (prop("composite")) {
            triggerEl?.focus();
          } else if (triggerEl?.dataset.value != null) {
            context.set("focusedValue", triggerEl.dataset.value);
          }
        });
      },
      focusPrevTab({ context, prop, scope, event }) {
        const focusedValue = event.value ?? context.get("focusedValue");
        if (!focusedValue) return;
        const triggerEl = getPrevTriggerEl(scope, {
          value: focusedValue,
          loopFocus: prop("loopFocus")
        });
        domQuery.raf(() => {
          if (prop("composite")) {
            triggerEl?.focus();
          } else if (triggerEl?.dataset.value != null) {
            context.set("focusedValue", triggerEl.dataset.value);
          }
        });
      },
      syncTabIndex({ context, scope }) {
        domQuery.raf(() => {
          const value = context.get("value");
          if (!value) return;
          const contentEl = getContentEl(scope, value);
          if (!contentEl) return;
          const focusables = domQuery.getFocusables(contentEl);
          if (focusables.length > 0) {
            contentEl.removeAttribute("tabindex");
          } else {
            contentEl.setAttribute("tabindex", "0");
          }
        });
      },
      cleanupObserver({ refs }) {
        const cleanup = refs.get("indicatorCleanup");
        if (cleanup) cleanup();
      },
      allowIndicatorTransition({ context }) {
        context.set("indicatorTransition", true);
      },
      setIndicatorRect({ context, event, scope }) {
        const value = event.id ?? context.get("value");
        const indicatorEl = getIndicatorEl(scope);
        if (!indicatorEl) return;
        if (!value) {
          context.set("indicatorTransition", false);
          return;
        }
        const triggerEl = getTriggerEl(scope, value);
        if (!triggerEl) return;
        context.set("indicatorRect", getRectById(scope, value));
        domQuery.nextTick(() => {
          context.set("indicatorTransition", false);
        });
      },
      syncSsr({ context }) {
        context.set("ssr", false);
      },
      syncIndicatorRect({ context, refs, scope }) {
        const cleanup = refs.get("indicatorCleanup");
        if (cleanup) cleanup();
        const value = context.get("value");
        if (!value) {
          context.set("indicatorTransition", false);
          return;
        }
        const triggerEl = getTriggerEl(scope, value);
        const indicatorEl = getIndicatorEl(scope);
        if (!triggerEl || !indicatorEl) return;
        const indicatorCleanup = domQuery.trackElementRect([triggerEl], {
          measure(el) {
            return getOffsetRect(el);
          },
          onEntry({ rects }) {
            const [rect] = rects;
            context.set("indicatorRect", resolveRect(rect));
          }
        });
        refs.set("indicatorCleanup", indicatorCleanup);
      },
      navigateIfNeeded({ context, prop, scope }) {
        const value = context.get("value");
        if (!value) return;
        const triggerEl = getTriggerEl(scope, value);
        if (!domQuery.isAnchorElement(triggerEl)) return;
        prop("navigate")?.({ value, node: triggerEl });
      }
    }
  }
});
var props = types.createProps()([
  "activationMode",
  "composite",
  "deselectable",
  "dir",
  "getRootNode",
  "id",
  "ids",
  "loopFocus",
  "navigate",
  "onFocusChange",
  "onValueChange",
  "orientation",
  "translations",
  "value",
  "defaultValue"
]);
var splitProps = utils.createSplitProps(props);
var triggerProps = types.createProps()(["disabled", "value"]);
var splitTriggerProps = utils.createSplitProps(triggerProps);
var contentProps = types.createProps()(["value"]);
var splitContentProps = utils.createSplitProps(contentProps);

exports.anatomy = anatomy;
exports.connect = connect;
exports.contentProps = contentProps;
exports.machine = machine;
exports.props = props;
exports.splitContentProps = splitContentProps;
exports.splitProps = splitProps;
exports.splitTriggerProps = splitTriggerProps;
exports.triggerProps = triggerProps;
