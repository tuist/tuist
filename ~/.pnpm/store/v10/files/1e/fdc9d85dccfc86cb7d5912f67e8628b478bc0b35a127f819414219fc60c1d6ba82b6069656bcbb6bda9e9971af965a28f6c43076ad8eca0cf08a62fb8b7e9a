'use strict';

var anatomy$1 = require('@zag-js/anatomy');
var collection$1 = require('@zag-js/collection');
var domQuery = require('@zag-js/dom-query');
var popper = require('@zag-js/popper');
var utils = require('@zag-js/utils');
var core = require('@zag-js/core');
var dismissable = require('@zag-js/dismissable');
var types = require('@zag-js/types');

// src/select.anatomy.ts
var anatomy = anatomy$1.createAnatomy("select").parts(
  "label",
  "positioner",
  "trigger",
  "indicator",
  "clearTrigger",
  "item",
  "itemText",
  "itemIndicator",
  "itemGroup",
  "itemGroupLabel",
  "list",
  "content",
  "root",
  "control",
  "valueText"
);
var parts = anatomy.build();
var collection = (options) => {
  return new collection$1.ListCollection(options);
};
collection.empty = () => {
  return new collection$1.ListCollection({ items: [] });
};

// src/select.dom.ts
var getRootId = (ctx) => ctx.ids?.root ?? `select:${ctx.id}`;
var getContentId = (ctx) => ctx.ids?.content ?? `select:${ctx.id}:content`;
var getTriggerId = (ctx) => ctx.ids?.trigger ?? `select:${ctx.id}:trigger`;
var getClearTriggerId = (ctx) => ctx.ids?.clearTrigger ?? `select:${ctx.id}:clear-trigger`;
var getLabelId = (ctx) => ctx.ids?.label ?? `select:${ctx.id}:label`;
var getControlId = (ctx) => ctx.ids?.control ?? `select:${ctx.id}:control`;
var getItemId = (ctx, id) => ctx.ids?.item?.(id) ?? `select:${ctx.id}:option:${id}`;
var getHiddenSelectId = (ctx) => ctx.ids?.hiddenSelect ?? `select:${ctx.id}:select`;
var getPositionerId = (ctx) => ctx.ids?.positioner ?? `select:${ctx.id}:positioner`;
var getItemGroupId = (ctx, id) => ctx.ids?.itemGroup?.(id) ?? `select:${ctx.id}:optgroup:${id}`;
var getItemGroupLabelId = (ctx, id) => ctx.ids?.itemGroupLabel?.(id) ?? `select:${ctx.id}:optgroup-label:${id}`;
var getHiddenSelectEl = (ctx) => ctx.getById(getHiddenSelectId(ctx));
var getContentEl = (ctx) => ctx.getById(getContentId(ctx));
var getTriggerEl = (ctx) => ctx.getById(getTriggerId(ctx));
var getClearTriggerEl = (ctx) => ctx.getById(getClearTriggerId(ctx));
var getPositionerEl = (ctx) => ctx.getById(getPositionerId(ctx));
var getItemEl = (ctx, id) => ctx.getById(getItemId(ctx, id));

