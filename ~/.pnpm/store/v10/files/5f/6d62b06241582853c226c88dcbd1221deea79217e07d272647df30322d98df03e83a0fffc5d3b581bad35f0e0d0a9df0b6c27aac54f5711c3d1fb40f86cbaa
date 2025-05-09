import { defineComponent as y, computed as v, openBlock as B, createElementBlock as C, normalizeClass as L, withModifiers as m, unref as D, renderSlot as T } from "vue";
import { hoveredItem as r, draggingItem as n } from "./store.js";
import { throttle as w } from "./throttle.js";
const k = ["draggable"], O = /* @__PURE__ */ y({
  __name: "Draggable",
  props: {
    ceiling: { default: 0.8 },
    floor: { default: 0.2 },
    isDraggable: { type: Boolean, default: !0 },
    isDroppable: { type: [Boolean, Function], default: !0 },
    parentIds: {},
    id: {}
  },
  emits: ["onDragEnd", "onDragStart"],
  setup(t, { expose: b, emit: p }) {
    const d = p, l = v(() => t.parentIds.at(-1) ?? null), I = (e) => {
      !e.dataTransfer || !(e.target instanceof HTMLElement) || !t.isDraggable || (e.target.classList.add("dragging"), e.dataTransfer.dropEffect = "move", e.dataTransfer.effectAllowed = "move", n.value = { id: t.id, parentId: l.value }, d("onDragStart", { id: t.id, parentId: l.value }));
    }, h = (e) => typeof t.isDroppable == "function" ? t.isDroppable(n.value, {
      id: t.id,
      parentId: l.value,
      offset: e
    }) : t.isDroppable, s = w((e) => {
      var g, c;
      if (!n.value || n.value.id === t.id || t.parentIds.includes(((g = n.value) == null ? void 0 : g.id) ?? ""))
        return;
      const a = (c = r.value) == null ? void 0 : c.offset, o = e.target.offsetHeight, f = t.floor * o, u = t.ceiling * o;
      let i = 3;
      e.offsetY <= 0 && a && a !== 3 ? i = a : e.offsetY <= f ? i = 0 : e.offsetY >= u ? i = 1 : e.offsetY > f && e.offsetY < u && (i = 2), h(i) && (r.value = { id: t.id, parentId: l.value, offset: i });
    }, 25), E = ["above", "below", "asChild"], S = v(() => {
      var a;
      let e = "sidebar-indent-nested";
      return t.id === ((a = r.value) == null ? void 0 : a.id) && (e += ` dragover-${E[r.value.offset]}`), e;
    }), Y = () => {
      if (!r.value || !n.value) return;
      const e = { ...n.value }, a = { ...r.value };
      n.value = null, r.value = null, document.querySelectorAll("div.dragging").forEach((o) => o.classList.remove("dragging")), e.id !== a.id && d("onDragEnd", e, a);
    };
    return b({
      draggingItem: n,
      hoveredItem: r
    }), (e, a) => (B(), C("div", {
      class: L(S.value),
      draggable: e.isDraggable,
      onDragend: Y,
      onDragover: a[0] || (a[0] = m(
        //@ts-ignore
        (...o) => D(s) && D(s)(...o),
        ["prevent", "stop"]
      )),
      onDragstart: m(I, ["stop"])
    }, [
      T(e.$slots, "default", {}, void 0, !0)
    ], 42, k));
  }
});
export {
  O as default
};
