import { defineComponent as P, openBlock as d, createElementBlock as S, createElementVNode as r, createVNode as c, withCtx as n, createTextVNode as a, unref as e, normalizeClass as f, createBlock as m, createCommentVNode as b, toDisplayString as z, Fragment as B, renderList as A, normalizeStyle as $ } from "vue";
import { cva as R, ScalarButton as y, cx as v, ScalarIcon as h } from "@scalar/components";
import { themeLabels as E } from "@scalar/themes";
import V from "../../components/ImportCollection/IntegrationLogo.vue.js";
import { useActiveEntities as W } from "../../store/active-entities.js";
import F from "./components/SettingsAppearance.vue.js";
import C from "./components/SettingsSection.vue.js";
import { useWorkspace as O } from "../../store/store.js";
const D = { class: "bg-b-1 h-full w-full overflow-auto" }, G = { class: "ml-auto mr-auto w-full max-w-[720px] px-5 py-5" }, q = { class: "flex flex-col gap-8" }, H = { class: "flex flex-col gap-2" }, M = { class: "flex flex-col gap-2" }, X = { class: "grid grid-cols-2 gap-2" }, Y = { class: "flex items-center gap-2" }, J = { class: "flex items-center gap-1" }, K = { class: "grid grid-cols-2 gap-2" }, Q = { class: "flex items-center gap-2" }, Z = { class: "flex items-center gap-1" }, I = { class: "size-7 rounded-xl" }, w = "https://proxy.scalar.com", ce = /* @__PURE__ */ P({
  __name: "SettingsGeneral",
  setup(ee) {
    const { activeWorkspace: o } = W(), { proxyUrl: k, workspaceMutators: j } = O(), L = [
      "default",
      "alternate",
      // 'moon',
      "purple",
      "solarized",
      // 'bluePlanet',
      "saturn",
      "kepler"
      // 'mars',
      // 'deepSpace',
    ], N = ["elysiajs", "fastify"], _ = (x) => ({
      default: { light: "#fff", dark: "#0f0f0f", accent: "#0099ff" },
      alternate: { light: "#f9f9f9", dark: "#131313", accent: "#e7e7e7" },
      moon: { light: "#ccc9b3", dark: "#313332", accent: "#645b0f" },
      purple: { light: "#f5f6f8", dark: "#22252b", accent: "#5469d4" },
      solarized: { light: "#fdf6e3", dark: "#00212b", accent: "#007acc" },
      bluePlanet: { light: "#f0f2f5", dark: "#000e23", accent: "#e0e2e6" },
      saturn: { light: "#e4e4df", dark: "#2c2c30", accent: "#1763a6" },
      kepler: { light: "#f6f6f6", dark: "#0d0f1e", accent: "#7070ff" },
      mars: { light: "#f2efe8", dark: "#321116", accent: "#c75549" },
      deepSpace: { light: "#f4f4f5", dark: "#09090b", accent: "#8ab4f8" },
      none: { light: "#ffffff", dark: "#000000", accent: "#3b82f6" }
    })[x] || { light: "#ffffff", dark: "#000000", accent: "#3b82f6" }, T = (x) => {
      var t;
      return j.edit((t = o.value) == null ? void 0 : t.uid, "themeId", x);
    }, g = R({
      base: "w-full shadow-none text-c-1 justify-start pl-2 gap-2 border-1/2",
      variants: {
        active: {
          true: "bg-primary text-c-1 hover:bg-inherit",
          false: "bg-b-1 hover:bg-b-2"
        }
      }
    }), U = (x) => {
      var t;
      return j.edit((t = o.value) == null ? void 0 : t.uid, "proxyUrl", x);
    };
    return (x, t) => (d(), S("div", D, [
      r("div", G, [
        r("div", q, [
          t[13] || (t[13] = r("div", null, [
            r("h2", { class: "mt-10 text-xl font-bold" }, "Settings")
          ], -1)),
          c(C, null, {
            title: n(() => t[3] || (t[3] = [
              a(" CORS Proxy ")
            ])),
            description: n(() => t[4] || (t[4] = [
              a(" Browsers block cross-origin requests for security. We provide a public proxy to "),
              r("a", {
                class: "hover:text-c-1 underline-offset-2",
                href: "https://en.wikipedia.org/wiki/Cross-origin_resource_sharing",
                target: "_blank"
              }, " bypass CORS issues ", -1),
              a(" . Check the "),
              r("a", {
                class: "hover:text-c-1 underline-offset-2",
                href: "https://github.com/scalar/scalar/tree/main/examples/proxy-server",
                target: "_blank"
              }, " source code on GitHub ", -1),
              a(" . ")
            ])),
            default: n(() => {
              var s, u, i;
              return [
                r("div", H, [
                  c(e(y), {
                    class: f(
                      e(v)(
                        e(g)({
                          active: ((s = e(o)) == null ? void 0 : s.proxyUrl) === w
                        })
                      )
                    ),
                    onClick: t[0] || (t[0] = (l) => U(w))
                  }, {
                    default: n(() => {
                      var l, p;
                      return [
                        r("div", {
                          class: f(["flex h-5 w-5 items-center justify-center rounded-full border-[1.5px] p-1", {
                            "bg-c-accent text-b-1 border-transparent": ((l = e(o)) == null ? void 0 : l.proxyUrl) === w
                          }])
                        }, [
                          ((p = e(o)) == null ? void 0 : p.proxyUrl) === w ? (d(), m(e(h), {
                            key: 0,
                            icon: "Checkmark",
                            size: "xs",
                            thickness: "3.5"
                          })) : b("", !0)
                        ], 2),
                        t[5] || (t[5] = a(" Use proxy.scalar.com (default) "))
                      ];
                    }),
                    _: 1
                  }, 8, ["class"]),
                  e(k) && e(k) !== w ? (d(), m(e(y), {
                    key: 0,
                    class: f(
                      e(v)(
                        e(g)({
                          active: ((u = e(o)) == null ? void 0 : u.proxyUrl) === e(k)
                        })
                      )
                    ),
                    onClick: t[1] || (t[1] = (l) => U(e(k)))
                  }, {
                    default: n(() => {
                      var l, p;
                      return [
                        r("div", {
                          class: f(["flex h-5 w-5 items-center justify-center rounded-full border-[1.5px] p-1", {
                            "bg-c-accent text-b-1 border-transparent": ((l = e(o)) == null ? void 0 : l.proxyUrl) === e(k)
                          }])
                        }, [
                          ((p = e(o)) == null ? void 0 : p.proxyUrl) === e(k) ? (d(), m(e(h), {
                            key: 0,
                            icon: "Checkmark",
                            size: "xs",
                            thickness: "3.5"
                          })) : b("", !0)
                        ], 2),
                        a(" Use custom proxy (" + z(e(k)) + ") ", 1)
                      ];
                    }),
                    _: 1
                  }, 8, ["class"])) : b("", !0),
                  c(e(y), {
                    class: f(e(v)(e(g)({ active: !((i = e(o)) != null && i.proxyUrl) }))),
                    onClick: t[2] || (t[2] = (l) => U(void 0))
                  }, {
                    default: n(() => {
                      var l, p;
                      return [
                        r("div", {
                          class: f([
                            "flex h-5 w-5 items-center justify-center rounded-full border-[1.5px] p-1",
                            !((l = e(o)) != null && l.proxyUrl) && "bg-c-accent text-b-1 border-transparent"
                          ])
                        }, [
                          (p = e(o)) != null && p.proxyUrl ? b("", !0) : (d(), m(e(h), {
                            key: 0,
                            icon: "Checkmark",
                            size: "xs",
                            thickness: "3.5"
                          }))
                        ], 2),
                        t[6] || (t[6] = a(" Skip the proxy "))
                      ];
                    }),
                    _: 1
                  }, 8, ["class"])
                ])
              ];
            }),
            _: 1
          }),
          c(C, null, {
            title: n(() => t[7] || (t[7] = [
              a(" Themes ")
            ])),
            description: n(() => t[8] || (t[8] = [
              a(" We’ve got a whole rainbow of themes for you to play with: ")
            ])),
            default: n(() => [
              r("div", M, [
                r("div", X, [
                  (d(), S(B, null, A(L, (s) => {
                    var u;
                    return c(e(y), {
                      key: s,
                      class: f(
                        e(v)(
                          e(g)({
                            active: ((u = e(o)) == null ? void 0 : u.themeId) === s
                          })
                        )
                      ),
                      onClick: (i) => T(s)
                    }, {
                      default: n(() => {
                        var i, l;
                        return [
                          r("div", Y, [
                            r("div", {
                              class: f(["flex h-5 w-5 items-center justify-center rounded-full border-[1.5px] p-1", {
                                "bg-c-accent text-b-1 border-transparent": ((i = e(o)) == null ? void 0 : i.themeId) === s
                              }])
                            }, [
                              ((l = e(o)) == null ? void 0 : l.themeId) === s ? (d(), m(e(h), {
                                key: 0,
                                icon: "Checkmark",
                                size: "xs",
                                thickness: "3.5"
                              })) : b("", !0)
                            ], 2),
                            a(" " + z(e(E)[s]), 1)
                          ]),
                          r("div", J, [
                            r("span", {
                              class: "border-c-3 -mr-3 inline-block h-5 w-5 rounded-full",
                              style: $({
                                backgroundColor: _(s).light
                              })
                            }, null, 4),
                            r("span", {
                              class: "border-c-3 -mr-3 inline-block h-5 w-5 rounded-full",
                              style: $({
                                backgroundColor: _(s).dark
                              })
                            }, null, 4),
                            r("span", {
                              class: "border-c-3 inline-block h-5 w-5 rounded-full",
                              style: $({
                                backgroundColor: _(s).accent
                              })
                            }, null, 4)
                          ])
                        ];
                      }),
                      _: 2
                    }, 1032, ["class", "onClick"]);
                  }), 64))
                ])
              ])
            ]),
            _: 1
          }),
          c(C, null, {
            title: n(() => t[9] || (t[9] = [
              a(" Framework Themes ")
            ])),
            description: n(() => t[10] || (t[10] = [
              a(" Are you a real fan? Show your support by using your favorite framework’s theme! ")
            ])),
            default: n(() => [
              r("div", K, [
                (d(), S(B, null, A(N, (s) => {
                  var u;
                  return c(e(y), {
                    key: s,
                    class: f(
                      e(v)(
                        e(g)({
                          active: ((u = e(o)) == null ? void 0 : u.themeId) === s
                        })
                      )
                    ),
                    onClick: (i) => T(s)
                  }, {
                    default: n(() => {
                      var i, l;
                      return [
                        r("div", Q, [
                          r("div", {
                            class: f(["flex h-5 w-5 items-center justify-center rounded-full border-[1.5px] p-1", {
                              "bg-c-accent text-b-1 border-transparent": ((i = e(o)) == null ? void 0 : i.themeId) === s
                            }])
                          }, [
                            ((l = e(o)) == null ? void 0 : l.themeId) === s ? (d(), m(e(h), {
                              key: 0,
                              icon: "Checkmark",
                              size: "xs",
                              thickness: "3.5"
                            })) : b("", !0)
                          ], 2),
                          a(" " + z(e(E)[s]), 1)
                        ]),
                        r("div", Z, [
                          r("div", I, [
                            c(V, { integration: s }, null, 8, ["integration"])
                          ])
                        ])
                      ];
                    }),
                    _: 2
                  }, 1032, ["class", "onClick"]);
                }), 64))
              ])
            ]),
            _: 1
          }),
          c(C, null, {
            title: n(() => t[11] || (t[11] = [
              a(" Appearance ")
            ])),
            description: n(() => t[12] || (t[12] = [
              a(" Choose between light, dark, or system-based appearance for your workspace. ")
            ])),
            default: n(() => [
              c(F)
            ]),
            _: 1
          })
        ])
      ])
    ]));
  }
});
export {
  ce as default
};