// src/select.connect.ts
function connect(service, normalize) {
  const { context, prop, scope, state, computed, send } = service;
  const disabled = prop("disabled") || context.get("fieldsetDisabled");
  const invalid = prop("invalid");
  const readOnly = prop("readOnly");
  const composite = prop("composite");
  const collection2 = prop("collection");
  const open = state.hasTag("open");
  const focused = state.matches("focused");
  const highlightedValue = context.get("highlightedValue");
  const highlightedItem = context.get("highlightedItem");
  const selectedItems = context.get("selectedItems");
  const currentPlacement = context.get("currentPlacement");
  const isTypingAhead = computed("isTypingAhead");
  const interactive = computed("isInteractive");
  const ariaActiveDescendant = highlightedValue ? getItemId(scope, highlightedValue) : void 0;
  function getItemState(props2) {
    const _disabled = collection2.getItemDisabled(props2.item);
    const value = collection2.getItemValue(props2.item);
    utils.ensure(value, () => `[zag-js] No value found for item ${JSON.stringify(props2.item)}`);
    return {
      value,
      disabled: Boolean(disabled || _disabled),
      highlighted: highlightedValue === value,
      selected: context.get("value").includes(value)
    };
  }
  const popperStyles = popper.getPlacementStyles({
    ...prop("positioning"),
    placement: currentPlacement
  });
  return {
    open,
    focused,
    empty: context.get("value").length === 0,
    highlightedItem,
    highlightedValue,
    selectedItems,
    hasSelectedItems: computed("hasSelectedItems"),
    value: context.get("value"),
    valueAsString: context.get("valueAsString"),
    collection: collection2,
    multiple: !!prop("multiple"),
    disabled: !!disabled,
    reposition(options = {}) {
      send({ type: "POSITIONING.SET", options });
    },
    focus() {
      getTriggerEl(scope)?.focus({ preventScroll: true });
    },
    setOpen(nextOpen) {
      const open2 = state.hasTag("open");
      if (open2 === nextOpen) return;
      send({ type: nextOpen ? "OPEN" : "CLOSE" });
    },
    selectValue(value) {
      send({ type: "ITEM.SELECT", value });
    },
    setValue(value) {
      send({ type: "VALUE.SET", value });
    },
    selectAll() {
      send({ type: "VALUE.SET", value: collection2.getValues() });
    },
    highlightValue(value) {
      send({ type: "HIGHLIGHTED_VALUE.SET", value });
    },
    clearValue(value) {
      if (value) {
        send({ type: "ITEM.CLEAR", value });
      } else {
        send({ type: "VALUE.CLEAR" });
      }
    },
    getItemState,
    getRootProps() {
      return normalize.element({
        ...parts.root.attrs,
        dir: prop("dir"),
        id: getRootId(scope),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly)
      });
    },
    getLabelProps() {
      return normalize.label({
        dir: prop("dir"),
        id: getLabelId(scope),
        ...parts.label.attrs,
        "data-disabled": domQuery.dataAttr(disabled),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly),
        htmlFor: getHiddenSelectId(scope),
        onClick(event) {
          if (event.defaultPrevented) return;
          if (disabled) return;
          getTriggerEl(scope)?.focus({ preventScroll: true });
        }
      });
    },
    getControlProps() {
      return normalize.element({
        ...parts.control.attrs,
        dir: prop("dir"),
        id: getControlId(scope),
        "data-state": open ? "open" : "closed",
        "data-focus": domQuery.dataAttr(focused),
        "data-disabled": domQuery.dataAttr(disabled),
        "data-invalid": domQuery.dataAttr(invalid)
      });
    },
    getValueTextProps() {
      return normalize.element({
        ...parts.valueText.attrs,
        dir: prop("dir"),
        "data-disabled": domQuery.dataAttr(disabled),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-focus": domQuery.dataAttr(focused)
      });
    },
    getTriggerProps() {
      return normalize.button({
        id: getTriggerId(scope),
        disabled,
        dir: prop("dir"),
        type: "button",
        role: "combobox",
        "aria-controls": getContentId(scope),
        "aria-expanded": open,
        "aria-haspopup": "listbox",
        "data-state": open ? "open" : "closed",
        "aria-invalid": invalid,
        "aria-labelledby": getLabelId(scope),
        ...parts.trigger.attrs,
        "data-disabled": domQuery.dataAttr(disabled),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly),
        "data-placement": currentPlacement,
        "data-placeholder-shown": domQuery.dataAttr(!computed("hasSelectedItems")),
        onClick(event) {
          if (!interactive) return;
          if (event.defaultPrevented) return;
          send({ type: "TRIGGER.CLICK" });
        },
        onFocus() {
          send({ type: "TRIGGER.FOCUS" });
        },
        onBlur() {
          send({ type: "TRIGGER.BLUR" });
        },
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          if (!interactive) return;
          const keyMap = {
            ArrowUp() {
              send({ type: "TRIGGER.ARROW_UP" });
            },
            ArrowDown(event2) {
              send({ type: event2.altKey ? "OPEN" : "TRIGGER.ARROW_DOWN" });
            },
            ArrowLeft() {
              send({ type: "TRIGGER.ARROW_LEFT" });
            },
            ArrowRight() {
              send({ type: "TRIGGER.ARROW_RIGHT" });
            },
            Home() {
              send({ type: "TRIGGER.HOME" });
            },
            End() {
              send({ type: "TRIGGER.END" });
            },
            Enter() {
              send({ type: "TRIGGER.ENTER" });
            },
            Space(event2) {
              if (isTypingAhead) {
                send({ type: "TRIGGER.TYPEAHEAD", key: event2.key });
              } else {
                send({ type: "TRIGGER.ENTER" });
              }
            }
          };
          const exec = keyMap[domQuery.getEventKey(event, {
            dir: prop("dir"),
            orientation: "vertical"
          })];
          if (exec) {
            exec(event);
            event.preventDefault();
            return;
          }
          if (domQuery.getByTypeahead.isValidEvent(event)) {
            send({ type: "TRIGGER.TYPEAHEAD", key: event.key });
            event.preventDefault();
          }
        }
      });
    },
    getIndicatorProps() {
      return normalize.element({
        ...parts.indicator.attrs,
        dir: prop("dir"),
        "aria-hidden": true,
        "data-state": open ? "open" : "closed",
        "data-disabled": domQuery.dataAttr(disabled),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly)
      });
    },
    getItemProps(props2) {
      const itemState = getItemState(props2);
      return normalize.element({
        id: getItemId(scope, itemState.value),
        role: "option",
        ...parts.item.attrs,
        dir: prop("dir"),
        "data-value": itemState.value,
        "aria-selected": itemState.selected,
        "data-state": itemState.selected ? "checked" : "unchecked",
        "data-highlighted": domQuery.dataAttr(itemState.highlighted),
        "data-disabled": domQuery.dataAttr(itemState.disabled),
        "aria-disabled": domQuery.ariaAttr(itemState.disabled),
        onPointerMove(event) {
          if (itemState.disabled || event.pointerType !== "mouse") return;
          if (itemState.value === highlightedValue) return;
          send({ type: "ITEM.POINTER_MOVE", value: itemState.value });
        },
        onClick(event) {
          if (event.defaultPrevented) return;
          if (itemState.disabled) return;
          send({ type: "ITEM.CLICK", src: "pointerup", value: itemState.value });
        },
        onPointerLeave(event) {
          if (itemState.disabled) return;
          if (props2.persistFocus) return;
          if (event.pointerType !== "mouse") return;
          const pointerMoved = service.event.previous()?.type.includes("POINTER");
          if (!pointerMoved) return;
          send({ type: "ITEM.POINTER_LEAVE" });
        }
      });
    },
    getItemTextProps(props2) {
      const itemState = getItemState(props2);
      return normalize.element({
        ...parts.itemText.attrs,
        "data-state": itemState.selected ? "checked" : "unchecked",
        "data-disabled": domQuery.dataAttr(itemState.disabled),
        "data-highlighted": domQuery.dataAttr(itemState.highlighted)
      });
    },
    getItemIndicatorProps(props2) {
      const itemState = getItemState(props2);
      return normalize.element({
        "aria-hidden": true,
        ...parts.itemIndicator.attrs,
        "data-state": itemState.selected ? "checked" : "unchecked",
        hidden: !itemState.selected
      });
    },
    getItemGroupLabelProps(props2) {
      const { htmlFor } = props2;
      return normalize.element({
        ...parts.itemGroupLabel.attrs,
        id: getItemGroupLabelId(scope, htmlFor),
        dir: prop("dir"),
        role: "presentation"
      });
    },
    getItemGroupProps(props2) {
      const { id } = props2;
      return normalize.element({
        ...parts.itemGroup.attrs,
        "data-disabled": domQuery.dataAttr(disabled),
        id: getItemGroupId(scope, id),
        "aria-labelledby": getItemGroupLabelId(scope, id),
        role: "group",
        dir: prop("dir")
      });
    },
    getClearTriggerProps() {
      return normalize.button({
        ...parts.clearTrigger.attrs,
        id: getClearTriggerId(scope),
        type: "button",
        "aria-label": "Clear value",
        "data-invalid": domQuery.dataAttr(invalid),
        disabled,
        hidden: !computed("hasSelectedItems"),
        dir: prop("dir"),
        onClick(event) {
          if (event.defaultPrevented) return;
          send({ type: "CLEAR.CLICK" });
        }
      });
    },
    getHiddenSelectProps() {
      const value = context.get("value");
      const defaultValue = prop("multiple") ? value : value?.[0];
      return normalize.select({
        name: prop("name"),
        form: prop("form"),
        disabled,
        multiple: prop("multiple"),
        required: prop("required"),
        "aria-hidden": true,
        id: getHiddenSelectId(scope),
        defaultValue,
        style: domQuery.visuallyHiddenStyle,
        tabIndex: -1,
        // Some browser extensions will focus the hidden select.
        // Let's forward the focus to the trigger.
        onFocus() {
          getTriggerEl(scope)?.focus({ preventScroll: true });
        },
        "aria-labelledby": getLabelId(scope)
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
    getContentProps() {
      return normalize.element({
        hidden: !open,
        dir: prop("dir"),
        id: getContentId(scope),
        role: composite ? "listbox" : "dialog",
        ...parts.content.attrs,
        "data-state": open ? "open" : "closed",
        "data-placement": currentPlacement,
        "data-activedescendant": ariaActiveDescendant,
        "aria-activedescendant": composite ? ariaActiveDescendant : void 0,
        "aria-multiselectable": prop("multiple") && composite ? true : void 0,
        "aria-labelledby": getLabelId(scope),
        tabIndex: 0,
        onKeyDown(event) {
          if (!interactive) return;
          if (!domQuery.isSelfTarget(event)) return;
          if (event.key === "Tab") {
            const valid = domQuery.isValidTabEvent(event);
            if (!valid) {
              event.preventDefault();
              return;
            }
          }
          const keyMap = {
            ArrowUp() {
              send({ type: "CONTENT.ARROW_UP" });
            },
            ArrowDown() {
              send({ type: "CONTENT.ARROW_DOWN" });
            },
            Home() {
              send({ type: "CONTENT.HOME" });
            },
            End() {
              send({ type: "CONTENT.END" });
            },
            Enter() {
              send({ type: "ITEM.CLICK", src: "keydown.enter" });
            },
            Space(event2) {
              if (isTypingAhead) {
                send({ type: "CONTENT.TYPEAHEAD", key: event2.key });
              } else {
                keyMap.Enter?.(event2);
              }
            }
          };
          const exec = keyMap[domQuery.getEventKey(event)];
          if (exec) {
            exec(event);
            event.preventDefault();
            return;
          }
          const target = domQuery.getEventTarget(event);
          if (domQuery.isEditableElement(target)) {
            return;
          }
          if (domQuery.getByTypeahead.isValidEvent(event)) {
            send({ type: "CONTENT.TYPEAHEAD", key: event.key });
            event.preventDefault();
          }
        }
      });
    },
    getListProps() {
      return normalize.element({
        ...parts.list.attrs,
        tabIndex: 0,
        role: !composite ? "listbox" : void 0,
        "aria-labelledby": getTriggerId(scope),
        "aria-activedescendant": !composite ? ariaActiveDescendant : void 0,
        "aria-multiselectable": !composite && prop("multiple") ? true : void 0
      });
    }
  };
}
var { and, not, or } = core.createGuards();
var machine = core.createMachine({
  props({ props: props2 }) {
    return {
      loopFocus: false,
      closeOnSelect: !props2.multiple,
      composite: true,
      defaultValue: [],
      ...props2,
      collection: props2.collection ?? collection.empty(),
      positioning: {
        placement: "bottom-start",
        gutter: 8,
        ...props2.positioning
      }
    };
  },
  context({ prop, bindable }) {
    return {
      value: bindable(() => ({
        defaultValue: prop("defaultValue"),
        value: prop("value"),
        isEqual: utils.isEqual,
        onChange(value) {
          const items = prop("collection").findMany(value);
          return prop("onValueChange")?.({ value, items });
        }
      })),
      highlightedValue: bindable(() => ({
        defaultValue: prop("defaultHighlightedValue") || null,
        value: prop("highlightedValue"),
        onChange(value) {
          prop("onHighlightChange")?.({
            highlightedValue: value,
            highlightedItem: prop("collection").find(value),
            highlightedIndex: prop("collection").indexOf(value)
          });
        }
      })),
      currentPlacement: bindable(() => ({
        defaultValue: void 0
      })),
      fieldsetDisabled: bindable(() => ({
        defaultValue: false
      })),
      highlightedItem: bindable(() => ({
        defaultValue: null
      })),
      selectedItems: bindable(() => {
        const value = prop("value") ?? prop("defaultValue") ?? [];
        const items = prop("collection").findMany(value);
        return { defaultValue: items };
      }),
      valueAsString: bindable(() => {
        const value = prop("value") ?? prop("defaultValue") ?? [];
        return { defaultValue: prop("collection").stringifyMany(value) };
      })
    };
  },
  refs() {
    return {
      typeahead: { ...domQuery.getByTypeahead.defaultOptions }
    };
  },
  computed: {
    hasSelectedItems: ({ context }) => context.get("value").length > 0,
    isTypingAhead: ({ refs }) => refs.get("typeahead").keysSoFar !== "",
    isDisabled: ({ prop, context }) => !!prop("disabled") || !!context.get("fieldsetDisabled"),
    isInteractive: ({ prop }) => !(prop("disabled") || prop("readOnly"))
  },
  initialState({ prop }) {
    const open = prop("open") || prop("defaultOpen");
    return open ? "open" : "idle";
  },
  entry: ["syncSelectElement"],
  watch({ context, prop, track, action }) {
    track([() => context.get("value").toString()], () => {
      action(["syncSelectedItems", "syncSelectElement", "dispatchChangeEvent"]);
    });
    track([() => prop("open")], () => {
      action(["toggleVisibility"]);
    });
    track([() => context.get("highlightedValue")], () => {
      action(["syncHighlightedItem"]);
    });
    track([() => prop("collection").toString()], () => {
      action(["syncCollection"]);
    });
  },
  on: {
    "HIGHLIGHTED_VALUE.SET": {
      actions: ["setHighlightedItem"]
    },
    "ITEM.SELECT": {
      actions: ["selectItem"]
    },
    "ITEM.CLEAR": {
      actions: ["clearItem"]
    },
    "VALUE.SET": {
      actions: ["setSelectedItems"]
    },
    "VALUE.CLEAR": {
      actions: ["clearSelectedItems"]
    },
    "CLEAR.CLICK": {
      actions: ["clearSelectedItems", "focusTriggerEl"]
    }
  },
  effects: ["trackFormControlState"],
  states: {
    idle: {
      tags: ["closed"],
      on: {
        "CONTROLLED.OPEN": [
          {
            guard: "isTriggerClickEvent",
            target: "open",
            actions: ["setInitialFocus", "highlightFirstSelectedItem"]
          },
          {
            target: "open",
            actions: ["setInitialFocus"]
          }
        ],
        "TRIGGER.CLICK": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["invokeOnOpen", "setInitialFocus", "highlightFirstSelectedItem"]
          }
        ],
        "TRIGGER.FOCUS": {
          target: "focused"
        },
        OPEN: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitialFocus", "invokeOnOpen"]
          }
        ]
      }
    },
    focused: {
      tags: ["closed"],
      on: {
        "CONTROLLED.OPEN": [
          {
            guard: "isTriggerClickEvent",
            target: "open",
            actions: ["setInitialFocus", "highlightFirstSelectedItem"]
          },
          {
            guard: "isTriggerArrowUpEvent",
            target: "open",
            actions: ["setInitialFocus", "highlightComputedLastItem"]
          },
          {
            guard: or("isTriggerArrowDownEvent", "isTriggerEnterEvent"),
            target: "open",
            actions: ["setInitialFocus", "highlightComputedFirstItem"]
          },
          {
            target: "open",
            actions: ["setInitialFocus"]
          }
        ],
        OPEN: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitialFocus", "invokeOnOpen"]
          }
        ],
        "TRIGGER.BLUR": {
          target: "idle"
        },
        "TRIGGER.CLICK": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitialFocus", "invokeOnOpen", "highlightFirstSelectedItem"]
          }
        ],
        "TRIGGER.ENTER": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitialFocus", "invokeOnOpen", "highlightComputedFirstItem"]
          }
        ],
        "TRIGGER.ARROW_UP": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitialFocus", "invokeOnOpen", "highlightComputedLastItem"]
          }
        ],
        "TRIGGER.ARROW_DOWN": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnOpen"]
          },
          {
            target: "open",
            actions: ["setInitialFocus", "invokeOnOpen", "highlightComputedFirstItem"]
          }
        ],
        "TRIGGER.ARROW_LEFT": [
          {
            guard: and(not("multiple"), "hasSelectedItems"),
            actions: ["selectPreviousItem"]
          },
          {
            guard: not("multiple"),
            actions: ["selectLastItem"]
          }
        ],
        "TRIGGER.ARROW_RIGHT": [
          {
            guard: and(not("multiple"), "hasSelectedItems"),
            actions: ["selectNextItem"]
          },
          {
            guard: not("multiple"),
            actions: ["selectFirstItem"]
          }
        ],
        "TRIGGER.HOME": {
          guard: not("multiple"),
          actions: ["selectFirstItem"]
        },
        "TRIGGER.END": {
          guard: not("multiple"),
          actions: ["selectLastItem"]
        },
        "TRIGGER.TYPEAHEAD": {
          guard: not("multiple"),
          actions: ["selectMatchingItem"]
        }
      }
    },
    open: {
      tags: ["open"],
      exit: ["scrollContentToTop"],
      effects: ["trackDismissableElement", "computePlacement", "scrollToHighlightedItem"],
      on: {
        "CONTROLLED.CLOSE": {
          target: "focused",
          actions: ["focusTriggerEl", "clearHighlightedItem"]
        },
        CLOSE: [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "focused",
            actions: ["invokeOnClose", "focusTriggerEl", "clearHighlightedItem"]
          }
        ],
        "TRIGGER.CLICK": [
          {
            guard: "isOpenControlled",
            actions: ["invokeOnClose"]
          },
          {
            target: "focused",
            actions: ["invokeOnClose", "clearHighlightedItem"]
          }
        ],
        "ITEM.CLICK": [
          {
            guard: and("closeOnSelect", "isOpenControlled"),
            actions: ["selectHighlightedItem", "invokeOnClose"]
          },
          {
            guard: "closeOnSelect",
            target: "focused",
            actions: ["selectHighlightedItem", "invokeOnClose", "focusTriggerEl", "clearHighlightedItem"]
          },
          {
            actions: ["selectHighlightedItem"]
          }
        ],
        "CONTENT.HOME": {
          actions: ["highlightFirstItem"]
        },
        "CONTENT.END": {
          actions: ["highlightLastItem"]
        },
        "CONTENT.ARROW_DOWN": [
          {
            guard: and("hasHighlightedItem", "loop", "isLastItemHighlighted"),
            actions: ["highlightFirstItem"]
          },
          {
            guard: "hasHighlightedItem",
            actions: ["highlightNextItem"]
          },
          {
            actions: ["highlightFirstItem"]
          }
        ],
        "CONTENT.ARROW_UP": [
          {
            guard: and("hasHighlightedItem", "loop", "isFirstItemHighlighted"),
            actions: ["highlightLastItem"]
          },
          {
            guard: "hasHighlightedItem",
            actions: ["highlightPreviousItem"]
          },
          {
            actions: ["highlightLastItem"]
          }
        ],
        "CONTENT.TYPEAHEAD": {
          actions: ["highlightMatchingItem"]
        },
        "ITEM.POINTER_MOVE": {
          actions: ["highlightItem"]
        },
        "ITEM.POINTER_LEAVE": {
          actions: ["clearHighlightedItem"]
        },
        "POSITIONING.SET": {
          actions: ["reposition"]
        }
      }
    }
  },
  implementations: {
    guards: {
      loop: ({ prop }) => !!prop("loopFocus"),
      multiple: ({ prop }) => !!prop("multiple"),
      hasSelectedItems: ({ computed }) => !!computed("hasSelectedItems"),
      hasHighlightedItem: ({ context }) => context.get("highlightedValue") != null,
      isFirstItemHighlighted: ({ context, prop }) => context.get("highlightedValue") === prop("collection").firstValue,
      isLastItemHighlighted: ({ context, prop }) => context.get("highlightedValue") === prop("collection").lastValue,
      closeOnSelect: ({ prop, event }) => !!(event.closeOnSelect ?? prop("closeOnSelect")),
      // guard assertions (for controlled mode)
      isOpenControlled: ({ prop }) => prop("open") !== void 0,
      isTriggerClickEvent: ({ event }) => event.previousEvent?.type === "TRIGGER.CLICK",
      isTriggerEnterEvent: ({ event }) => event.previousEvent?.type === "TRIGGER.ENTER",
      isTriggerArrowUpEvent: ({ event }) => event.previousEvent?.type === "TRIGGER.ARROW_UP",
      isTriggerArrowDownEvent: ({ event }) => event.previousEvent?.type === "TRIGGER.ARROW_DOWN"
    },
    effects: {
      trackFormControlState({ context, scope }) {
        return domQuery.trackFormControl(getHiddenSelectEl(scope), {
          onFieldsetDisabledChange(disabled) {
            context.set("fieldsetDisabled", disabled);
          },
          onFormReset() {
            const value = context.initial("value");
            context.set("value", value);
          }
        });
      },
      trackDismissableElement({ scope, send, prop }) {
        const contentEl = () => getContentEl(scope);
        let restoreFocus = true;
        return dismissable.trackDismissableElement(contentEl, {
          defer: true,
          exclude: [getTriggerEl(scope), getClearTriggerEl(scope)],
          onFocusOutside: prop("onFocusOutside"),
          onPointerDownOutside: prop("onPointerDownOutside"),
          onInteractOutside(event) {
            prop("onInteractOutside")?.(event);
            restoreFocus = !(event.detail.focusable || event.detail.contextmenu);
          },
          onDismiss() {
            send({ type: "CLOSE", src: "interact-outside", restoreFocus });
          }
        });
      },
      computePlacement({ context, prop, scope }) {
        const positioning = prop("positioning");
        context.set("currentPlacement", positioning.placement);
        const triggerEl = () => getTriggerEl(scope);
        const positionerEl = () => getPositionerEl(scope);
        return popper.getPlacement(triggerEl, positionerEl, {
          defer: true,
          ...positioning,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      scrollToHighlightedItem({ context, prop, scope, event }) {
        const exec = (immediate) => {
          const highlightedValue = context.get("highlightedValue");
          if (highlightedValue == null) return;
          if (event.current().type.includes("POINTER")) return;
          const optionEl = getItemEl(scope, highlightedValue);
          const contentEl2 = getContentEl(scope);
          const scrollToIndexFn = prop("scrollToIndexFn");
          if (scrollToIndexFn) {
            const highlightedIndex = prop("collection").indexOf(highlightedValue);
            scrollToIndexFn?.({ index: highlightedIndex, immediate });
            return;
          }
          domQuery.scrollIntoView(optionEl, { rootEl: contentEl2, block: "nearest" });
        };
        domQuery.raf(() => exec(true));
        const contentEl = () => getContentEl(scope);
        return domQuery.observeAttributes(contentEl, {
          defer: true,
          attributes: ["data-activedescendant"],
          callback() {
            exec(false);
          }
        });
      }
    },
    actions: {
      reposition({ context, prop, scope, event }) {
        const positionerEl = () => getPositionerEl(scope);
        popper.getPlacement(getTriggerEl(scope), positionerEl, {
          ...prop("positioning"),
          ...event.options,
          defer: true,
          listeners: false,
          onComplete(data) {
            context.set("currentPlacement", data.placement);
          }
        });
      },
      toggleVisibility({ send, prop, event }) {
        send({ type: prop("open") ? "CONTROLLED.OPEN" : "CONTROLLED.CLOSE", previousEvent: event });
      },
      highlightPreviousItem({ context, prop }) {
        const highlightedValue = context.get("highlightedValue");
        if (highlightedValue == null) return;
        const value = prop("collection").getPreviousValue(highlightedValue, 1, prop("loopFocus"));
        context.set("highlightedValue", value);
      },
      highlightNextItem({ context, prop }) {
        const highlightedValue = context.get("highlightedValue");
        if (highlightedValue == null) return;
        const value = prop("collection").getNextValue(highlightedValue, 1, prop("loopFocus"));
        context.set("highlightedValue", value);
      },
      highlightFirstItem({ context, prop }) {
        const value = prop("collection").firstValue;
        context.set("highlightedValue", value);
      },
      highlightLastItem({ context, prop }) {
        const value = prop("collection").lastValue;
        context.set("highlightedValue", value);
      },
      setInitialFocus({ scope }) {
        domQuery.raf(() => {
          const element = domQuery.getInitialFocus({
            root: getContentEl(scope)
          });
          element?.focus({ preventScroll: true });
        });
      },
      focusTriggerEl({ event, scope }) {
        const restoreFocus = event.restoreFocus ?? event.previousEvent?.restoreFocus;
        if (restoreFocus != null && !restoreFocus) return;
        domQuery.raf(() => {
          const element = getTriggerEl(scope);
          element?.focus({ preventScroll: true });
        });
      },
      selectHighlightedItem({ context, prop, event }) {
        let value = event.value ?? context.get("highlightedValue");
        if (value == null) return;
        const nullable = prop("deselectable") && !prop("multiple") && context.get("value").includes(value);
        value = nullable ? null : value;
        context.set("value", (prev) => {
          if (value == null) return [];
          if (prop("multiple")) return utils.addOrRemove(prev, value);
          return [value];
        });
      },
      highlightComputedFirstItem({ context, prop, computed }) {
        const collection2 = prop("collection");
        const value = computed("hasSelectedItems") ? collection2.sort(context.get("value"))[0] : collection2.firstValue;
        context.set("highlightedValue", value);
      },
      highlightComputedLastItem({ context, prop, computed }) {
        const collection2 = prop("collection");
        const value = computed("hasSelectedItems") ? collection2.sort(context.get("value"))[0] : collection2.lastValue;
        context.set("highlightedValue", value);
      },
      highlightFirstSelectedItem({ context, prop, computed }) {
        if (!computed("hasSelectedItems")) return;
        const value = prop("collection").sort(context.get("value"))[0];
        context.set("highlightedValue", value);
      },
      highlightItem({ context, event }) {
        context.set("highlightedValue", event.value);
      },
      highlightMatchingItem({ context, prop, event, refs }) {
        const value = prop("collection").search(event.key, {
          state: refs.get("typeahead"),
          currentValue: context.get("highlightedValue")
        });
        if (value == null) return;
        context.set("highlightedValue", value);
      },
      setHighlightedItem({ context, event }) {
        context.set("highlightedValue", event.value);
      },
      clearHighlightedItem({ context }) {
        context.set("highlightedValue", null);
      },
      selectItem({ context, prop, event }) {
        const nullable = prop("deselectable") && !prop("multiple") && context.get("value").includes(event.value);
        const value = nullable ? null : event.value;
        context.set("value", (prev) => {
          if (value == null) return [];
          if (prop("multiple")) return utils.addOrRemove(prev, value);
          return [value];
        });
      },
      clearItem({ context, event }) {
        context.set("value", (prev) => prev.filter((v) => v !== event.value));
      },
      setSelectedItems({ context, event }) {
        context.set("value", event.value);
      },
      clearSelectedItems({ context }) {
        context.set("value", []);
      },
      selectPreviousItem({ context, prop }) {
        const [firstItem] = context.get("value");
        const value = prop("collection").getPreviousValue(firstItem);
        if (value) context.set("value", [value]);
      },
      selectNextItem({ context, prop }) {
        const [firstItem] = context.get("value");
        const value = prop("collection").getNextValue(firstItem);
        if (value) context.set("value", [value]);
      },
      selectFirstItem({ context, prop }) {
        const value = prop("collection").firstValue;
        if (value) context.set("value", [value]);
      },
      selectLastItem({ context, prop }) {
        const value = prop("collection").lastValue;
        if (value) context.set("value", [value]);
      },
      selectMatchingItem({ context, prop, event, refs }) {
        const value = prop("collection").search(event.key, {
          state: refs.get("typeahead"),
          currentValue: context.get("value")[0]
        });
        if (value == null) return;
        context.set("value", [value]);
      },
      scrollContentToTop({ prop, scope }) {
        if (prop("scrollToIndexFn")) {
          prop("scrollToIndexFn")?.({ index: 0, immediate: true });
        } else {
          getContentEl(scope)?.scrollTo(0, 0);
        }
      },
      invokeOnOpen({ prop }) {
        prop("onOpenChange")?.({ open: true });
      },
      invokeOnClose({ prop }) {
        prop("onOpenChange")?.({ open: false });
      },
      syncSelectElement({ context, prop, scope }) {
        const selectEl = getHiddenSelectEl(scope);
        if (!selectEl) return;
        if (context.get("value").length === 0 && !prop("multiple")) {
          selectEl.selectedIndex = -1;
          return;
        }
        for (const option of selectEl.options) {
          option.selected = context.get("value").includes(option.value);
        }
      },
      syncCollection({ context, prop }) {
        const collection2 = prop("collection");
        const highlightedItem = collection2.find(context.get("highlightedValue"));
        if (highlightedItem) context.set("highlightedItem", highlightedItem);
        const selectedItems = collection2.findMany(context.get("value"));
        context.set("selectedItems", selectedItems);
        const valueAsString = collection2.stringifyItems(selectedItems);
        context.set("valueAsString", valueAsString);
      },
      syncSelectedItems({ context, prop }) {
        const collection2 = prop("collection");
        const prevSelectedItems = context.get("selectedItems");
        const value = context.get("value");
        const selectedItems = value.map((value2) => {
          const item = prevSelectedItems.find((item2) => collection2.getItemValue(item2) === value2);
          return item || collection2.find(value2);
        });
        context.set("selectedItems", selectedItems);
        context.set("valueAsString", collection2.stringifyItems(selectedItems));
      },
      syncHighlightedItem({ context, prop }) {
        const collection2 = prop("collection");
        const highlightedValue = context.get("highlightedValue");
        const highlightedItem = highlightedValue ? collection2.find(highlightedValue) : null;
        context.set("highlightedItem", highlightedItem);
      },
      dispatchChangeEvent({ scope }) {
        queueMicrotask(() => {
          const node = getHiddenSelectEl(scope);
          if (!node) return;
          const win = scope.getWin();
          const changeEvent = new win.Event("change", { bubbles: true, composed: true });
          node.dispatchEvent(changeEvent);
        });
      }
    }
  }
});
var props = types.createProps()([
  "closeOnSelect",
  "collection",
  "dir",
  "disabled",
  "deselectable",
  "form",
  "getRootNode",
  "highlightedValue",
  "id",
  "ids",
  "invalid",
  "loopFocus",
  "multiple",
  "name",
  "onFocusOutside",
  "onHighlightChange",
  "onInteractOutside",
  "onOpenChange",
  "onPointerDownOutside",
  "onValueChange",
  "defaultOpen",
  "open",
  "composite",
  "positioning",
  "required",
  "readOnly",
  "scrollToIndexFn",
  "value",
  "defaultValue",
  "defaultHighlightedValue"
]);
var splitProps = utils.createSplitProps(props);
var itemProps = types.createProps()(["item", "persistFocus"]);
var splitItemProps = utils.createSplitProps(itemProps);
var itemGroupProps = types.createProps()(["id"]);
var splitItemGroupProps = utils.createSplitProps(itemGroupProps);
var itemGroupLabelProps = types.createProps()(["htmlFor"]);
var splitItemGroupLabelProps = utils.createSplitProps(itemGroupLabelProps);

exports.anatomy = anatomy;
exports.collection = collection;
exports.connect = connect;
exports.itemGroupLabelProps = itemGroupLabelProps;
exports.itemGroupProps = itemGroupProps;
exports.itemProps = itemProps;
exports.machine = machine;
exports.props = props;
exports.splitItemGroupLabelProps = splitItemGroupLabelProps;
exports.splitItemGroupProps = splitItemGroupProps;
exports.splitItemProps = splitItemProps;
exports.splitProps = splitProps;
