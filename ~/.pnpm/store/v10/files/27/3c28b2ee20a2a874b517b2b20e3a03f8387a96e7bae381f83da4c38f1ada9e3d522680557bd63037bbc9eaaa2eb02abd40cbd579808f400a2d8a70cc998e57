'use strict';

var anatomy$1 = require('@zag-js/anatomy');
var domQuery = require('@zag-js/dom-query');
var autoResize = require('@zag-js/auto-resize');
var core = require('@zag-js/core');
var interactOutside = require('@zag-js/interact-outside');
var liveRegion = require('@zag-js/live-region');
var utils = require('@zag-js/utils');
var types = require('@zag-js/types');

// src/tags-input.anatomy.ts
var anatomy = anatomy$1.createAnatomy("tagsInput").parts(
  "root",
  "label",
  "control",
  "input",
  "clearTrigger",
  "item",
  "itemPreview",
  "itemInput",
  "itemText",
  "itemDeleteTrigger"
);
var parts = anatomy.build();
var getRootId = (ctx) => ctx.ids?.root ?? `tags-input:${ctx.id}`;
var getInputId = (ctx) => ctx.ids?.input ?? `tags-input:${ctx.id}:input`;
var getClearTriggerId = (ctx) => ctx.ids?.clearBtn ?? `tags-input:${ctx.id}:clear-btn`;
var getHiddenInputId = (ctx) => ctx.ids?.hiddenInput ?? `tags-input:${ctx.id}:hidden-input`;
var getLabelId = (ctx) => ctx.ids?.label ?? `tags-input:${ctx.id}:label`;
var getControlId = (ctx) => ctx.ids?.control ?? `tags-input:${ctx.id}:control`;
var getItemId = (ctx, opt) => ctx.ids?.item?.(opt) ?? `tags-input:${ctx.id}:tag:${opt.value}:${opt.index}`;
var getItemDeleteTriggerId = (ctx, opt) => ctx.ids?.itemDeleteTrigger?.(opt) ?? `${getItemId(ctx, opt)}:delete-btn`;
var getItemInputId = (ctx, opt) => ctx.ids?.itemInput?.(opt) ?? `${getItemId(ctx, opt)}:input`;
var getEditInputId = (id) => `${id}:input`;
var getEditInputEl = (ctx, id) => ctx.getById(getEditInputId(id));
var getTagInputEl = (ctx, opt) => ctx.getById(getItemInputId(ctx, opt));
var getRootEl = (ctx) => ctx.getById(getRootId(ctx));
var getInputEl = (ctx) => ctx.getById(getInputId(ctx));
var getHiddenInputEl = (ctx) => ctx.getById(getHiddenInputId(ctx));
var getTagElements = (ctx) => domQuery.queryAll(getRootEl(ctx), `[data-part=item-preview]:not([data-disabled])`);
var getFirstEl = (ctx) => getTagElements(ctx)[0];
var getLastEl = (ctx) => getTagElements(ctx)[getTagElements(ctx).length - 1];
var getPrevEl = (ctx, id) => domQuery.prevById(getTagElements(ctx), id, false);
var getNextEl = (ctx, id) => domQuery.nextById(getTagElements(ctx), id, false);
var getTagElAtIndex = (ctx, index) => getTagElements(ctx)[index];
var getIndexOfId = (ctx, id) => domQuery.indexOfId(getTagElements(ctx), id);
var setHoverIntent = (el) => {
  const tagEl = el.closest("[data-part=item-preview]");
  if (!tagEl) return;
  tagEl.dataset.deleteIntent = "";
};
var clearHoverIntent = (el) => {
  const tagEl = el.closest("[data-part=item-preview]");
  if (!tagEl) return;
  delete tagEl.dataset.deleteIntent;
};
var dispatchInputEvent = (ctx, value) => {
  const inputEl = getHiddenInputEl(ctx);
  if (!inputEl) return;
  domQuery.dispatchInputValueEvent(inputEl, { value });
};

