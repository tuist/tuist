var h = Object.defineProperty;
var u = (n, t, e) => t in n ? h(n, t, { enumerable: !0, configurable: !0, writable: !0, value: e }) : n[t] = e;
var l = (n, t, e) => u(n, typeof t != "symbol" ? t + "" : t, e);
import { getEnvColor as f } from "../../libs/env-helpers.js";
import { ScalarButton as b, ScalarIcon as v, ScalarTooltip as g } from "@scalar/components";
import { REGEX as w } from "@scalar/oas-utils/helpers";
import { ViewPlugin as y, RangeSetBuilder as x, Decoration as E, EditorView as N, WidgetType as k } from "@scalar/use-codemirror";
import { defineComponent as C, h as s, createApp as V } from "vue";
import { parseEnvVariables as R } from "../../libs/environment-parser.js";
class d extends k {
  constructor(e, o, i, c, a) {
    super();
    l(this, "app");
    l(this, "environment");
    l(this, "envVariables");
    l(this, "workspace");
    l(this, "isReadOnly");
    this.variableName = e, this.variableName = e, this.environment = o, this.envVariables = i, this.workspace = c, this.isReadOnly = a ?? !1;
  }
  toDOM() {
    const e = document.createElement("span");
    e.className = "cm-pill", e.textContent = `${this.variableName}`;
    const o = C({
      props: { variableName: { type: String, default: null } },
      render: () => {
        const i = this.envVariables ? R(this.envVariables).find((r) => r.key === this.variableName) : void 0, c = i && this.environment ? f(this.environment) : "#8E8E8E";
        e.style.setProperty("--tw-bg-base", c || "#8E8E8E"), e.style.opacity = i != null && i.value ? "1" : "0.5";
        const a = i != null && i.value ? s("div", { class: "p-2" }, i.value) : s("div", { class: "divide-y divide-1/2 grid" }, [
          s("span", { class: "p-2 opacity-25" }, "No value"),
          !this.isReadOnly && s("div", { class: "p-1" }, [
            s(
              b,
              {
                class: "gap-1.5 justify-start font-normal px-1 py-1.5 h-auto transition-colors rounded no-underline text-xxs w-full hover:bg-b-2",
                variant: "ghost",
                onClick: () => {
                  var r;
                  window.location.href = `/workspace/${(r = this.workspace) == null ? void 0 : r.uid}/environment`;
                }
              },
              {
                default: () => [
                  s(v, {
                    class: "w-2",
                    icon: "Add",
                    size: "xs"
                  }),
                  "Add variable"
                ]
              }
            )
          ])
        ]);
        return s(
          g,
          {
            align: "center",
            class: "w-full",
            delay: 0,
            side: "bottom",
            sideOffset: 6
          },
          {
            trigger: () => s("span", `${this.variableName}`),
            content: () => s(
              "div",
              {
                class: [
                  "border w-content rounded  bg-b-1 brightness-lifted text-xxs leading-5 text-c-1",
                  i != null && i.value ? "border-solid" : "border-dashed"
                ]
              },
              a
            )
          }
        );
      }
    });
    return this.app = V(o, { variableName: this.variableName }), this.app.mount(e), e;
  }
  destroy() {
    this.app && this.app.unmount();
  }
  eq(e) {
    return e instanceof d && e.variableName === this.variableName;
  }
  ignoreEvent() {
    return !1;
  }
}
const q = (n) => y.fromClass(
  class {
    constructor(t) {
      l(this, "decorations");
      this.decorations = this.buildDecorations(t);
    }
    update(t) {
      (t.docChanged || t.viewportChanged) && requestAnimationFrame(() => {
        this.decorations = this.buildDecorations(t.view), t.view.update([]);
      });
    }
    buildDecorations(t) {
      const e = new x();
      for (const { from: o, to: i } of t.visibleRanges) {
        const c = t.state.doc.sliceString(o, i);
        let a;
        for (; (a = w.VARIABLES.exec(c)) !== null; ) {
          const r = o + a.index, p = r + a[0].length, m = a[1] ?? "";
          e.add(
            r,
            p,
            E.widget({
              widget: new d(
                m,
                n.environment,
                n.envVariables,
                n.workspace,
                n.isReadOnly
              ),
              side: 1
            })
          );
        }
      }
      return e.finish();
    }
  },
  {
    decorations: (t) => t.decorations
  }
), I = N.domEventHandlers({
  keydown(n, t) {
    if (n.key === "Backspace") {
      const { state: e } = t, { from: o, to: i } = e.selection.main;
      if (o === 0 && i === e.doc.length)
        return t.dispatch({
          changes: { from: 0, to: e.doc.length },
          selection: { anchor: 0 }
        }), n.preventDefault(), !0;
      if (o === i && o > 0 && e.doc.sliceString(o - 2, o) === "}}")
        return t.dispatch({
          changes: { from: o - 2, to: i },
          selection: { anchor: o - 2 }
        }), n.preventDefault(), !0;
    }
    return !1;
  }
});
export {
  I as backspaceCommand,
  q as pillPlugin
};
