'use strict';

var core = require('@vueuse/core');
var vueDemi = require('vue-demi');
var Sortable = require('sortablejs');

function useSortable(el, list, options = {}) {
  let sortable;
  const { document = core.defaultDocument, ...resetOptions } = options;
  const defaultOptions = {
    onUpdate: (e) => {
      moveArrayElement(list, e.oldIndex, e.newIndex, e);
    }
  };
  const start = () => {
    const target = typeof el === "string" ? document?.querySelector(el) : core.unrefElement(el);
    if (!target || sortable !== void 0)
      return;
    sortable = new Sortable(target, { ...defaultOptions, ...resetOptions });
  };
  const stop = () => {
    sortable?.destroy();
    sortable = void 0;
  };
  const option = (name, value) => {
    if (value !== void 0)
      sortable?.option(name, value);
    else
      return sortable?.option(name);
  };
  core.tryOnMounted(start);
  core.tryOnScopeDispose(stop);
  return {
    stop,
    start,
    option
  };
}
function insertNodeAt(parentElement, element, index) {
  const refElement = parentElement.children[index];
  parentElement.insertBefore(element, refElement);
}
function removeNode(node) {
  if (node.parentNode)
    node.parentNode.removeChild(node);
}
function moveArrayElement(list, from, to, e = null) {
  if (e != null) {
    removeNode(e.item);
    insertNodeAt(e.from, e.item, from);
  }
  const _valueIsRef = vueDemi.isRef(list);
  const array = _valueIsRef ? [...core.toValue(list)] : core.toValue(list);
  if (to >= 0 && to < array.length) {
    const element = array.splice(from, 1)[0];
    vueDemi.nextTick(() => {
      array.splice(to, 0, element);
      if (_valueIsRef)
        list.value = array;
    });
  }
}

const UseSortable = /* @__PURE__ */ /* #__PURE__ */ vueDemi.defineComponent({
  name: "UseSortable",
  model: {
    // Compatible with vue2
    prop: "modelValue",
    event: "update:modelValue"
  },
  props: {
    modelValue: {
      type: Array,
      required: true
    },
    tag: {
      type: String,
      default: "div"
    },
    options: {
      type: Object,
      required: true
    }
  },
  setup(props, { slots }) {
    const list = core.useVModel(props, "modelValue");
    const target = vueDemi.ref();
    const data = vueDemi.reactive(useSortable(target, list, props.options));
    return () => {
      if (slots.default)
        return vueDemi.h(props.tag, { ref: target }, slots.default(data));
    };
  }
});

exports.UseSortable = UseSortable;
