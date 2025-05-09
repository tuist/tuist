import { createAnatomy } from '@zag-js/anatomy';
import { dispatchInputCheckedEvent, setElementChecked, trackFormControl, trackPress, dataAttr, visuallyHiddenStyle, getEventTarget } from '@zag-js/dom-query';
import { trackFocusVisible, isFocusVisible } from '@zag-js/focus-visible';
import { createGuards, createMachine } from '@zag-js/core';
import { createProps } from '@zag-js/types';
import { createSplitProps } from '@zag-js/utils';

// src/checkbox.anatomy.ts
var anatomy = createAnatomy("checkbox").parts("root", "label", "control", "indicator");
var parts = anatomy.build();

// src/checkbox.dom.ts
var getRootId = (ctx) => ctx.ids?.root ?? `checkbox:${ctx.id}`;
var getLabelId = (ctx) => ctx.ids?.label ?? `checkbox:${ctx.id}:label`;
var getControlId = (ctx) => ctx.ids?.control ?? `checkbox:${ctx.id}:control`;
var getHiddenInputId = (ctx) => ctx.ids?.hiddenInput ?? `checkbox:${ctx.id}:input`;
var getRootEl = (ctx) => ctx.getById(getRootId(ctx));
var getHiddenInputEl = (ctx) => ctx.getById(getHiddenInputId(ctx));

