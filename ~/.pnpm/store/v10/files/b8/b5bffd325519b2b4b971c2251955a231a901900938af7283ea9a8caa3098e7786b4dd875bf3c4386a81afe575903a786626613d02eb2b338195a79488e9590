import { defineComponent as L, computed as O, ref as D, openBlock as c, createElementBlock as z, createElementVNode as a, createVNode as n, unref as t, withCtx as o, Fragment as I, renderList as U, createBlock as g, withModifiers as r, toDisplayString as C } from "vue";
import { useModal as S, ScalarDropdown as $, ScalarDropdownItem as u, ScalarListboxCheckbox as V, ScalarIcon as p, ScalarTooltip as q, ScalarButton as E, ScalarDropdownDivider as F, ScalarModal as N } from "@scalar/components";
import { useRouter as P } from "vue-router";
import Y from "../../../components/Sidebar/Actions/DeleteSidebarListElement.vue.js";
import G from "../../../components/Sidebar/Actions/EditSidebarListElement.vue.js";
import { useActiveEntities as H } from "../../../store/active-entities.js";
import { useWorkspace as J } from "../../../store/store.js";
const K = { class: "flex w-[inherit] items-center text-sm" }, Q = { class: "m-0 flex items-center gap-1.5 font-bold" }, X = { class: "line-clamp-1 text-left" }, Z = { class: "overflow-hidden text-ellipsis" }, ee = { class: "flex h-4 w-4 items-center justify-center" }, de = /* @__PURE__ */ L({
  __name: "WorkspaceDropdown",
  setup(te) {
    const { activeWorkspace: m } = H(), { workspaces: d, workspaceMutators: b, events: T } = J(), { push: _ } = P(), j = (s) => {
      var e;
      s !== ((e = m.value) == null ? void 0 : e.uid) && _({
        name: "workspace",
        params: {
          workspace: s
        }
      });
    }, y = O(() => Object.keys(d).length === 1), B = () => T.commandPalette.emit({ commandName: "Create Workspace" }), f = D(""), i = D(""), v = S(), w = S(), M = (s) => {
      const e = d[s];
      e && (f.value = e.name, i.value = s, v.show());
    }, R = (s) => {
      s.trim() && (b.edit(i.value, "name", s.trim()), v.hide());
    }, W = (s) => {
      const e = d[s];
      e && (f.value = e.name, i.value = s, w.show());
    }, A = async () => {
      var s;
      if (!y.value) {
        const e = ((s = m.value) == null ? void 0 : s.uid) === i.value, l = { ...d };
        if (delete l[i.value], b.delete(i.value), e) {
          const k = Object.keys(l)[0];
          await _({
            name: "workspace",
            params: {
              workspace: k
            }
          });
        }
      }
      w.hide();
    };
    return (s, e) => (c(), z("div", null, [
      a("div", K, [
        n(t($), null, {
          items: o(() => [
            (c(!0), z(I, null, U(t(d), (l, k) => (c(), g(t(u), {
              key: k,
              class: "group/item flex w-full items-center gap-1.5 overflow-hidden text-ellipsis whitespace-nowrap",
              onClick: r((x) => j(l.uid), ["stop"])
            }, {
              default: o(() => {
                var x;
                return [
                  n(t(V), {
                    selected: ((x = t(m)) == null ? void 0 : x.uid) === k
                  }, null, 8, ["selected"]),
                  a("span", Z, C(l.name), 1),
                  n(t($), {
                    placement: "right-start",
                    teleport: ""
                  }, {
                    items: o(() => [
                      n(t(u), {
                        class: "flex gap-2",
                        onMousedown: (h) => M(l.uid),
                        onTouchend: r((h) => M(l.uid), ["prevent"])
                      }, {
                        default: o(() => [
                          n(t(p), {
                            class: "inline-flex",
                            icon: "Edit",
                            size: "md",
                            thickness: "1.5"
                          }),
                          e[4] || (e[4] = a("span", null, "Rename", -1))
                        ]),
                        _: 2
                      }, 1032, ["onMousedown", "onTouchend"]),
                      y.value ? (c(), g(t(q), {
                        key: 0,
                        class: "z-overlay",
                        side: "bottom"
                      }, {
                        trigger: o(() => [
                          n(t(u), {
                            class: "flex w-full gap-2",
                            disabled: "",
                            onMousedown: e[0] || (e[0] = r(() => {
                            }, ["prevent"])),
                            onTouchend: e[1] || (e[1] = r(() => {
                            }, ["prevent"]))
                          }, {
                            default: o(() => [
                              n(t(p), {
                                class: "inline-flex",
                                icon: "Delete",
                                size: "md",
                                thickness: "1.5"
                              }),
                              e[5] || (e[5] = a("span", null, "Delete", -1))
                            ]),
                            _: 1
                          })
                        ]),
                        content: o(() => e[6] || (e[6] = [
                          a("div", { class: "w-content bg-b-1 text-xxs text-c-1 pointer-events-none z-10 grid min-w-48 gap-1.5 rounded p-2 leading-5 shadow-lg" }, [
                            a("div", { class: "text-c-2 flex items-center" }, [
                              a("span", null, "Only workspace cannot be deleted.")
                            ])
                          ], -1)
                        ])),
                        _: 1
                      })) : (c(), g(t(u), {
                        key: 1,
                        class: "flex !gap-2",
                        onMousedown: r((h) => W(l.uid), ["prevent"]),
                        onTouchend: r((h) => W(l.uid), ["prevent"])
                      }, {
                        default: o(() => [
                          n(t(p), {
                            class: "inline-flex",
                            icon: "Delete",
                            size: "sm",
                            thickness: "1.5"
                          }),
                          e[7] || (e[7] = a("span", null, "Delete", -1))
                        ]),
                        _: 2
                      }, 1032, ["onMousedown", "onTouchend"]))
                    ]),
                    default: o(() => [
                      n(t(E), {
                        class: "hover:bg-b-3 -mr-1 ml-auto aspect-square h-fit px-0.5 py-0 group-hover/item:flex",
                        size: "sm",
                        type: "button",
                        variant: "ghost"
                      }, {
                        default: o(() => [
                          n(t(p), {
                            icon: "Ellipses",
                            size: "sm"
                          })
                        ]),
                        _: 1
                      })
                    ]),
                    _: 2
                  }, 1024)
                ];
              }),
              _: 2
            }, 1032, ["onClick"]))), 128)),
            n(t(F)),
            n(t(u), {
              class: "flex items-center gap-1.5",
              onClick: B
            }, {
              default: o(() => [
                a("div", ee, [
                  n(t(p), {
                    icon: "Add",
                    size: "sm"
                  })
                ]),
                e[8] || (e[8] = a("span", null, "Create Workspace", -1))
              ]),
              _: 1
            })
          ]),
          default: o(() => [
            n(t(E), {
              class: "text-c-1 hover:bg-b-2 line-clamp-1 h-full w-fit justify-start px-1.5 py-1.5 font-normal",
              fullWidth: "",
              variant: "ghost"
            }, {
              default: o(() => {
                var l;
                return [
                  a("div", Q, [
                    a("h2", X, C((l = t(m)) == null ? void 0 : l.name), 1)
                  ])
                ];
              }),
              _: 1
            })
          ]),
          _: 1
        })
      ]),
      n(t(N), {
        size: "xxs",
        state: t(w),
        title: "Delete workspace"
      }, {
        default: o(() => [
          n(Y, {
            variableName: f.value,
            warningMessage: "This cannot be undone. You’re about to delete the workspace and everything inside it.",
            onClose: e[2] || (e[2] = (l) => t(w).hide()),
            onDelete: A
          }, null, 8, ["variableName"])
        ]),
        _: 1
      }, 8, ["state"]),
      n(t(N), {
        size: "xxs",
        state: t(v),
        title: "Rename Workspace"
      }, {
        default: o(() => [
          n(G, {
            name: f.value,
            onClose: e[3] || (e[3] = (l) => t(v).hide()),
            onEdit: R
          }, null, 8, ["name"])
        ]),
        _: 1
      }, 8, ["state"])
    ]));
  }
});
export {
  de as default
};
