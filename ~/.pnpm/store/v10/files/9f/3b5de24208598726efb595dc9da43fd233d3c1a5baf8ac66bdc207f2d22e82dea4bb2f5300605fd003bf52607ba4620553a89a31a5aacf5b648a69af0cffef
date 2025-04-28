'use strict';

var anatomy$1 = require('@zag-js/anatomy');
var core = require('@zag-js/core');
var domQuery = require('@zag-js/dom-query');
var popper = require('@zag-js/popper');
var utils = require('@zag-js/utils');
var dismissable = require('@zag-js/dismissable');
var rectUtils = require('@zag-js/rect-utils');
var types = require('@zag-js/types');

// src/menu.anatomy.ts
var anatomy = anatomy$1.createAnatomy("menu").parts(
  "arrow",
  "arrowTip",
  "content",
  "contextTrigger",
  "indicator",
  "item",
  "itemGroup",
  "itemGroupLabel",
  "itemIndicator",
  "itemText",
  "positioner",
  "separator",
  "trigger",
  "triggerItem"
);
var parts = anatomy.build();
var getTriggerId = (ctx) => ctx.ids?.trigger ?? `menu:${ctx.id}:trigger`;
var getContextTriggerId = (ctx) => ctx.ids?.contextTrigger ?? `menu:${ctx.id}:ctx-trigger`;
var getContentId = (ctx) => ctx.ids?.content ?? `menu:${ctx.id}:content`;
var getArrowId = (ctx) => ctx.ids?.arrow ?? `menu:${ctx.id}:arrow`;
var getPositionerId = (ctx) => ctx.ids?.positioner ?? `menu:${ctx.id}:popper`;
var getGroupId = (ctx, id) => ctx.ids?.group?.(id) ?? `menu:${ctx.id}:group:${id}`;
var getItemId = (ctx, id) => `${ctx.id}/${id}`;
var getItemValue = (el) => el?.dataset.value ?? null;
var getGroupLabelId = (ctx, id) => ctx.ids?.groupLabel?.(id) ?? `menu:${ctx.id}:group-label:${id}`;
var getContentEl = (ctx) => ctx.getById(getContentId(ctx));
var getPositionerEl = (ctx) => ctx.getById(getPositionerId(ctx));
var getTriggerEl = (ctx) => ctx.getById(getTriggerId(ctx));
var getItemEl = (ctx, value) => value ? ctx.getById(getItemId(ctx, value)) : null;
var getContextTriggerEl = (ctx) => ctx.getById(getContextTriggerId(ctx));
var getElements = (ctx) => {
  const ownerId = CSS.escape(getContentId(ctx));
  const selector = `[role^="menuitem"][data-ownedby=${ownerId}]:not([data-disabled])`;
  return domQuery.queryAll(getContentEl(ctx), selector);
};
var getFirstEl = (ctx) => utils.first(getElements(ctx));
var getLastEl = (ctx) => utils.last(getElements(ctx));
var isMatch = (el, value) => {
  if (!value) return false;
  return el.id === value || el.dataset.value === value;
};
var getNextEl = (ctx, opts) => {
  const items = getElements(ctx);
  const index = items.findIndex((el) => isMatch(el, opts.value));
  return utils.next(items, index, { loop: opts.loop ?? opts.loopFocus });
};
var getPrevEl = (ctx, opts) => {
  const items = getElements(ctx);
  const index = items.findIndex((el) => isMatch(el, opts.value));
  return utils.prev(items, index, { loop: opts.loop ?? opts.loopFocus });
};
var getElemByKey = (ctx, opts) => {
  const items = getElements(ctx);
  const item = items.find((el) => isMatch(el, opts.value));
  return domQuery.getByTypeahead(items, { state: opts.typeaheadState, key: opts.key, activeId: item?.id ?? null });
};
var isTargetDisabled = (v) => {
  return domQuery.isHTMLElement(v) && (v.dataset.disabled === "" || v.hasAttribute("disabled"));
};
var isTriggerItem = (el) => {
  return !!el?.getAttribute("role")?.startsWith("menuitem") && !!el?.hasAttribute("aria-controls");
};
var itemSelectEvent = "menu:select";
function dispatchSelectionEvent(el, value) {
  if (!el) return;
  const win = domQuery.getWindow(el);
  const event = new win.CustomEvent(itemSelectEvent, { detail: { value } });
  el.dispatchEvent(event);
}