// src/checkbox.connect.ts
function connect(service, normalize) {
  const { send, context, prop, computed, scope } = service;
  const disabled = prop("disabled");
  const readOnly = prop("readOnly");
  const invalid = prop("invalid");
  const focused = !disabled && context.get("focused");
  const focusVisible = !disabled && context.get("focusVisible");
  const checked = computed("checked");
  const indeterminate = computed("indeterminate");
  const dataAttrs = {
    "data-active": dataAttr(context.get("active")),
    "data-focus": dataAttr(focused),
    "data-focus-visible": dataAttr(focusVisible),
    "data-readonly": dataAttr(readOnly),
    "data-hover": dataAttr(context.get("hovered")),
    "data-disabled": dataAttr(disabled),
    "data-state": indeterminate ? "indeterminate" : checked ? "checked" : "unchecked",
    "data-invalid": dataAttr(invalid)
  };
  return {
    checked,
    disabled,
    indeterminate,
    focused,
    checkedState: checked,
    setChecked(checked2) {
      send({ type: "CHECKED.SET", checked: checked2, isTrusted: false });
    },
    toggleChecked() {
      send({ type: "CHECKED.TOGGLE", checked, isTrusted: false });
    },
    getRootProps() {
      return normalize.label({
        ...parts.root.attrs,
        ...dataAttrs,
        dir: prop("dir"),
        id: getRootId(scope),
        htmlFor: getHiddenInputId(scope),
        onPointerMove() {
          if (disabled) return;
          send({ type: "CONTEXT.SET", context: { hovered: true } });
        },
        onPointerLeave() {
          if (disabled) return;
          send({ type: "CONTEXT.SET", context: { hovered: false } });
        },
        onClick(event) {
          const target = getEventTarget(event);
          if (target === getHiddenInputEl(scope)) {
            event.stopPropagation();
          }
        }
      });
    },
    getLabelProps() {
      return normalize.element({
        ...parts.label.attrs,
        ...dataAttrs,
        dir: prop("dir"),
        id: getLabelId(scope)
      });
    },
    getControlProps() {
      return normalize.element({
        ...parts.control.attrs,
        ...dataAttrs,
        dir: prop("dir"),
        id: getControlId(scope),
        "aria-hidden": true
      });
    },
    getIndicatorProps() {
      return normalize.element({
        ...parts.indicator.attrs,
        ...dataAttrs,
        dir: prop("dir"),
        hidden: !indeterminate && !checked
      });
    },
    getHiddenInputProps() {
      return normalize.input({
        id: getHiddenInputId(scope),
        type: "checkbox",
        required: prop("required"),
        defaultChecked: checked,
        disabled,
        "aria-labelledby": getLabelId(scope),
        "aria-invalid": invalid,
        name: prop("name"),
        form: prop("form"),
        value: prop("value"),
        style: visuallyHiddenStyle,
        onFocus() {
          const focusVisible2 = isFocusVisible();
          send({ type: "CONTEXT.SET", context: { focused: true, focusVisible: focusVisible2 } });
        },
        onBlur() {
          send({ type: "CONTEXT.SET", context: { focused: false, focusVisible: false } });
        },
        onClick(event) {
          if (readOnly) {
            event.preventDefault();
            return;
          }
          const checked2 = event.currentTarget.checked;
          send({ type: "CHECKED.SET", checked: checked2, isTrusted: true });
        }
      });
    }
  };
}
var { not } = createGuards();
var machine = createMachine({
  props({ props: props2 }) {
    return {
      value: "on",
      ...props2,
      defaultChecked: !!props2.defaultChecked
    };
  },
  initialState() {
    return "ready";
  },
  context({ prop, bindable }) {
    return {
      checked: bindable(() => ({
        defaultValue: prop("defaultChecked"),
        value: prop("checked"),
        onChange(checked) {
          prop("onCheckedChange")?.({ checked });
        }
      })),
      fieldsetDisabled: bindable(() => ({ defaultValue: false })),
      focusVisible: bindable(() => ({ defaultValue: false })),
      active: bindable(() => ({ defaultValue: false })),
      focused: bindable(() => ({ defaultValue: false })),
      hovered: bindable(() => ({ defaultValue: false }))
    };
  },
  watch({ track, context, prop, action }) {
    track([() => prop("disabled")], () => {
      action(["removeFocusIfNeeded"]);
    });
    track([() => context.get("checked")], () => {
      action(["syncInputElement"]);
    });
  },
  effects: ["trackFormControlState", "trackPressEvent", "trackFocusVisible"],
  on: {
    "CHECKED.TOGGLE": [
      {
        guard: not("isTrusted"),
        actions: ["toggleChecked", "dispatchChangeEvent"]
      },
      {
        actions: ["toggleChecked"]
      }
    ],
    "CHECKED.SET": [
      {
        guard: not("isTrusted"),
        actions: ["setChecked", "dispatchChangeEvent"]
      },
      {
        actions: ["setChecked"]
      }
    ],
    "CONTEXT.SET": {
      actions: ["setContext"]
    }
  },
  computed: {
    indeterminate: ({ context }) => isIndeterminate(context.get("checked")),
    checked: ({ context }) => isChecked(context.get("checked")),
    disabled: ({ context, prop }) => !!prop("disabled") || context.get("fieldsetDisabled")
  },
  states: {
    ready: {}
  },
  implementations: {
    guards: {
      isTrusted: ({ event }) => !!event.isTrusted
    },
    effects: {
      trackPressEvent({ context, computed, scope }) {
        if (computed("disabled")) return;
        return trackPress({
          pointerNode: getRootEl(scope),
          keyboardNode: getHiddenInputEl(scope),
          isValidKey: (event) => event.key === " ",
          onPress: () => context.set("active", false),
          onPressStart: () => context.set("active", true),
          onPressEnd: () => context.set("active", false)
        });
      },
      trackFocusVisible({ computed, scope }) {
        if (computed("disabled")) return;
        return trackFocusVisible({ root: scope.getRootNode?.() });
      },
      trackFormControlState({ context, scope }) {
        return trackFormControl(getHiddenInputEl(scope), {
          onFieldsetDisabledChange(disabled) {
            context.set("fieldsetDisabled", disabled);
          },
          onFormReset() {
            context.set("checked", context.initial("checked"));
          }
        });
      }
    },
    actions: {
      setContext({ context, event }) {
        for (const key in event.context) {
          context.set(key, event.context[key]);
        }
      },
      syncInputElement({ context, computed, scope }) {
        const inputEl = getHiddenInputEl(scope);
        if (!inputEl) return;
        setElementChecked(inputEl, computed("checked"));
        inputEl.indeterminate = isIndeterminate(context.get("checked"));
      },
      removeFocusIfNeeded({ context, prop }) {
        if (prop("disabled") && context.get("focused")) {
          context.set("focused", false);
          context.set("focusVisible", false);
        }
      },
      setChecked({ context, event }) {
        context.set("checked", event.checked);
      },
      toggleChecked({ context, computed }) {
        const checked = isIndeterminate(computed("checked")) ? true : !computed("checked");
        context.set("checked", checked);
      },
      dispatchChangeEvent({ computed, scope }) {
        queueMicrotask(() => {
          const inputEl = getHiddenInputEl(scope);
          dispatchInputCheckedEvent(inputEl, { checked: computed("checked") });
        });
      }
    }
  }
});
function isIndeterminate(checked) {
  return checked === "indeterminate";
}
function isChecked(checked) {
  return isIndeterminate(checked) ? false : !!checked;
}
var props = createProps()([
  "defaultChecked",
  "checked",
  "dir",
  "disabled",
  "form",
  "getRootNode",
  "id",
  "ids",
  "invalid",
  "name",
  "onCheckedChange",
  "readOnly",
  "required",
  "value"
]);
var splitProps = createSplitProps(props);

export { anatomy, connect, machine, props, splitProps };
