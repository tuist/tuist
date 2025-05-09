import { createAnatomy } from '@zag-js/anatomy';
import { raf, dispatchInputValueEvent, queryAll, dataAttr, ariaAttr, isHTMLElement, isComposingEvent, isModifierKey, getEventKey, getNativeEvent, getBeforeInputValue, visuallyHiddenStyle } from '@zag-js/dom-query';
import { setValueAtIndex, isEqual, createSplitProps, invariant } from '@zag-js/utils';
import { setup } from '@zag-js/core';
import { createProps } from '@zag-js/types';

// src/pin-input.anatomy.ts
var anatomy = createAnatomy("pinInput").parts("root", "label", "input", "control");
var parts = anatomy.build();
var getRootId = (ctx) => ctx.ids?.root ?? `pin-input:${ctx.id}`;
var getInputId = (ctx, id) => ctx.ids?.input?.(id) ?? `pin-input:${ctx.id}:${id}`;
var getHiddenInputId = (ctx) => ctx.ids?.hiddenInput ?? `pin-input:${ctx.id}:hidden`;
var getLabelId = (ctx) => ctx.ids?.label ?? `pin-input:${ctx.id}:label`;
var getControlId = (ctx) => ctx.ids?.control ?? `pin-input:${ctx.id}:control`;
var getRootEl = (ctx) => ctx.getById(getRootId(ctx));
var getInputEls = (ctx) => {
  const ownerId = CSS.escape(getRootId(ctx));
  const selector = `input[data-ownedby=${ownerId}]`;
  return queryAll(getRootEl(ctx), selector);
};
var getInputElAtIndex = (ctx, index) => getInputEls(ctx)[index];
var getFirstInputEl = (ctx) => getInputEls(ctx)[0];
var getHiddenInputEl = (ctx) => ctx.getById(getHiddenInputId(ctx));
var setInputValue = (inputEl, value) => {
  inputEl.value = value;
  inputEl.setAttribute("value", value);
};

// src/pin-input.utils.ts
var REGEX = {
  numeric: /^[0-9]+$/,
  alphabetic: /^[A-Za-z]+$/,
  alphanumeric: /^[a-zA-Z0-9]+$/i
};
function isValidType(type, value) {
  if (!type) return true;
  return !!REGEX[type]?.test(value);
}
function isValidValue(value, type, pattern) {
  if (!pattern) return isValidType(type, value);
  const regex = new RegExp(pattern, "g");
  return regex.test(value);
}

