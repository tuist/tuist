import { defineComponent, ref, onBeforeUnmount, watchEffect } from 'vue';
import { i as injectHead, V as Vue3 } from './shared/vue.ziyDaVMR.mjs';
import 'unhead';
import '@unhead/shared';

function addVNodeToHeadObj(node, obj) {
  const nodeType = !Vue3 ? node.tag : node.type;
  const type = nodeType === "html" ? "htmlAttrs" : nodeType === "body" ? "bodyAttrs" : nodeType;
  if (typeof type !== "string" || !(type in obj))
    return;
  const nodeData = !Vue3 ? node.data : node;
  const props = (!Vue3 ? nodeData.attrs : node.props) || {};
  if (!Vue3) {
    if (nodeData.staticClass)
      props.class = nodeData.staticClass;
    if (nodeData.staticStyle)
      props.style = Object.entries(nodeData.staticStyle).map(([key, value]) => `${key}:${value}`).join(";");
  }
  if (node.children) {
    const childrenAttr = !Vue3 ? "text" : "children";
    props.children = Array.isArray(node.children) ? node.children[0][childrenAttr] : node[childrenAttr];
  }
  if (Array.isArray(obj[type]))
    obj[type].push(props);
  else if (type === "title")
    obj.title = props.children;
  else
    obj[type] = props;
}
function vnodesToHeadObj(nodes) {
  const obj = {
    title: void 0,
    htmlAttrs: void 0,
    bodyAttrs: void 0,
    base: void 0,
    meta: [],
    link: [],
    style: [],
    script: [],
    noscript: []
  };
  for (const node of nodes) {
    if (typeof node.type === "symbol" && Array.isArray(node.children)) {
      for (const childNode of node.children)
        addVNodeToHeadObj(childNode, obj);
    } else {
      addVNodeToHeadObj(node, obj);
    }
  }
  return obj;
}
const Head = /* @__PURE__ */ defineComponent({
  name: "Head",
  setup(_, { slots }) {
    const head = injectHead();
    const obj = ref({});
    const entry = head.push(obj);
    onBeforeUnmount(() => {
      entry.dispose();
    });
    return () => {
      watchEffect(() => {
        if (!slots.default)
          return;
        entry.patch(vnodesToHeadObj(slots.default()));
      });
      return null;
    };
  }
});

export { Head };