// src/tags-input.connect.ts
function connect(service, normalize) {
  const { state, send, computed, prop, scope, context } = service;
  const interactive = computed("isInteractive");
  const disabled = prop("disabled");
  const readOnly = prop("readOnly");
  const invalid = prop("invalid") || computed("isOverflowing");
  const translations = prop("translations");
  const focused = state.hasTag("focused");
  const editingTag = state.matches("editing:tag");
  const empty = computed("count") === 0;
  function getItemState(options) {
    const id = getItemId(scope, options);
    const editedTagId = context.get("editedTagId");
    const highlightedTagId = context.get("highlightedTagId");
    return {
      id,
      editing: editingTag && editedTagId === id,
      highlighted: id === highlightedTagId,
      disabled: Boolean(options.disabled || disabled)
    };
  }
  return {
    empty,
    inputValue: computed("trimmedInputValue"),
    value: context.get("value"),
    valueAsString: computed("valueAsString"),
    count: computed("count"),
    atMax: computed("isAtMax"),
    setValue(value) {
      send({ type: "SET_VALUE", value });
    },
    clearValue(id) {
      if (id) {
        send({ type: "CLEAR_TAG", id });
      } else {
        send({ type: "CLEAR_VALUE" });
      }
    },
    addValue(value) {
      send({ type: "ADD_TAG", value });
    },
    setValueAtIndex(index, value) {
      send({ type: "SET_VALUE_AT_INDEX", index, value });
    },
    setInputValue(value) {
      send({ type: "SET_INPUT_VALUE", value });
    },
    clearInputValue() {
      send({ type: "SET_INPUT_VALUE", value: "" });
    },
    focus() {
      getInputEl(scope)?.focus();
    },
    getItemState,
    getRootProps() {
      return normalize.element({
        dir: prop("dir"),
        ...parts.root.attrs,
        "data-invalid": domQuery.dataAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly),
        "data-disabled": domQuery.dataAttr(disabled),
        "data-focus": domQuery.dataAttr(focused),
        "data-empty": domQuery.dataAttr(empty),
        id: getRootId(scope),
        onPointerDown() {
          if (!interactive) return;
          send({ type: "POINTER_DOWN" });
        }
      });
    },
    getLabelProps() {
      return normalize.label({
        ...parts.label.attrs,
        "data-disabled": domQuery.dataAttr(disabled),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly),
        id: getLabelId(scope),
        dir: prop("dir"),
        htmlFor: getInputId(scope)
      });
    },
    getControlProps() {
      return normalize.element({
        id: getControlId(scope),
        ...parts.control.attrs,
        dir: prop("dir"),
        tabIndex: readOnly ? 0 : void 0,
        "data-disabled": domQuery.dataAttr(disabled),
        "data-readonly": domQuery.dataAttr(readOnly),
        "data-invalid": domQuery.dataAttr(invalid),
        "data-focus": domQuery.dataAttr(focused)
      });
    },
    getInputProps() {
      return normalize.input({
        ...parts.input.attrs,
        dir: prop("dir"),
        "data-invalid": domQuery.dataAttr(invalid),
        "aria-invalid": domQuery.ariaAttr(invalid),
        "data-readonly": domQuery.dataAttr(readOnly),
        maxLength: prop("maxLength"),
        id: getInputId(scope),
        defaultValue: context.get("inputValue"),
        autoComplete: "off",
        autoCorrect: "off",
        autoCapitalize: "none",
        disabled: disabled || readOnly,
        onInput(event) {
          const evt = domQuery.getNativeEvent(event);
          const value = event.currentTarget.value;
          if (evt.inputType === "insertFromPaste") {
            send({ type: "PASTE", value });
            return;
          }
          if (endsWith(value, prop("delimiter"))) {
            send({ type: "DELIMITER_KEY" });
            return;
          }
          send({ type: "TYPE", value, key: evt.inputType });
        },
        onFocus() {
          queueMicrotask(() => {
            send({ type: "FOCUS" });
          });
        },
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          if (domQuery.isComposingEvent(event)) return;
          const target = event.currentTarget;
          const isCombobox = target.getAttribute("role") === "combobox";
          const isExpanded = target.ariaExpanded === "true";
          const keyMap = {
            ArrowDown() {
              send({ type: "ARROW_DOWN" });
            },
            ArrowLeft() {
              if (isCombobox && isExpanded) return;
              send({ type: "ARROW_LEFT" });
            },
            ArrowRight(event2) {
              if (context.get("highlightedTagId")) {
                event2.preventDefault();
              }
              if (isCombobox && isExpanded) return;
              send({ type: "ARROW_RIGHT" });
            },
            Escape(event2) {
              event2.preventDefault();
              send({ type: "ESCAPE" });
            },
            Backspace() {
              send({ type: "BACKSPACE" });
            },
            Delete() {
              send({ type: "DELETE" });
            },
            Enter(event2) {
              if (isCombobox && isExpanded) return;
              send({ type: "ENTER" });
              event2.preventDefault();
            }
          };
          const key = domQuery.getEventKey(event, { dir: prop("dir") });
          const exec = keyMap[key];
          if (exec) {
            exec(event);
            return;
          }
        }
      });
    },
    getHiddenInputProps() {
      return normalize.input({
        type: "text",
        hidden: true,
        name: prop("name"),
        form: prop("form"),
        disabled,
        readOnly,
        required: prop("required"),
        id: getHiddenInputId(scope),
        defaultValue: computed("valueAsString")
      });
    },
    getItemProps(props2) {
      return normalize.element({
        ...parts.item.attrs,
        dir: prop("dir"),
        "data-value": props2.value,
        "data-disabled": domQuery.dataAttr(disabled)
      });
    },
    getItemPreviewProps(props2) {
      const itemState = getItemState(props2);
      return normalize.element({
        ...parts.itemPreview.attrs,
        id: itemState.id,
        dir: prop("dir"),
        hidden: itemState.editing,
        "data-value": props2.value,
        "data-disabled": domQuery.dataAttr(disabled),
        "data-highlighted": domQuery.dataAttr(itemState.highlighted),
        onPointerDown(event) {
          if (!interactive || itemState.disabled) return;
          event.preventDefault();
          send({ type: "POINTER_DOWN_TAG", id: itemState.id });
        },
        onDoubleClick() {
          if (!interactive || itemState.disabled) return;
          send({ type: "DOUBLE_CLICK_TAG", id: itemState.id });
        }
      });
    },
    getItemTextProps(props2) {
      const itemState = getItemState(props2);
      return normalize.element({
        ...parts.itemText.attrs,
        dir: prop("dir"),
        "data-disabled": domQuery.dataAttr(disabled),
        "data-highlighted": domQuery.dataAttr(itemState.highlighted)
      });
    },
    getItemInputProps(props2) {
      const itemState = getItemState(props2);
      return normalize.input({
        ...parts.itemInput.attrs,
        dir: prop("dir"),
        "aria-label": translations?.tagEdited?.(props2.value),
        disabled,
        id: getItemInputId(scope, props2),
        tabIndex: -1,
        hidden: !itemState.editing,
        defaultValue: itemState.editing ? context.get("editedTagValue") : "",
        onInput(event) {
          send({ type: "TAG_INPUT_TYPE", value: event.currentTarget.value });
        },
        onBlur(event) {
          queueMicrotask(() => {
            send({ type: "TAG_INPUT_BLUR", target: event.relatedTarget, id: itemState.id });
          });
        },
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          if (domQuery.isComposingEvent(event)) return;
          const keyMap = {
            Enter() {
              send({ type: "TAG_INPUT_ENTER" });
            },
            Escape() {
              send({ type: "TAG_INPUT_ESCAPE" });
            }
          };
          const exec = keyMap[event.key];
          if (exec) {
            event.preventDefault();
            exec(event);
          }
        }
      });
    },
    getItemDeleteTriggerProps(props2) {
      const id = getItemId(scope, props2);
      return normalize.button({
        ...parts.itemDeleteTrigger.attrs,
        dir: prop("dir"),
        id: getItemDeleteTriggerId(scope, props2),
        type: "button",
        disabled,
        "aria-label": translations?.deleteTagTriggerLabel?.(props2.value),
        tabIndex: -1,
        onPointerDown(event) {
          if (!interactive) {
            event.preventDefault();
          }
        },
        onPointerMove(event) {
          if (!interactive) return;
          setHoverIntent(event.currentTarget);
        },
        onPointerLeave(event) {
          if (!interactive) return;
          clearHoverIntent(event.currentTarget);
        },
        onClick() {
          if (!interactive) return;
          send({ type: "CLICK_DELETE_TAG", id });
        }
      });
    },
    getClearTriggerProps() {
      return normalize.button({
        ...parts.clearTrigger.attrs,
        dir: prop("dir"),
        id: getClearTriggerId(scope),
        type: "button",
        "data-readonly": domQuery.dataAttr(readOnly),
        disabled,
        "aria-label": translations?.clearTriggerLabel,
        hidden: empty,
        onClick() {
          if (!interactive) return;
          send({ type: "CLEAR_VALUE" });
        }
      });
    }
  };
}
function endsWith(str, del) {
  if (!del) return false;
  if (typeof del === "string") return str.endsWith(del);
  return new RegExp(`${del.source}$`).test(str);
}
var { and, not, or } = core.createGuards();
var machine = core.createMachine({
  props({ props: props2 }) {
    return {
      dir: "ltr",
      addOnPaste: false,
      editable: true,
      validate: () => true,
      delimiter: ",",
      defaultValue: [],
      defaultInputValue: "",
      max: Infinity,
      ...props2,
      translations: {
        clearTriggerLabel: "Clear all tags",
        deleteTagTriggerLabel: (value) => `Delete tag ${value}`,
        tagAdded: (value) => `Added tag ${value}`,
        tagsPasted: (values) => `Pasted ${values.length} tags`,
        tagEdited: (value) => `Editing tag ${value}. Press enter to save or escape to cancel.`,
        tagUpdated: (value) => `Tag update to ${value}`,
        tagDeleted: (value) => `Tag ${value} deleted`,
        tagSelected: (value) => `Tag ${value} selected. Press enter to edit, delete or backspace to remove.`,
        ...props2.translations
      }
    };
  },
  initialState({ prop }) {
    return prop("autoFocus") ? "focused:input" : "idle";
  },
  refs() {
    return {
      liveRegion: null,
      log: { current: null, prev: null }
    };
  },
  context({ bindable, prop }) {
    return {
      value: bindable(() => ({
        defaultValue: prop("defaultValue"),
        value: prop("value"),
        isEqual: utils.isEqual,
        hash(value) {
          return value.join(", ");
        },
        onChange(value) {
          prop("onValueChange")?.({ value });
        }
      })),
      inputValue: bindable(() => ({
        sync: true,
        defaultValue: prop("defaultInputValue"),
        value: prop("inputValue"),
        onChange(value) {
          prop("onInputValueChange")?.({ inputValue: value });
        }
      })),
      fieldsetDisabled: bindable(() => ({ defaultValue: false })),
      editedTagValue: bindable(() => ({ defaultValue: "" })),
      editedTagId: bindable(() => ({ defaultValue: null })),
      editedTagIndex: bindable(() => ({
        defaultValue: null,
        sync: true
      })),
      highlightedTagId: bindable(() => ({
        defaultValue: null,
        sync: true,
        onChange(value) {
          prop("onHighlightChange")?.({ highlightedValue: value });
        }
      }))
    };
  },
  computed: {
    count: ({ context }) => context.get("value").length,
    valueAsString: ({ context }) => context.hash("value"),
    trimmedInputValue: ({ context }) => context.get("inputValue").trim(),
    isDisabled: ({ prop }) => !!prop("disabled"),
    isInteractive: ({ prop }) => !(prop("readOnly") || !!prop("disabled")),
    isAtMax: ({ context, prop }) => context.get("value").length === prop("max"),
    isOverflowing: ({ context, prop }) => context.get("value").length > prop("max")
  },
  watch({ track, context, action, computed, refs }) {
    track([() => context.get("editedTagValue")], () => {
      action(["syncEditedTagInputValue"]);
    });
    track([() => context.get("inputValue")], () => {
      action(["syncInputValue"]);
    });
    track([() => context.get("highlightedTagId")], () => {
      action(["logHighlightedTag"]);
    });
    track([() => computed("isOverflowing")], () => {
      action(["invokeOnInvalid"]);
    });
    track([() => JSON.stringify(refs.get("log"))], () => {
      action(["announceLog"]);
    });
  },
  effects: ["trackLiveRegion", "trackFormControlState"],
  exit: ["clearLog"],
  on: {
    DOUBLE_CLICK_TAG: {
      // internal: true,
      guard: "isTagEditable",
      target: "editing:tag",
      actions: ["setEditedId"]
    },
    POINTER_DOWN_TAG: {
      // internal: true,
      target: "navigating:tag",
      actions: ["highlightTag", "focusInput"]
    },
    CLICK_DELETE_TAG: {
      target: "focused:input",
      actions: ["deleteTag"]
    },
    SET_INPUT_VALUE: {
      actions: ["setInputValue"]
    },
    SET_VALUE: {
      actions: ["setValue"]
    },
    CLEAR_TAG: {
      actions: ["deleteTag"]
    },
    SET_VALUE_AT_INDEX: {
      actions: ["setValueAtIndex"]
    },
    CLEAR_VALUE: {
      actions: ["clearTags", "clearInputValue", "focusInput"]
    },
    ADD_TAG: {
      actions: ["addTag"]
    },
    INSERT_TAG: {
      // (!isAtMax || allowOverflow) && !inputValueIsEmpty
      guard: and(or(not("isAtMax"), "allowOverflow"), not("isInputValueEmpty")),
      actions: ["addTag", "clearInputValue"]
    },
    EXTERNAL_BLUR: [
      { guard: "addOnBlur", actions: ["raiseInsertTagEvent"] },
      { guard: "clearOnBlur", actions: ["clearInputValue"] }
    ]
  },
  states: {
    idle: {
      on: {
        FOCUS: {
          target: "focused:input"
        },
        POINTER_DOWN: {
          guard: not("hasHighlightedTag"),
          target: "focused:input"
        }
      }
    },
    "focused:input": {
      tags: ["focused"],
      entry: ["focusInput", "clearHighlightedId"],
      effects: ["trackInteractOutside"],
      on: {
        TYPE: {
          actions: ["setInputValue"]
        },
        BLUR: [
          {
            guard: "addOnBlur",
            target: "idle",
            actions: ["raiseInsertTagEvent"]
          },
          {
            guard: "clearOnBlur",
            target: "idle",
            actions: ["clearInputValue"]
          },
          { target: "idle" }
        ],
        ENTER: {
          actions: ["raiseInsertTagEvent"]
        },
        DELIMITER_KEY: {
          actions: ["raiseInsertTagEvent"]
        },
        ARROW_LEFT: {
          guard: and("hasTags", "isCaretAtStart"),
          target: "navigating:tag",
          actions: ["highlightLastTag"]
        },
        BACKSPACE: {
          target: "navigating:tag",
          guard: and("hasTags", "isCaretAtStart"),
          actions: ["highlightLastTag"]
        },
        DELETE: {
          guard: "hasHighlightedTag",
          actions: ["deleteHighlightedTag", "highlightTagAtIndex"]
        },
        PASTE: [
          {
            guard: "addOnPaste",
            actions: ["setInputValue", "addTagFromPaste"]
          },
          {
            actions: ["setInputValue"]
          }
        ]
      }
    },
    "navigating:tag": {
      tags: ["focused"],
      effects: ["trackInteractOutside"],
      on: {
        ARROW_RIGHT: [
          {
            guard: and("hasTags", "isCaretAtStart", not("isLastTagHighlighted")),
            actions: ["highlightNextTag"]
          },
          { target: "focused:input" }
        ],
        ARROW_LEFT: [
          {
            guard: not("isCaretAtStart"),
            target: "focused:input"
          },
          {
            actions: ["highlightPrevTag"]
          }
        ],
        BLUR: {
          target: "idle",
          actions: ["clearHighlightedId"]
        },
        ENTER: {
          guard: and("isTagEditable", "hasHighlightedTag"),
          target: "editing:tag",
          actions: ["setEditedId", "focusEditedTagInput"]
        },
        ARROW_DOWN: {
          target: "focused:input"
        },
        ESCAPE: {
          target: "focused:input"
        },
        TYPE: {
          target: "focused:input",
          actions: ["setInputValue"]
        },
        BACKSPACE: [
          {
            guard: not("isCaretAtStart"),
            target: "focused:input"
          },
          {
            guard: "isFirstTagHighlighted",
            actions: ["deleteHighlightedTag", "highlightFirstTag"]
          },
          {
            guard: "hasHighlightedTag",
            actions: ["deleteHighlightedTag", "highlightPrevTag"]
          },
          {
            actions: ["highlightLastTag"]
          }
        ],
        DELETE: [
          {
            guard: not("isCaretAtStart"),
            target: "focused:input"
          },
          {
            target: "focused:input",
            actions: ["deleteHighlightedTag", "highlightTagAtIndex"]
          }
        ],
        PASTE: [
          {
            guard: "addOnPaste",
            target: "focused:input",
            actions: ["setInputValue", "addTagFromPaste"]
          },
          {
            target: "focused:input",
            actions: ["setInputValue"]
          }
        ]
      }
    },
    "editing:tag": {
      tags: ["editing", "focused"],
      entry: ["focusEditedTagInput"],
      effects: ["autoResize"],
      on: {
        TAG_INPUT_TYPE: {
          actions: ["setEditedTagValue"]
        },
        TAG_INPUT_ESCAPE: {
          target: "navigating:tag",
          actions: ["clearEditedTagValue", "focusInput", "clearEditedId", "highlightTagAtIndex"]
        },
        TAG_INPUT_BLUR: [
          {
            guard: "isInputRelatedTarget",
            target: "navigating:tag",
            actions: ["clearEditedTagValue", "clearHighlightedId", "clearEditedId"]
          },
          {
            target: "idle",
            actions: ["clearEditedTagValue", "clearHighlightedId", "clearEditedId", "raiseExternalBlurEvent"]
          }
        ],
        TAG_INPUT_ENTER: [
          {
            guard: "isEditedTagEmpty",
            target: "navigating:tag",
            actions: ["deleteHighlightedTag", "focusInput", "clearEditedId", "highlightTagAtIndex"]
          },
          {
            target: "navigating:tag",
            actions: ["submitEditedTagValue", "focusInput", "clearEditedId", "highlightTagAtIndex"]
          }
        ]
      }
    }
  },
  implementations: {
    guards: {
      isInputRelatedTarget: ({ scope, event }) => event.relatedTarget === getInputEl(scope),
      isAtMax: ({ computed }) => computed("isAtMax"),
      hasHighlightedTag: ({ context }) => context.get("highlightedTagId") != null,
      isFirstTagHighlighted: ({ context, scope }) => {
        const value = context.get("value");
        const firstItemId = getItemId(scope, { value: value[0], index: 0 });
        return firstItemId === context.get("highlightedTagId");
      },
      isEditedTagEmpty: ({ context }) => context.get("editedTagValue").trim() === "",
      isLastTagHighlighted: ({ context, scope }) => {
        const value = context.get("value");
        const lastIndex = value.length - 1;
        const lastItemId = getItemId(scope, { value: value[lastIndex], index: lastIndex });
        return lastItemId === context.get("highlightedTagId");
      },
      isInputValueEmpty: ({ context }) => context.get("inputValue").trim().length === 0,
      hasTags: ({ context }) => context.get("value").length > 0,
      allowOverflow: ({ prop }) => !!prop("allowOverflow"),
      autoFocus: ({ prop }) => !!prop("autoFocus"),
      addOnBlur: ({ prop }) => prop("blurBehavior") === "add",
      clearOnBlur: ({ prop }) => prop("blurBehavior") === "clear",
      addOnPaste: ({ prop }) => !!prop("addOnPaste"),
      isTagEditable: ({ prop }) => !!prop("editable"),
      isCaretAtStart: ({ scope }) => domQuery.isCaretAtStart(getInputEl(scope))
    },
    effects: {
      trackInteractOutside({ scope, prop, send }) {
        return interactOutside.trackInteractOutside(getInputEl(scope), {
          exclude(target) {
            return domQuery.contains(getRootEl(scope), target);
          },
          onFocusOutside: prop("onFocusOutside"),
          onPointerDownOutside: prop("onPointerDownOutside"),
          onInteractOutside(event) {
            prop("onInteractOutside")?.(event);
            if (event.defaultPrevented) return;
            send({ type: "BLUR", src: "interact-outside" });
          }
        });
      },
      trackFormControlState({ context, send, scope }) {
        return domQuery.trackFormControl(getHiddenInputEl(scope), {
          onFieldsetDisabledChange(disabled) {
            context.set("fieldsetDisabled", disabled);
          },
          onFormReset() {
            const value = context.initial("value");
            send({ type: "SET_VALUE", value, src: "form-reset" });
          }
        });
      },
      autoResize({ context, prop, scope }) {
        let fn_cleanup;
        const raf_cleanup = domQuery.raf(() => {
          const editedTagValue = context.get("editedTagValue");
          const editedTagIndex = context.get("editedTagIndex");
          if (!editedTagValue || editedTagIndex == null || !prop("editable")) return;
          const inputEl = getTagInputEl(scope, {
            value: editedTagValue,
            index: editedTagIndex
          });
          fn_cleanup = autoResize.autoResizeInput(inputEl);
        });
        return () => {
          raf_cleanup();
          fn_cleanup?.();
        };
      },
      trackLiveRegion({ scope, refs }) {
        const liveRegion$1 = liveRegion.createLiveRegion({
          level: "assertive",
          document: scope.getDoc()
        });
        refs.set("liveRegion", liveRegion$1);
        return () => liveRegion$1.destroy();
      }
    },
    actions: {
      raiseInsertTagEvent({ send }) {
        send({ type: "INSERT_TAG" });
      },
      raiseExternalBlurEvent({ send, event }) {
        send({ type: "EXTERNAL_BLUR", id: event.id });
      },
      dispatchChangeEvent({ scope, computed }) {
        dispatchInputEvent(scope, computed("valueAsString"));
      },
      highlightNextTag({ context, scope }) {
        const highlightedTagId = context.get("highlightedTagId");
        if (highlightedTagId == null) return;
        const next = getNextEl(scope, highlightedTagId);
        context.set("highlightedTagId", next?.id ?? null);
      },
      highlightFirstTag({ context, scope }) {
        domQuery.raf(() => {
          const first = getFirstEl(scope);
          context.set("highlightedTagId", first?.id ?? null);
        });
      },
      highlightLastTag({ context, scope }) {
        const last = getLastEl(scope);
        context.set("highlightedTagId", last?.id ?? null);
      },
      highlightPrevTag({ context, scope }) {
        const highlightedTagId = context.get("highlightedTagId");
        if (highlightedTagId == null) return;
        const prev = getPrevEl(scope, highlightedTagId);
        context.set("highlightedTagId", prev?.id ?? null);
      },
      highlightTag({ context, event }) {
        context.set("highlightedTagId", event.id);
      },
      highlightTagAtIndex({ context, scope }) {
        domQuery.raf(() => {
          const idx = context.get("editedTagIndex");
          if (idx == null) return;
          const tagEl = getTagElAtIndex(scope, idx);
          if (tagEl == null) return;
          context.set("highlightedTagId", tagEl.id);
          context.set("editedTagIndex", null);
        });
      },
      deleteTag({ context, scope, event, refs }) {
        const index = getIndexOfId(scope, event.id);
        const value = context.get("value")[index];
        const prevLog = refs.get("log");
        refs.set("log", {
          prev: prevLog.current,
          current: { type: "delete", value }
        });
        context.set("value", (prev) => utils.removeAt(prev, index));
      },
      deleteHighlightedTag({ context, scope, refs }) {
        const highlightedTagId = context.get("highlightedTagId");
        if (highlightedTagId == null) return;
        const index = getIndexOfId(scope, highlightedTagId);
        context.set("editedTagIndex", index);
        const value = context.get("value");
        const prevLog = refs.get("log");
        refs.set("log", {
          prev: prevLog.current,
          current: { type: "delete", value: value[index] }
        });
        context.set("value", (prev) => utils.removeAt(prev, index));
      },
      setEditedId({ context, event, scope }) {
        const highlightedTagId = context.get("highlightedTagId");
        const editedTagId = event.id ?? highlightedTagId;
        context.set("editedTagId", editedTagId);
        const index = getIndexOfId(scope, editedTagId);
        const valueAtIndex = context.get("value")[index];
        context.set("editedTagIndex", index);
        context.set("editedTagValue", valueAtIndex);
      },
      clearEditedId({ context }) {
        context.set("editedTagId", null);
      },
      clearEditedTagValue({ context }) {
        context.set("editedTagValue", "");
      },
      setEditedTagValue({ context, event }) {
        context.set("editedTagValue", event.value);
      },
      submitEditedTagValue({ context, scope, refs }) {
        const editedTagId = context.get("editedTagId");
        if (!editedTagId) return;
        const index = getIndexOfId(scope, editedTagId);
        context.set("value", (prev) => {
          const value = prev.slice();
          value[index] = context.get("editedTagValue");
          return value;
        });
        const prevLog = refs.get("log");
        refs.set("log", {
          prev: prevLog.current,
          current: { type: "update", value: context.get("editedTagValue") }
        });
      },
      setValueAtIndex({ context, event, refs }) {
        if (event.value) {
          context.set("value", (prev) => {
            const value = prev.slice();
            value[event.index] = event.value;
            return value;
          });
          const prevLog = refs.get("log");
          refs.set("log", {
            prev: prevLog.current,
            current: { type: "update", value: event.value }
          });
        } else {
          utils.warn("You need to provide a value for the tag");
        }
      },
      focusEditedTagInput({ context, scope }) {
        domQuery.raf(() => {
          const editedTagId = context.get("editedTagId");
          if (!editedTagId) return;
          const editTagInputEl = getEditInputEl(scope, editedTagId);
          editTagInputEl?.select();
        });
      },
      setInputValue({ context, event }) {
        context.set("inputValue", event.value);
      },
      clearHighlightedId({ context }) {
        context.set("highlightedTagId", null);
      },
      focusInput({ scope }) {
        domQuery.raf(() => {
          getInputEl(scope)?.focus();
        });
      },
      clearInputValue({ context }) {
        domQuery.raf(() => {
          context.set("inputValue", "");
        });
      },
      syncInputValue({ context, scope }) {
        const inputEl = getInputEl(scope);
        if (!inputEl) return;
        domQuery.setElementValue(inputEl, context.get("inputValue"));
      },
      syncEditedTagInputValue({ context, event, scope }) {
        const id = context.get("editedTagId") || context.get("highlightedTagId") || event.id;
        if (id == null) return;
        const editTagInputEl = getEditInputEl(scope, id);
        if (!editTagInputEl) return;
        domQuery.setElementValue(editTagInputEl, context.get("editedTagValue"));
      },
      addTag({ context, event, computed, prop, refs }) {
        const inputValue = event.value ?? computed("trimmedInputValue");
        const value = context.get("value");
        const guard = prop("validate")?.({ inputValue, value: Array.from(value) });
        if (guard) {
          const nextValue = utils.uniq(value.concat(inputValue));
          context.set("value", nextValue);
          const prevLog = refs.get("log");
          refs.set("log", {
            prev: prevLog.current,
            current: { type: "add", value: inputValue }
          });
        } else {
          prop("onValueInvalid")?.({ reason: "invalidTag" });
        }
      },
      addTagFromPaste({ context, computed, prop, refs }) {
        domQuery.raf(() => {
          const inputValue = computed("trimmedInputValue");
          const value = context.get("value");
          const guard = prop("validate")?.({
            inputValue,
            value: Array.from(value)
          });
          if (guard) {
            const delimiter = prop("delimiter");
            const trimmedValue = delimiter ? inputValue.split(delimiter).map((v) => v.trim()) : [inputValue];
            const nextValue = utils.uniq(value.concat(...trimmedValue));
            context.set("value", nextValue);
            const prevLog = refs.get("log");
            refs.set("log", {
              prev: prevLog.current,
              current: { type: "paste", values: trimmedValue }
            });
          } else {
            prop("onValueInvalid")?.({ reason: "invalidTag" });
          }
          context.set("inputValue", "");
        });
      },
      clearTags({ context, refs }) {
        context.set("value", []);
        const prevLog = refs.get("log");
        refs.set("log", {
          prev: prevLog.current,
          current: { type: "clear" }
        });
      },
      setValue({ context, event }) {
        context.set("value", event.value);
      },
      invokeOnInvalid({ prop, computed }) {
        if (computed("isOverflowing")) {
          prop("onValueInvalid")?.({ reason: "rangeOverflow" });
        }
      },
      clearLog({ refs }) {
        const log = refs.get("log");
        log.prev = log.current = null;
      },
      logHighlightedTag({ refs, context, scope }) {
        const highlightedTagId = context.get("highlightedTagId");
        const log = refs.get("log");
        if (highlightedTagId == null || !log.current) return;
        const index = getIndexOfId(scope, highlightedTagId);
        const value = context.get("value")[index];
        const prevLog = refs.get("log");
        refs.set("log", {
          prev: prevLog.current,
          current: { type: "select", value }
        });
      },
      // queue logs with screen reader and get it announced
      announceLog({ refs, prop }) {
        const liveRegion = refs.get("liveRegion");
        const translations = prop("translations");
        const log = refs.get("log");
        if (!log.current || liveRegion == null) return;
        const region = liveRegion;
        const { current, prev } = log;
        let msg;
        switch (current.type) {
          case "add":
            msg = translations.tagAdded(current.value);
            break;
          case "delete":
            msg = translations.tagDeleted(current.value);
            break;
          case "update":
            msg = translations.tagUpdated(current.value);
            break;
          case "paste":
            msg = translations.tagsPasted(current.values);
            break;
          case "select":
            msg = translations.tagSelected(current.value);
            if (prev?.type === "delete") {
              msg = `${translations.tagDeleted(prev.value)}. ${msg}`;
            } else if (prev?.type === "update") {
              msg = `${translations.tagUpdated(prev.value)}. ${msg}`;
            }
            break;
        }
        if (msg) region.announce(msg);
      }
    }
  }
});
var props = types.createProps()([
  "addOnPaste",
  "allowOverflow",
  "autoFocus",
  "blurBehavior",
  "delimiter",
  "dir",
  "disabled",
  "editable",
  "form",
  "getRootNode",
  "id",
  "ids",
  "inputValue",
  "invalid",
  "max",
  "maxLength",
  "name",
  "onFocusOutside",
  "onHighlightChange",
  "onInputValueChange",
  "onInteractOutside",
  "onPointerDownOutside",
  "onValueChange",
  "onValueInvalid",
  "required",
  "readOnly",
  "translations",
  "validate",
  "value",
  "defaultValue",
  "defaultInputValue"
]);
var splitProps = utils.createSplitProps(props);
var itemProps = types.createProps()(["index", "disabled", "value"]);
var splitItemProps = utils.createSplitProps(itemProps);

exports.anatomy = anatomy;
exports.connect = connect;
exports.itemProps = itemProps;
exports.machine = machine;
exports.props = props;
exports.splitItemProps = splitItemProps;
exports.splitProps = splitProps;