// src/pin-input.connect.ts
function connect(service, normalize) {
  const { send, context, computed, prop, scope } = service;
  const complete = computed("isValueComplete");
  const invalid = prop("invalid");
  const translations = prop("translations");
  const focusedIndex = context.get("focusedIndex");
  function focus() {
    getFirstInputEl(scope)?.focus();
  }
  return {
    focus,
    count: context.get("count"),
    items: Array.from({ length: context.get("count") }).map((_, i) => i),
    value: context.get("value"),
    valueAsString: computed("valueAsString"),
    complete,
    setValue(value) {
      if (!Array.isArray(value)) {
        invariant("[pin-input/setValue] value must be an array");
      }
      send({ type: "VALUE.SET", value });
    },
    clearValue() {
      send({ type: "VALUE.CLEAR" });
    },
    setValueAtIndex(index, value) {
      send({ type: "VALUE.SET", value, index });
    },
    getRootProps() {
      return normalize.element({
        dir: prop("dir"),
        ...parts.root.attrs,
        id: getRootId(scope),
        "data-invalid": dataAttr(invalid),
        "data-disabled": dataAttr(prop("disabled")),
        "data-complete": dataAttr(complete),
        "data-readonly": dataAttr(prop("readOnly"))
      });
    },
    getLabelProps() {
      return normalize.label({
        ...parts.label.attrs,
        dir: prop("dir"),
        htmlFor: getHiddenInputId(scope),
        id: getLabelId(scope),
        "data-invalid": dataAttr(invalid),
        "data-disabled": dataAttr(prop("disabled")),
        "data-complete": dataAttr(complete),
        "data-readonly": dataAttr(prop("readOnly")),
        onClick(event) {
          event.preventDefault();
          focus();
        }
      });
    },
    getHiddenInputProps() {
      return normalize.input({
        "aria-hidden": true,
        type: "text",
        tabIndex: -1,
        id: getHiddenInputId(scope),
        readOnly: prop("readOnly"),
        disabled: prop("disabled"),
        required: prop("required"),
        name: prop("name"),
        form: prop("form"),
        style: visuallyHiddenStyle,
        maxLength: computed("valueLength"),
        defaultValue: computed("valueAsString")
      });
    },
    getControlProps() {
      return normalize.element({
        ...parts.control.attrs,
        dir: prop("dir"),
        id: getControlId(scope)
      });
    },
    getInputProps(props2) {
      const { index } = props2;
      const inputType = prop("type") === "numeric" ? "tel" : "text";
      return normalize.input({
        ...parts.input.attrs,
        dir: prop("dir"),
        disabled: prop("disabled"),
        "data-disabled": dataAttr(prop("disabled")),
        "data-complete": dataAttr(complete),
        id: getInputId(scope, index.toString()),
        "data-index": index,
        "data-ownedby": getRootId(scope),
        "aria-label": translations?.inputLabel?.(index, computed("valueLength")),
        inputMode: prop("otp") || prop("type") === "numeric" ? "numeric" : "text",
        "aria-invalid": ariaAttr(invalid),
        "data-invalid": dataAttr(invalid),
        type: prop("mask") ? "password" : inputType,
        defaultValue: context.get("value")[index] || "",
        readOnly: prop("readOnly"),
        autoCapitalize: "none",
        autoComplete: prop("otp") ? "one-time-code" : "off",
        placeholder: focusedIndex === index ? "" : prop("placeholder"),
        onBeforeInput(event) {
          try {
            const value = getBeforeInputValue(event);
            const isValid = isValidValue(value, prop("type"), prop("pattern"));
            if (!isValid) {
              send({ type: "VALUE.INVALID", value });
              event.preventDefault();
            }
            if (value.length > 2) {
              event.currentTarget.setSelectionRange(0, 1, "forward");
            }
          } catch {
          }
        },
        onChange(event) {
          const evt = getNativeEvent(event);
          const { value } = event.currentTarget;
          if (evt.inputType === "insertFromPaste" || value.length > 2) {
            send({ type: "INPUT.PASTE", value });
            event.currentTarget.value = value[0];
            event.preventDefault();
            return;
          }
          if (evt.inputType === "deleteContentBackward") {
            send({ type: "INPUT.BACKSPACE" });
            return;
          }
          send({ type: "INPUT.CHANGE", value, index });
        },
        onKeyDown(event) {
          if (event.defaultPrevented) return;
          if (isComposingEvent(event)) return;
          if (isModifierKey(event)) return;
          const keyMap = {
            Backspace() {
              send({ type: "INPUT.BACKSPACE" });
            },
            Delete() {
              send({ type: "INPUT.DELETE" });
            },
            ArrowLeft() {
              send({ type: "INPUT.ARROW_LEFT" });
            },
            ArrowRight() {
              send({ type: "INPUT.ARROW_RIGHT" });
            },
            Enter() {
              send({ type: "INPUT.ENTER" });
            }
          };
          const exec = keyMap[getEventKey(event, {
            dir: prop("dir"),
            orientation: "horizontal"
          })];
          if (exec) {
            exec(event);
            event.preventDefault();
          }
        },
        onFocus() {
          send({ type: "INPUT.FOCUS", index });
        },
        onBlur(event) {
          const target = event.relatedTarget;
          if (isHTMLElement(target) && target.dataset.ownedby === getRootId(scope)) return;
          send({ type: "INPUT.BLUR", index });
        }
      });
    }
  };
}
var { choose, createMachine } = setup();
var machine = createMachine({
  props({ props: props2 }) {
    return {
      placeholder: "\u25CB",
      otp: false,
      type: "numeric",
      defaultValue: props2.count ? fill([], props2.count) : [],
      ...props2,
      translations: {
        inputLabel: (index, length) => `pin code ${index + 1} of ${length}`,
        ...props2.translations
      }
    };
  },
  initialState() {
    return "idle";
  },
  context({ prop, bindable }) {
    return {
      value: bindable(() => ({
        value: prop("value"),
        defaultValue: prop("defaultValue"),
        isEqual,
        onChange(value) {
          prop("onValueChange")?.({ value, valueAsString: value.join("") });
        }
      })),
      focusedIndex: bindable(() => ({
        sync: true,
        defaultValue: -1
      })),
      // TODO: Move this to `props` in next major version
      count: bindable(() => ({
        defaultValue: prop("count")
      }))
    };
  },
  computed: {
    _value: ({ context }) => fill(context.get("value"), context.get("count")),
    valueLength: ({ computed }) => computed("_value").length,
    filledValueLength: ({ computed }) => computed("_value").filter((v) => v?.trim() !== "").length,
    isValueComplete: ({ computed }) => computed("valueLength") === computed("filledValueLength"),
    valueAsString: ({ computed }) => computed("_value").join(""),
    focusedValue: ({ computed, context }) => computed("_value")[context.get("focusedIndex")] || ""
  },
  entry: choose([
    {
      guard: "autoFocus",
      actions: ["setInputCount", "setFocusIndexToFirst"]
    },
    { actions: ["setInputCount"] }
  ]),
  watch({ action, track, context, computed }) {
    track([() => context.get("focusedIndex")], () => {
      action(["focusInput", "selectInputIfNeeded"]);
    });
    track([() => context.get("value").join(",")], () => {
      action(["syncInputElements", "dispatchInputEvent"]);
    });
    track([() => computed("isValueComplete")], () => {
      action(["invokeOnComplete", "blurFocusedInputIfNeeded"]);
    });
  },
  on: {
    "VALUE.SET": [
      {
        guard: "hasIndex",
        actions: ["setValueAtIndex"]
      },
      { actions: ["setValue"] }
    ],
    "VALUE.CLEAR": {
      actions: ["clearValue", "setFocusIndexToFirst"]
    }
  },
  states: {
    idle: {
      on: {
        "INPUT.FOCUS": {
          target: "focused",
          actions: ["setFocusedIndex"]
        }
      }
    },
    focused: {
      on: {
        "INPUT.CHANGE": {
          actions: ["setFocusedValue", "syncInputValue", "setNextFocusedIndex"]
        },
        "INPUT.PASTE": {
          actions: ["setPastedValue", "setLastValueFocusIndex"]
        },
        "INPUT.FOCUS": {
          actions: ["setFocusedIndex"]
        },
        "INPUT.BLUR": {
          target: "idle",
          actions: ["clearFocusedIndex"]
        },
        "INPUT.DELETE": {
          guard: "hasValue",
          actions: ["clearFocusedValue"]
        },
        "INPUT.ARROW_LEFT": {
          actions: ["setPrevFocusedIndex"]
        },
        "INPUT.ARROW_RIGHT": {
          actions: ["setNextFocusedIndex"]
        },
        "INPUT.BACKSPACE": [
          {
            guard: "hasValue",
            actions: ["clearFocusedValue"]
          },
          {
            actions: ["setPrevFocusedIndex", "clearFocusedValue"]
          }
        ],
        "INPUT.ENTER": {
          guard: "isValueComplete",
          actions: ["requestFormSubmit"]
        },
        "VALUE.INVALID": {
          actions: ["invokeOnInvalid"]
        }
      }
    }
  },
  implementations: {
    guards: {
      autoFocus: ({ prop }) => !!prop("autoFocus"),
      hasValue: ({ context }) => context.get("value")[context.get("focusedIndex")] !== "",
      isValueComplete: ({ computed }) => computed("isValueComplete"),
      hasIndex: ({ event }) => event.index !== void 0
    },
    actions: {
      dispatchInputEvent({ computed, scope }) {
        const inputEl = getHiddenInputEl(scope);
        dispatchInputValueEvent(inputEl, { value: computed("valueAsString") });
      },
      setInputCount({ scope, context, prop }) {
        if (prop("count")) return;
        const inputEls = getInputEls(scope);
        context.set("count", inputEls.length);
      },
      focusInput({ context, scope }) {
        const focusedIndex = context.get("focusedIndex");
        if (focusedIndex === -1) return;
        getInputElAtIndex(scope, focusedIndex)?.focus({ preventScroll: true });
      },
      selectInputIfNeeded({ context, prop, scope }) {
        const focusedIndex = context.get("focusedIndex");
        if (!prop("selectOnFocus") || focusedIndex === -1) return;
        raf(() => {
          getInputElAtIndex(scope, focusedIndex)?.select();
        });
      },
      invokeOnComplete({ computed, prop }) {
        if (!computed("isValueComplete")) return;
        prop("onValueComplete")?.({
          value: computed("_value"),
          valueAsString: computed("valueAsString")
        });
      },
      invokeOnInvalid({ context, event, prop }) {
        prop("onValueInvalid")?.({
          value: event.value,
          index: context.get("focusedIndex")
        });
      },
      clearFocusedIndex({ context }) {
        context.set("focusedIndex", -1);
      },
      setFocusedIndex({ context, event }) {
        context.set("focusedIndex", event.index);
      },
      setValue({ context, event }) {
        const value = fill(event.value, context.get("count"));
        context.set("value", value);
      },
      setFocusedValue({ context, event, computed, flush }) {
        const focusedValue = computed("focusedValue");
        const focusedIndex = context.get("focusedIndex");
        const value = getNextValue(focusedValue, event.value);
        flush(() => {
          context.set("value", setValueAtIndex(computed("_value"), focusedIndex, value));
        });
      },
      revertInputValue({ context, computed, scope }) {
        const inputEl = getInputElAtIndex(scope, context.get("focusedIndex"));
        setInputValue(inputEl, computed("focusedValue"));
      },
      syncInputValue({ context, event, scope }) {
        const value = context.get("value");
        const inputEl = getInputElAtIndex(scope, event.index);
        setInputValue(inputEl, value[event.index]);
      },
      syncInputElements({ context, scope }) {
        const inputEls = getInputEls(scope);
        const value = context.get("value");
        inputEls.forEach((inputEl, index) => {
          setInputValue(inputEl, value[index]);
        });
      },
      setPastedValue({ context, event, computed, flush }) {
        raf(() => {
          const valueAsString = computed("valueAsString");
          const focusedIndex = context.get("focusedIndex");
          const valueLength = computed("valueLength");
          const filledValueLength = computed("filledValueLength");
          const startIndex = Math.min(focusedIndex, filledValueLength);
          const left = startIndex > 0 ? valueAsString.substring(0, focusedIndex) : "";
          const right = event.value.substring(0, valueLength - startIndex);
          const value = fill(`${left}${right}`.split(""), valueLength);
          flush(() => {
            context.set("value", value);
          });
        });
      },
      setValueAtIndex({ context, event, computed }) {
        const nextValue = getNextValue(computed("focusedValue"), event.value);
        context.set("value", setValueAtIndex(computed("_value"), event.index, nextValue));
      },
      clearValue({ context }) {
        const nextValue = Array.from({ length: context.get("count") }).fill("");
        context.set("value", nextValue);
      },
      clearFocusedValue({ context, computed }) {
        const focusedIndex = context.get("focusedIndex");
        if (focusedIndex === -1) return;
        context.set("value", setValueAtIndex(computed("_value"), focusedIndex, ""));
      },
      setFocusIndexToFirst({ context }) {
        context.set("focusedIndex", 0);
      },
      setNextFocusedIndex({ context, computed }) {
        context.set("focusedIndex", Math.min(context.get("focusedIndex") + 1, computed("valueLength") - 1));
      },
      setPrevFocusedIndex({ context }) {
        context.set("focusedIndex", Math.max(context.get("focusedIndex") - 1, 0));
      },
      setLastValueFocusIndex({ context, computed }) {
        raf(() => {
          context.set("focusedIndex", Math.min(computed("filledValueLength"), computed("valueLength") - 1));
        });
      },
      blurFocusedInputIfNeeded({ context, prop, scope }) {
        if (!prop("blurOnComplete")) return;
        raf(() => {
          getInputElAtIndex(scope, context.get("focusedIndex"))?.blur();
        });
      },
      requestFormSubmit({ computed, prop, scope }) {
        if (!prop("name") || !computed("isValueComplete")) return;
        const inputEl = getHiddenInputEl(scope);
        inputEl?.form?.requestSubmit();
      }
    }
  }
});
function getNextValue(current, next) {
  let nextValue = next;
  if (current[0] === next[0]) nextValue = next[1];
  else if (current[0] === next[1]) nextValue = next[0];
  return nextValue.split("")[nextValue.length - 1];
}
function fill(value, count) {
  return Array.from({ length: count }).fill("").map((v, i) => value[i] || v);
}
var props = createProps()([
  "autoFocus",
  "blurOnComplete",
  "count",
  "defaultValue",
  "dir",
  "disabled",
  "form",
  "getRootNode",
  "id",
  "ids",
  "invalid",
  "mask",
  "name",
  "onValueChange",
  "onValueComplete",
  "onValueInvalid",
  "otp",
  "pattern",
  "placeholder",
  "readOnly",
  "required",
  "selectOnFocus",
  "translations",
  "type",
  "value"
]);
var splitProps = createSplitProps(props);

export { anatomy, connect, machine, props, splitProps };