// src/menu.connect.ts
function connect(service, normalize) {
  const { context, send, state, computed, prop, scope } = service;
  const open = state.hasTag("open");
  const isSubmenu = computed("isSubmenu");
  const isTypingAhead = computed("isTypingAhead");
  const composite = prop("composite");
  const currentPlacement = context.get("currentPlacement");
  const anchorPoint = context.get("anchorPoint");
  const highlightedValue = context.get("highlightedValue");
  const popperStyles = popper.getPlacementStyles({
    ...prop("positioning"),
    placement: anchorPoint ? "bottom" : currentPlacement
  });
  function getItemState(props2) {
    return {
      id: getItemId(scope, props2.value),
      disabled: !!props2.disabled,
      highlighted: highlightedValue === props2.value
    };
  }
  function getOptionItemProps(props2) {
    const valueText = props2.valueText ?? props2.value;
    return { ...props2, id: props2.value, valueText };
  }
  function getOptionItemState(props2) {
    const itemState = getItemState(getOptionItemProps(props2));
    return {
      ...itemState,
      checked: !!props2.checked
    };
  }
  function getItemProps(props2) {
    const { closeOnSelect, valueText, value } = props2;
    const itemState = getItemState(props2);
    const id = getItemId(scope, value);
    return normalize.element({
      ...parts.item.attrs,
      id,
      role: "menuitem",
      "aria-disabled": domQuery.ariaAttr(itemState.disabled),
      "data-disabled": domQuery.dataAttr(itemState.disabled),
      "data-ownedby": getContentId(scope),
      "data-highlighted": domQuery.dataAttr(itemState.highlighted),
      "data-value": value,
      "data-valuetext": valueText,
      onDragStart(event) {
        const isLink = event.currentTarget.matches("a[href]");
        if (isLink) event.preventDefault();
      },
      onPointerMove(event) {
        if (itemState.disabled) return;
        if (event.pointerType !== "mouse") return;
        const target = event.currentTarget;
        if (itemState.highlighted) return;
        send({ type: "ITEM_POINTERMOVE", id, target, closeOnSelect });
      },
      onPointerLeave(event) {
        if (itemState.disabled) return;
        if (event.pointerType !== "mouse") return;
        const pointerMoved = service.event.previous()?.type.includes("POINTER");
        if (!pointerMoved) return;
        const target = event.currentTarget;
        send({ type: "ITEM_POINTERLEAVE", id, target, closeOnSelect });
      },
      onPointerDown(event) {
        if (itemState.disabled) return;
        const target = event.currentTarget;
        send({ type: "ITEM_POINTERDOWN", target, id, closeOnSelect });
      },
      onClick(event) {
        if (domQuery.isDownloadingEvent(event)) return;
        if (domQuery.isOpeningInNewTab(event)) return;
        if (itemState.disabled) return;
        const target = event.currentTarget;
        send({ type: "ITEM_CLICK", target, id, closeOnSelect });
      }
    });
  }
  return {
    highlightedValue,
    open,
    setOpen(nextOpen) {
      const open2 = state.hasTag("open");
      if (open2 === nextOpen) return;
      send({ type: nextOpen ? "OPEN" : "CLOSE" });
    },
    setHighlightedValue(value) {
      send({ type: "HIGHLIGHTED.SET", value });
    },
    setParent(parent) {
      send({ type: "PARENT.SET", value: parent, id: parent.prop("id") });
    },
    setChild(child) {
      send({ type: "CHILD.SET", value: child, id: child.prop("id") });
    },
    reposition(options = {}) {
      send({ type: "POSITIONING.SET", options });
    },
    addItemListener(props2) {
      const node = scope.getById(props2.id);
      if (!node) return;
      const listener = () => props2.onSelect?.();
      node.addEventListener(itemSelectEvent, listener);
      return () => node.removeEventListener(itemSelectEvent, listener);
    },
    getContextTriggerProps() {
      return normalize.element({
        ...parts.contextTrigger.attrs,
        dir: prop("dir"),
        id: getContextTriggerId(scope),
        onPointerDown(event) {
          if (event.pointerType === "mouse") return;
          const point = domQuery.getEventPoint(event);
          send({ type: "CONTEXT_MENU_START", point });
        },
        onPointerCancel(event) {
          if (event.pointerType === "mouse") return;
          send({ type: "CONTEXT_MENU_CANCEL" });
        },
        onPointerMove(event) {
          if (event.pointerType === "mouse") return;
          send({ type: "CONTEXT_MENU_CANCEL" });
        },
        onPointerUp(event) {
          if (event.pointerType === "mouse") return;
          send({ type: "CONTEXT_MENU_CANCEL" });
        },
        onContextMenu(event) {
          const point = domQuery.getEventPoint(event);
          send({ type: "CONTEXT_MENU", point });
          event.preventDefault();
        },
        style: {
          WebkitTouchCallout: "none",
          WebkitUserSelect: "none",
          userSelect: "none"
        }
      });
    },
    getTriggerItemProps(childApi) {
      const triggerProps = childApi.getTriggerProps();
      return core.mergeProps(getItemProps({ value: triggerProps.id }), triggerProps);
    },
    getTriggerProps() {
      return normalize.button({
        ...isSubmenu ? parts.triggerItem.attrs : parts.trigger.attrs,
        "data-placement": context.get("currentPlacement"),
        type: "button",
        dir: prop("dir"),
        id: getTriggerId(scope),
        "data-uid": prop("id"),
        "aria-haspopup": composite ? "menu" : "dialog",
        "aria-controls": getContentId(scope),
        "aria-expanded": open || void 0,
        "data-state": open ? "open" : "closed",
        onPointerMove(event) {
          if (event.pointerType !== "mouse") return;
          const disabled = isTargetDisabled(event.currentTarget);
          if (disabled || !isSubmenu) return;
          const point = domQuery.getEventPoint(event);
          send({ type: "TRIGGER_POINTERMOVE", target: event.currentTarget, point });
        },
        onPointerLeave(event) {
          if (isTargetDisabled(event.currentTarget)) return;
          if (event.pointerType !== "mouse") return;
          if (!isSubmenu) return;
          const point = domQuery.getEventPoint(event);
          send({
            type: "TRIGGER_POINTERLEAVE",
            target: event.currentTarget,
            point
          });
        },
        onPointerDown(event) {
          if (isTargetDisabled(event.currentTarget)) return;
          if (domQuery.isContextMenuEvent(event)) return;
          event.preventDefault();
        },
        onClick(event) {
          if (event.defaultPrevented) return;
          if (isTargetDisabled(event.currentTarget)) return;
          send({ type: "TRIGGER_CLICK", target: event.currentTarget });
        },
        onBlur() {
          send({ type: "TRIGGER_BLUR" });
        },
        onFocus() {
          send({ type: "TRIGGER_FOCUS" });
        },
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          const keyMap = {
            ArrowDown() {
              send({ type: "ARROW_DOWN" });
            },
            ArrowUp() {
              send({ type: "ARROW_UP" });
            },
            Enter() {
              send({ type: "ARROW_DOWN", src: "enter" });
            },
            Space() {
              send({ type: "ARROW_DOWN", src: "space" });
            }
          };
          const key = domQuery.getEventKey(event, {
            orientation: "vertical",
            dir: prop("dir")
          });
          const exec = keyMap[key];
          if (exec) {
            event.preventDefault();
            exec(event);
          }
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
        ...parts.positioner.attrs,
        dir: prop("dir"),
        id: getPositionerId(scope),
        style: popperStyles.floating
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
    getContentProps() {
      return normalize.element({
        ...parts.content.attrs,
        id: getContentId(scope),
        "aria-label": prop("aria-label"),
        hidden: !open,
        "data-state": open ? "open" : "closed",
        role: composite ? "menu" : "dialog",
        tabIndex: 0,
        dir: prop("dir"),
        "aria-activedescendant": computed("highlightedId") || void 0,
        "aria-labelledby": getTriggerId(scope),
        "data-placement": currentPlacement,
        onPointerEnter(event) {
          if (event.pointerType !== "mouse") return;
          send({ type: "MENU_POINTERENTER" });
        },
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          if (!domQuery.isSelfTarget(event)) return;
          const target = domQuery.getEventTarget(event);
          const sameMenu = target?.closest("[role=menu]") === event.currentTarget || target === event.currentTarget;
          if (!sameMenu) return;
          if (event.key === "Tab") {
            const valid = domQuery.isValidTabEvent(event);
            if (!valid) {
              event.preventDefault();
              return;
            }
          }
          const item = getItemEl(scope, highlightedValue);
          const keyMap = {
            ArrowDown() {
              send({ type: "ARROW_DOWN" });
            },
            ArrowUp() {
              send({ type: "ARROW_UP" });
            },
            ArrowLeft() {
              send({ type: "ARROW_LEFT" });
            },
            ArrowRight() {
              send({ type: "ARROW_RIGHT" });
            },
            Enter() {
              send({ type: "ENTER" });
              if (domQuery.isAnchorElement(item)) {
                prop("navigate")?.({ value: highlightedValue, node: item });
              }
            },
            Space(event2) {
              if (isTypingAhead) {
                send({ type: "TYPEAHEAD", key: event2.key });
              } else {
                keyMap.Enter?.(event2);
              }
            },
            Home() {
              send({ type: "HOME" });
            },
            End() {
              send({ type: "END" });
            }
          };
          const key = domQuery.getEventKey(event, { dir: prop("dir") });
          const exec = keyMap[key];
          if (exec) {
            exec(event);
            event.stopPropagation();
            event.preventDefault();
            return;
          }
          if (!prop("typeahead")) return;
          if (!domQuery.isPrintableKey(event)) return;
          if (domQuery.isModifierKey(event)) return;
          if (domQuery.isEditableElement(target)) return;
          send({ type: "TYPEAHEAD", key: event.key });
          event.preventDefault();
        }
      });
    },
    getSeparatorProps() {
      return normalize.element({
        ...parts.separator.attrs,
        role: "separator",
        dir: prop("dir"),
        "aria-orientation": "horizontal"
      });
    },
    getItemState,
    getItemProps,
    getOptionItemState,
    getOptionItemProps(props2) {
      const { type, disabled, onCheckedChange, closeOnSelect } = props2;
      const option = getOptionItemProps(props2);
      const itemState = getOptionItemState(props2);
      return {
        ...getItemProps(option),
        ...normalize.element({
          "data-type": type,
          ...parts.item.attrs,
          dir: prop("dir"),
          "data-value": option.value,
          role: `menuitem${type}`,
          "aria-checked": !!itemState.checked,
          "data-state": itemState.checked ? "checked" : "unchecked",
          onClick(event) {
            if (disabled) return;
            if (domQuery.isDownloadingEvent(event)) return;
            if (domQuery.isOpeningInNewTab(event)) return;
            const target = event.currentTarget;
            send({ type: "ITEM_CLICK", target, option, closeOnSelect });
            onCheckedChange?.(!itemState.checked);
          }
        })
      };
    },
    getItemIndicatorProps(props2) {
      const itemState = getOptionItemState(props2);
      return normalize.element({
        ...parts.itemIndicator.attrs,
        dir: prop("dir"),
        "data-disabled": domQuery.dataAttr(itemState.disabled),
        "data-highlighted": domQuery.dataAttr(itemState.highlighted),
        "data-state": itemState.checked ? "checked" : "unchecked",
        hidden: !itemState.checked
      });
    },
    getItemTextProps(props2) {
      const itemState = getOptionItemState(props2);
      return normalize.element({
        ...parts.itemText.attrs,
        dir: prop("dir"),
        "data-disabled": domQuery.dataAttr(itemState.disabled),
        "data-highlighted": domQuery.dataAttr(itemState.highlighted),
        "data-state": itemState.checked ? "checked" : "unchecked"
      });
    },
    getItemGroupLabelProps(props2) {
      return normalize.element({
        ...parts.itemGroupLabel.attrs,
        id: getGroupLabelId(scope, props2.htmlFor),
        dir: prop("dir")
      });
    },
    getItemGroupProps(props2) {
      return normalize.element({
        id: getGroupId(scope, props2.id),
        ...parts.itemGroup.attrs,
        dir: prop("dir"),
        "aria-labelledby": getGroupLabelId(scope, props2.id),
        role: "group"
      });
    }
  };
}
var { not, and, or } = core.createGuards();
var machine = core.createMachine({
  props({ props: props2 }) {
    return {
      closeOnSelect: true,
      typeahead: true,
      composite: true,
      loopFocus: false,
      navigate(details) {
        domQuery.clickIfLink(details.node);
      },
      ...props2,
      positioning: {
        placement: "bottom-start",
        gutter: 8,
        ...props2.positioning
      }
    };
  },
  initialState({ prop }) {
    const open = prop("open") || prop("defaultOpen");
    return open ? "open" : "idle";
  },
  context({ bindable, prop }) {
    return {
      suspendPointer: bindable(() => ({
        defaultValue: false
      })),
      highlightedValue: bindable(() => ({
        defaultValue: prop("defaultHighlightedValue") || null,
        value: prop("highlightedValue"),
        onChange(value) {
          prop("onHighlightChange")?.({ highlightedValue: value });
        }
      })),
      lastHighlightedValue: bindable(() => ({
        defaultValue: null
      })),
      currentPlacement: bindable(() => ({
        defaultValue: void 0
      })),
      intentPolygon: bindable(() => ({
        defaultValue: null
      })),
      anchorPoint: bindable(() => ({
        defaultValue: null,
        hash(value) {
          return `x: ${value?.x}, y: ${value?.y}`;
        }
      }))
    };
  },
  refs() {
    return {
      parent: null,
      children: {},
      typeaheadState: { ...domQuery.getByTypeahead.defaultOptions },
      positioningOverride: {}
    };
  },
  computed: {
    isSubmenu: ({ refs }) => refs.get("parent") != null,
    isRtl: ({ prop }) => prop("dir") === "rtl",
    isTypingAhead: ({ refs }) => refs.get("typeaheadState").keysSoFar !== "",
    highlightedId: ({ context, scope, refs }) => resolveItemId(refs.get("children"), context.get("highlightedValue"), scope)
  },
  watch({ track, action, context, computed, prop }) {
    track([() => computed("isSubmenu")], () => {
      action(["setSubmenuPlacement"]);
    });
    track([() => context.hash("anchorPoint")], () => {
      action(["reposition"]);
    });
    track([() => prop("open")], () => {
      action(["toggleVisibility"]);
    });
  },
  on: {
    "PARENT.SET": {
      actions: ["setParentMenu"]
    },
    "CHILD.SET": {
      actions: ["setChildMenu"]
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
    OPEN_AUTOFOCUS: [
      {
        guard: "isOpenControlled",
        actions: ["invokeOnOpen"]
      },
      {
        // internal: true,
        target: "open",
        actions: ["highlightFirstItem", "invokeOnOpen"]
      }
    ],
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
    "HIGHLIGHTED.RESTORE": {
      actions: ["restoreHighlightedItem"]
    },
    "HIGHLIGHTED.SET": {
      actions: ["setHighlightedItem"]
    }
  },
  states: {
    idle: {
      tags: ["closed"],
      on: {
        "CONTROLLED.OPEN": {
          target: "open"
        },
        "CONTROLLED.CLOSE": {
          target: "closed"
        },
        CONTEXT_MENU_START: {
          target: "opening:contextmenu",
          actions: ["setAnchorPoint"]
        },
        CONTEXT_MENU: [
          {
            guard: "isOpenControlled",
            actions: ["setAnchorPoint", "invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setAnchorPoint", "invokeOnOpen"]
          }
        ],
        TRIGGER_CLICK: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen"]
          }
        ],
        TRIGGER_FOCUS: {
          guard: not("isSubmenu"),
          target: "closed"
        },
        TRIGGER_POINTERMOVE: {
          guard: "isSubmenu",
          target: "opening"
        }
      }
    },
    "opening:contextmenu": {
      tags: ["closed"],
      effects: ["waitForLongPress"],
      on: {
        "CONTROLLED.OPEN": { target: "open" },
        "CONTROLLED.CLOSE": { target: "closed" },
        CONTEXT_MENU_CANCEL: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        "LONG_PRESS.OPEN": [
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
    },
    opening: {
      tags: ["closed"],
      effects: ["waitForOpenDelay"],
      on: {
        "CONTROLLED.OPEN": {
          target: "open"
        },
        "CONTROLLED.CLOSE": {
          target: "closed"
        },
        BLUR: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        TRIGGER_POINTERLEAVE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        "DELAY.OPEN": [
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
    },
    closing: {
      tags: ["open"],
      effects: ["trackPointerMove", "trackInteractOutside", "waitForCloseDelay"],
      on: {
        "CONTROLLED.OPEN": {
          target: "open"
        },
        "CONTROLLED.CLOSE": {
          target: "closed",
          actions: ["focusParentMenu", "restoreParentHighlightedItem"]
        },
        // don't invoke on open here since the menu is still open (we're only keeping it open)
        MENU_POINTERENTER: {
          target: "open",
          actions: ["clearIntentPolygon"]
        },
        POINTER_MOVED_AWAY_FROM_SUBMENU: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["focusParentMenu", "restoreParentHighlightedItem"]
          }
        ],
        "DELAY.CLOSE": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "closed",
            actions: ["focusParentMenu", "restoreParentHighlightedItem", "invokeOnClose"]
          }
        ]
      }
    },
    closed: {
      tags: ["closed"],
      entry: ["clearHighlightedItem", "focusTrigger", "resumePointer"],
      on: {
        "CONTROLLED.OPEN": [
          {
            guard: or("isOpenAutoFocusEvent", "isArrowDownEvent"),
            target: "open",
            actions: ["highlightFirstItem"]
          },
          {
            guard: "isArrowUpEvent",
            target: "open",
            actions: ["highlightLastItem"]
          },
          {
            target: "open"
          }
        ],
        CONTEXT_MENU_START: {
          target: "opening:contextmenu",
          actions: ["setAnchorPoint"]
        },
        CONTEXT_MENU: [
          {
            guard: "isOpenControlled",
            actions: ["setAnchorPoint", "invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setAnchorPoint", "invokeOnOpen"]
          }
        ],
        TRIGGER_CLICK: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen"]
          }
        ],
        TRIGGER_POINTERMOVE: {
          guard: "isTriggerItem",
          target: "opening"
        },
        TRIGGER_BLUR: { target: "idle" },
        ARROW_DOWN: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["highlightFirstItem", "invokeOnOpen"]
          }
        ],
        ARROW_UP: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["highlightLastItem", "invokeOnOpen"]
          }
        ]
      }
    },
    open: {
      tags: ["open"],
      effects: ["trackInteractOutside", "trackPositioning", "scrollToHighlightedItem"],
      entry: ["focusMenu", "resumePointer"],
      on: {
        "CONTROLLED.CLOSE": [
          {
            target: "closed",
            guard: "isArrowLeftEvent",
            actions: ["focusParentMenu"]
          },
          {
            target: "closed"
          }
        ],
        TRIGGER_CLICK: [
          {
            guard: and(not("isTriggerItem"), "isOpenControlled"),
            actions: ["invokeOnClose"]
          },
          {
            guard: not("isTriggerItem"),
            target: "closed",
            actions: ["invokeOnClose"]
          }
        ],
        CONTEXT_MENU: {
          actions: ["setAnchorPoint", "focusMenu"]
        },
        ARROW_UP: {
          actions: ["highlightPrevItem", "focusMenu"]
        },
        ARROW_DOWN: {
          actions: ["highlightNextItem", "focusMenu"]
        },
        ARROW_LEFT: [
          {
            guard: and("isSubmenu", "isOpenControlled"),
            actions: ["invokeOnClose"]
          },
          {
            guard: "isSubmenu",
            target: "closed",
            actions: ["focusParentMenu", "invokeOnClose"]
          }
        ],
        HOME: {
          actions: ["highlightFirstItem", "focusMenu"]
        },
        END: {
          actions: ["highlightLastItem", "focusMenu"]
        },
        ARROW_RIGHT: {
          guard: "isTriggerItemHighlighted",
          actions: ["openSubmenu"]
        },
        ENTER: [
          {
            guard: "isTriggerItemHighlighted",
            actions: ["openSubmenu"]
          },
          {
            actions: ["clickHighlightedItem"]
          }
        ],
        ITEM_POINTERMOVE: [
          {
            guard: not("isPointerSuspended"),
            actions: ["setHighlightedItem", "focusMenu"]
          },
          {
            actions: ["setLastHighlightedItem"]
          }
        ],
        ITEM_POINTERLEAVE: {
          guard: and(not("isPointerSuspended"), not("isTriggerItem")),
          actions: ["clearHighlightedItem"]
        },
        ITEM_CLICK: [
          // == grouped ==
          {
            guard: and(
              not("isTriggerItemHighlighted"),
              not("isHighlightedItemEditable"),
              "closeOnSelect",
              "isOpenControlled"
            ),
            actions: ["invokeOnSelect", "setOptionState", "closeRootMenu", "invokeOnClose"]
          },
          {
            guard: and(not("isTriggerItemHighlighted"), not("isHighlightedItemEditable"), "closeOnSelect"),
            target: "closed",
            actions: ["invokeOnSelect", "setOptionState", "closeRootMenu", "invokeOnClose"]
          },
          //
          {
            guard: and(not("isTriggerItemHighlighted"), not("isHighlightedItemEditable")),
            actions: ["invokeOnSelect", "setOptionState"]
          },
          { actions: ["setHighlightedItem"] }
        ],
        TRIGGER_POINTERMOVE: {
          guard: "isTriggerItem",
          actions: ["setIntentPolygon"]
        },
        TRIGGER_POINTERLEAVE: {
          target: "closing"
        },
        ITEM_POINTERDOWN: {
          actions: ["setHighlightedItem"]
        },
        TYPEAHEAD: {
          actions: ["highlightMatchedItem"]
        },
        FOCUS_MENU: {
          actions: ["focusMenu"]
        },
        "POSITIONING.SET": {
          actions: ["reposition"]
        }
      }
    }
  },
  implementations: {
    guards: {
      closeOnSelect: ({ prop, event }) => !!(event?.closeOnSelect ?? prop("closeOnSelect")),
      // whether the trigger is also a menu item
      isTriggerItem: ({ event }) => isTriggerItem(event.target),
      // whether the trigger item is the active item
      isTriggerItemHighlighted: ({ event, scope, computed }) => {
        const target = event.target ?? scope.getById(computed("highlightedId"));
        return !!target?.hasAttribute("aria-controls");
      },
      isSubmenu: ({ computed }) => computed("isSubmenu"),
      isPointerSuspended: ({ context }) => context.get("suspendPointer"),
      isHighlightedItemEditable: ({ scope, computed }) => domQuery.isEditableElement(scope.getById(computed("highlightedId"))),
      // guard assertions (for controlled mode)
      isOpenControlled: ({ prop }) => prop("open") !== void 0,
      isArrowLeftEvent: ({ event }) => event.previousEvent?.type === "ARROW_LEFT",
      isArrowUpEvent: ({ event }) => event.previousEvent?.type === "ARROW_UP",
      isArrowDownEvent: ({ event }) => event.previousEvent?.type === "ARROW_DOWN",
      isOpenAutoFocusEvent: ({ event }) => event.previousEvent?.type === "OPEN_AUTOFOCUS"
    },
    effects: {
      waitForOpenDelay({ send }) {
        const timer = setTimeout(() => {
          send({ type: "DELAY.OPEN" });
        }, 100);
        return () => clearTimeout(timer);
      },
      waitForCloseDelay({ send }) {
        const timer = setTimeout(() => {
          send({ type: "DELAY.CLOSE" });
        }, 300);
        return () => clearTimeout(timer);
      },
      waitForLongPress({ send }) {
        const timer = setTimeout(() => {
          send({ type: "LONG_PRESS.OPEN" });
        }, 700);
        return () => clearTimeout(timer);
      },
      trackPositioning({ context, prop, scope, refs }) {
        if (!!getContextTriggerEl(scope)) return;
        const positioning = {
          ...prop("positioning"),
          ...refs.get("positioningOverride")
        };
        context.set("currentPlacement", positioning.placement);
        const getPositionerEl2 = () => getPositionerEl(scope);
        return popper.getPlacement(getTriggerEl(scope), getPositionerEl2, {
          ...positioning,
          defer: true,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      trackInteractOutside({ refs, scope, prop, computed, send }) {
        const getContentEl2 = () => getContentEl(scope);
        let restoreFocus = true;
        return dismissable.trackDismissableElement(getContentEl2, {
          defer: true,
          exclude: [getTriggerEl(scope)],
          onInteractOutside: prop("onInteractOutside"),
          onFocusOutside: prop("onFocusOutside"),
          onEscapeKeyDown(event) {
            prop("onEscapeKeyDown")?.(event);
            if (computed("isSubmenu")) event.preventDefault();
            closeRootMenu({ parent: refs.get("parent") });
          },
          onPointerDownOutside(event) {
            const target = domQuery.getEventTarget(event.detail.originalEvent);
            const isWithinContextTrigger = domQuery.contains(getContextTriggerEl(scope), target);
            if (isWithinContextTrigger && event.detail.contextmenu) {
              event.preventDefault();
              return;
            }
            restoreFocus = !event.detail.focusable;
            prop("onPointerDownOutside")?.(event);
          },
          onDismiss() {
            send({ type: "CLOSE", src: "interact-outside", restoreFocus });
          }
        });
      },
      trackPointerMove({ context, scope, send, refs, flush }) {
        const parent = refs.get("parent");
        flush(() => {
          parent.context.set("suspendPointer", true);
        });
        const doc = scope.getDoc();
        return domQuery.addDomEvent(doc, "pointermove", (e) => {
          const isMovingToSubmenu = isWithinPolygon(context.get("intentPolygon"), {
            x: e.clientX,
            y: e.clientY
          });
          if (!isMovingToSubmenu) {
            send({ type: "POINTER_MOVED_AWAY_FROM_SUBMENU" });
            parent.context.set("suspendPointer", false);
          }
        });
      },
      scrollToHighlightedItem({ event, scope, computed }) {
        const exec = () => {
          if (event.type.startsWith("ITEM_POINTER")) return;
          const itemEl = scope.getById(computed("highlightedId"));
          const contentEl2 = getContentEl(scope);
          domQuery.scrollIntoView(itemEl, { rootEl: contentEl2, block: "nearest" });
        };
        domQuery.raf(() => exec());
        const contentEl = () => getContentEl(scope);
        return domQuery.observeAttributes(contentEl, {
          defer: true,
          attributes: ["aria-activedescendant"],
          callback: exec
        });
      }
    },
    actions: {
      setAnchorPoint({ context, event }) {
        context.set("anchorPoint", event.point);
      },
      setSubmenuPlacement({ computed, refs }) {
        if (!computed("isSubmenu")) return;
        const placement = computed("isRtl") ? "left-start" : "right-start";
        refs.set("positioningOverride", { placement, gutter: 0 });
      },
      reposition({ context, scope, prop, event, refs }) {
        const getPositionerEl2 = () => getPositionerEl(scope);
        const anchorPoint = context.get("anchorPoint");
        const getAnchorRect = anchorPoint ? () => ({ width: 0, height: 0, ...anchorPoint }) : void 0;
        const positioning = {
          ...prop("positioning"),
          ...refs.get("positioningOverride")
        };
        popper.getPlacement(getTriggerEl(scope), getPositionerEl2, {
          ...positioning,
          defer: true,
          getAnchorRect,
          ...event.options ?? {},
          listeners: false,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      setOptionState({ event }) {
        if (!event.option) return;
        const { checked, onCheckedChange, type } = event.option;
        if (type === "radio") {
          onCheckedChange?.(true);
        } else if (type === "checkbox") {
          onCheckedChange?.(!checked);
        }
      },
      clickHighlightedItem({ scope, computed }) {
        const itemEl = scope.getById(computed("highlightedId"));
        if (!itemEl || itemEl.dataset.disabled) return;
        queueMicrotask(() => itemEl.click());
      },
      setIntentPolygon({ context, scope, event }) {
        const menu = getContentEl(scope);
        const placement = context.get("currentPlacement");
        if (!menu || !placement) return;
        const rect = menu.getBoundingClientRect();
        const polygon = rectUtils.getElementPolygon(rect, placement);
        if (!polygon) return;
        const rightSide = popper.getPlacementSide(placement) === "right";
        const bleed = rightSide ? -5 : 5;
        context.set("intentPolygon", [{ ...event.point, x: event.point.x + bleed }, ...polygon]);
      },
      clearIntentPolygon({ context }) {
        context.set("intentPolygon", null);
      },
      resumePointer({ refs, flush }) {
        const parent = refs.get("parent");
        if (!parent) return;
        flush(() => {
          parent.context.set("suspendPointer", false);
        });
      },
      setHighlightedItem({ context, event }) {
        const value = event.value || getItemValue(event.target);
        context.set("highlightedValue", value);
      },
      clearHighlightedItem({ context }) {
        context.set("highlightedValue", null);
      },
      focusMenu({ scope }) {
        domQuery.raf(() => {
          const contentEl = getContentEl(scope);
          const initialFocusEl = domQuery.getInitialFocus({
            root: contentEl,
            enabled: !domQuery.contains(contentEl, scope.getActiveElement()),
            filter(node) {
              return !node.role?.startsWith("menuitem");
            }
          });
          initialFocusEl?.focus({ preventScroll: true });
        });
      },
      highlightFirstItem({ context, scope }) {
        const fn = getContentEl(scope) ? queueMicrotask : domQuery.raf;
        fn(() => {
          const first2 = getFirstEl(scope);
          if (!first2) return;
          context.set("highlightedValue", getItemValue(first2));
        });
      },
      highlightLastItem({ context, scope }) {
        const fn = getContentEl(scope) ? queueMicrotask : domQuery.raf;
        fn(() => {
          const last2 = getLastEl(scope);
          if (!last2) return;
          context.set("highlightedValue", getItemValue(last2));
        });
      },
      highlightNextItem({ context, scope, event, prop }) {
        const next2 = getNextEl(scope, {
          loop: event.loop,
          value: context.get("highlightedValue"),
          loopFocus: prop("loopFocus")
        });
        context.set("highlightedValue", getItemValue(next2));
      },
      highlightPrevItem({ context, scope, event, prop }) {
        const prev2 = getPrevEl(scope, {
          loop: event.loop,
          value: context.get("highlightedValue"),
          loopFocus: prop("loopFocus")
        });
        context.set("highlightedValue", getItemValue(prev2));
      },
      invokeOnSelect({ context, prop, scope }) {
        const value = context.get("highlightedValue");
        if (value == null) return;
        const node = getItemEl(scope, value);
        dispatchSelectionEvent(node, value);
        prop("onSelect")?.({ value });
      },
      focusTrigger({ scope, context, event, computed }) {
        if (computed("isSubmenu") || context.get("anchorPoint") || event.restoreFocus === false) return;
        queueMicrotask(() => getTriggerEl(scope)?.focus({ preventScroll: true }));
      },
      highlightMatchedItem({ scope, context, event, refs }) {
        const node = getElemByKey(scope, {
          key: event.key,
          value: context.get("highlightedValue"),
          typeaheadState: refs.get("typeaheadState")
        });
        if (!node) return;
        context.set("highlightedValue", getItemValue(node));
      },
      setParentMenu({ refs, event }) {
        refs.set("parent", event.value);
      },
      setChildMenu({ refs, event }) {
        const children = refs.get("children");
        children[event.id] = event.value;
        refs.set("children", children);
      },
      closeRootMenu({ refs }) {
        closeRootMenu({ parent: refs.get("parent") });
      },
      openSubmenu({ refs, scope, computed }) {
        const item = scope.getById(computed("highlightedId"));
        const id = item?.getAttribute("data-uid");
        const children = refs.get("children");
        const child = id ? children[id] : null;
        child?.send({ type: "OPEN_AUTOFOCUS" });
      },
      focusParentMenu({ refs }) {
        refs.get("parent")?.send({ type: "FOCUS_MENU" });
      },
      setLastHighlightedItem({ context, event }) {
        context.set("lastHighlightedValue", getItemValue(event.target));
      },
      restoreHighlightedItem({ context }) {
        if (!context.get("lastHighlightedValue")) return;
        context.set("highlightedValue", context.get("lastHighlightedValue"));
        context.set("lastHighlightedValue", null);
      },
      restoreParentHighlightedItem({ refs }) {
        refs.get("parent")?.send({ type: "HIGHLIGHTED.RESTORE" });
      },
      invokeOnOpen({ prop }) {
        prop("onOpenChange")?.({ open: true });
      },
      invokeOnClose({ prop }) {
        prop("onOpenChange")?.({ open: false });
      },
      toggleVisibility({ prop, event, send }) {
        send({
          type: prop("open") ? "CONTROLLED.OPEN" : "CONTROLLED.CLOSE",
          previousEvent: event
        });
      }
    }
  }
});
function closeRootMenu(ctx) {
  let parent = ctx.parent;
  while (parent && parent.computed("isSubmenu")) {
    parent = parent.refs.get("parent");
  }
  parent?.send({ type: "CLOSE" });
}
function isWithinPolygon(polygon, point) {
  if (!polygon) return false;
  return rectUtils.isPointInPolygon(polygon, point);
}
function resolveItemId(children, value, scope) {
  const hasChildren = Object.keys(children).length > 0;
  if (!value) return null;
  if (!hasChildren) {
    return getItemId(scope, value);
  }
  for (const id in children) {
    const childMenu = children[id];
    const childTriggerId = getTriggerId(childMenu.scope);
    if (childTriggerId === value) {
      return childTriggerId;
    }
  }
  return getItemId(scope, value);
}
var props = types.createProps()([
  "anchorPoint",
  "aria-label",
  "closeOnSelect",
  "composite",
  "defaultHighlightedValue",
  "defaultOpen",
  "dir",
  "getRootNode",
  "highlightedValue",
  "id",
  "ids",
  "loopFocus",
  "navigate",
  "onEscapeKeyDown",
  "onFocusOutside",
  "onHighlightChange",
  "onInteractOutside",
  "onOpenChange",
  "onPointerDownOutside",
  "onSelect",
  "open",
  "positioning",
  "typeahead"
]);
var splitProps = utils.createSplitProps(props);
var itemProps = types.createProps()(["closeOnSelect", "disabled", "value", "valueText"]);
var splitItemProps = utils.createSplitProps(itemProps);
var itemGroupLabelProps = types.createProps()(["htmlFor"]);
var splitItemGroupLabelProps = utils.createSplitProps(itemGroupLabelProps);
var itemGroupProps = types.createProps()(["id"]);
var splitItemGroupProps = utils.createSplitProps(itemGroupProps);
var optionItemProps = types.createProps()([
  "checked",
  "closeOnSelect",
  "disabled",
  "onCheckedChange",
  "type",
  "value",
  "valueText"
]);
var splitOptionItemProps = utils.createSplitProps(optionItemProps);

exports.anatomy = anatomy;
exports.connect = connect;
exports.itemGroupLabelProps = itemGroupLabelProps;
exports.itemGroupProps = itemGroupProps;
exports.itemProps = itemProps;
exports.machine = machine;
exports.optionItemProps = optionItemProps;
exports.props = props;
exports.splitItemGroupLabelProps = splitItemGroupLabelProps;
exports.splitItemGroupProps = splitItemGroupProps;
exports.splitItemProps = splitItemProps;
exports.splitOptionItemProps = splitOptionItemProps;
exports.splitProps = splitProps;
