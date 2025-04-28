var qt = Object.defineProperty;
var Jt = (s, a, t) => a in s ? qt(s, a, { enumerable: !0, configurable: !0, writable: !0, value: t }) : s[a] = t;
var x = (s, a, t) => Jt(s, typeof a != "symbol" ? a + "" : a, t);
import { ref as f, watchEffect as F, defineComponent as yt, computed as v, onMounted as Ft, watch as Kt, onBeforeUnmount as _t, openBlock as d, createElementBlock as p, normalizeClass as A, normalizeStyle as ct, unref as N, createBlock as X, resolveDynamicComponent as et, renderSlot as D, createCommentVNode as R, mergeProps as ft, Fragment as j, createElementVNode as L, normalizeProps as jt, createTextVNode as Vt, toDisplayString as dt, renderList as mt, useAttrs as te, nextTick as ee, withCtx as U, createVNode as K } from "vue";
function Zt(s) {
  if (!s || typeof document > "u") return;
  let a = document.head || document.getElementsByTagName("head")[0], t = document.createElement("style");
  t.type = "text/css", a.appendChild(t), t.styleSheet ? t.styleSheet.cssText = s : t.appendChild(document.createTextNode(s));
}
Zt(":where([data-sonner-toaster][dir=ltr]),:where(html[dir=ltr]){--toast-icon-margin-start:-3px;--toast-icon-margin-end:4px;--toast-svg-margin-start:-1px;--toast-svg-margin-end:0px;--toast-button-margin-start:auto;--toast-button-margin-end:0;--toast-close-button-start:0;--toast-close-button-end:unset;--toast-close-button-transform:translate(-35%, -35%)}:where([data-sonner-toaster][dir=rtl]),:where(html[dir=rtl]){--toast-icon-margin-start:4px;--toast-icon-margin-end:-3px;--toast-svg-margin-start:0px;--toast-svg-margin-end:-1px;--toast-button-margin-start:0;--toast-button-margin-end:auto;--toast-close-button-start:unset;--toast-close-button-end:0;--toast-close-button-transform:translate(35%, -35%)}:where([data-sonner-toaster]){position:fixed;width:var(--width);font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica Neue,Arial,Noto Sans,sans-serif,Apple Color Emoji,Segoe UI Emoji,Segoe UI Symbol,Noto Color Emoji;--gray1:hsl(0, 0%, 99%);--gray2:hsl(0, 0%, 97.3%);--gray3:hsl(0, 0%, 95.1%);--gray4:hsl(0, 0%, 93%);--gray5:hsl(0, 0%, 90.9%);--gray6:hsl(0, 0%, 88.7%);--gray7:hsl(0, 0%, 85.8%);--gray8:hsl(0, 0%, 78%);--gray9:hsl(0, 0%, 56.1%);--gray10:hsl(0, 0%, 52.3%);--gray11:hsl(0, 0%, 43.5%);--gray12:hsl(0, 0%, 9%);--border-radius:8px;box-sizing:border-box;padding:0;margin:0;list-style:none;outline:0;z-index:999999999;transition:transform .4s ease}:where([data-sonner-toaster][data-lifted=true]){transform:translateY(-10px)}@media (hover:none) and (pointer:coarse){:where([data-sonner-toaster][data-lifted=true]){transform:none}}:where([data-sonner-toaster][data-x-position=right]){right:max(var(--offset),env(safe-area-inset-right))}:where([data-sonner-toaster][data-x-position=left]){left:max(var(--offset),env(safe-area-inset-left))}:where([data-sonner-toaster][data-x-position=center]){left:50%;transform:translateX(-50%)}:where([data-sonner-toaster][data-y-position=top]){top:max(var(--offset),env(safe-area-inset-top))}:where([data-sonner-toaster][data-y-position=bottom]){bottom:max(var(--offset),env(safe-area-inset-bottom))}:where([data-sonner-toast]){--y:translateY(100%);--lift-amount:calc(var(--lift) * var(--gap));z-index:var(--z-index);position:absolute;opacity:0;transform:var(--y);filter:blur(0);touch-action:none;transition:transform .4s,opacity .4s,height .4s,box-shadow .2s;box-sizing:border-box;outline:0;overflow-wrap:anywhere}:where([data-sonner-toast][data-styled=true]){padding:16px;background:var(--normal-bg);border:1px solid var(--normal-border);color:var(--normal-text);border-radius:var(--border-radius);box-shadow:0 4px 12px rgba(0,0,0,.1);width:var(--width);font-size:13px;display:flex;align-items:center;gap:6px}:where([data-sonner-toast]:focus-visible){box-shadow:0 4px 12px rgba(0,0,0,.1),0 0 0 2px rgba(0,0,0,.2)}:where([data-sonner-toast][data-y-position=top]){top:0;--y:translateY(-100%);--lift:1;--lift-amount:calc(1 * var(--gap))}:where([data-sonner-toast][data-y-position=bottom]){bottom:0;--y:translateY(100%);--lift:-1;--lift-amount:calc(var(--lift) * var(--gap))}:where([data-sonner-toast]) :where([data-description]){font-weight:400;line-height:1.4;color:inherit}:where([data-sonner-toast]) :where([data-title]){font-weight:500;line-height:1.5;color:inherit}:where([data-sonner-toast]) :where([data-icon]){display:flex;height:16px;width:16px;position:relative;justify-content:flex-start;align-items:center;flex-shrink:0;margin-left:var(--toast-icon-margin-start);margin-right:var(--toast-icon-margin-end)}:where([data-sonner-toast][data-promise=true]) :where([data-icon])>svg{opacity:0;transform:scale(.8);transform-origin:center;animation:sonner-fade-in .3s ease forwards}:where([data-sonner-toast]) :where([data-icon])>*{flex-shrink:0}:where([data-sonner-toast]) :where([data-icon]) svg{margin-left:var(--toast-svg-margin-start);margin-right:var(--toast-svg-margin-end)}:where([data-sonner-toast]) :where([data-content]){display:flex;flex-direction:column;gap:2px}[data-sonner-toast][data-styled=true] [data-button]{border-radius:4px;padding-left:8px;padding-right:8px;height:24px;font-size:12px;color:var(--normal-bg);background:var(--normal-text);margin-left:var(--toast-button-margin-start);margin-right:var(--toast-button-margin-end);border:none;cursor:pointer;outline:0;display:flex;align-items:center;flex-shrink:0;transition:opacity .4s,box-shadow .2s}:where([data-sonner-toast]) :where([data-button]):focus-visible{box-shadow:0 0 0 2px rgba(0,0,0,.4)}:where([data-sonner-toast]) :where([data-button]):first-of-type{margin-left:var(--toast-button-margin-start);margin-right:var(--toast-button-margin-end)}:where([data-sonner-toast]) :where([data-cancel]){color:var(--normal-text);background:rgba(0,0,0,.08)}:where([data-sonner-toast][data-theme=dark]) :where([data-cancel]){background:rgba(255,255,255,.3)}[data-sonner-toast] [data-close-button]{position:absolute;left:var(--toast-close-button-start);right:var(--toast-close-button-end);top:0;height:20px;width:20px;display:flex;justify-content:center;align-items:center;padding:0;color:var(--gray12);border:1px solid var(--gray4);transform:var(--toast-close-button-transform);border-radius:50%;cursor:pointer;z-index:1;transition:opacity .1s,background .2s,border-color .2s}[data-sonner-toast] [data-close-button]{background:var(--gray1)}:where([data-sonner-toast]) :where([data-close-button]):focus-visible{box-shadow:0 4px 12px rgba(0,0,0,.1),0 0 0 2px rgba(0,0,0,.2)}:where([data-sonner-toast]) :where([data-disabled=true]){cursor:not-allowed}[data-sonner-toast]:hover [data-close-button]:hover{background:var(--gray2);border-color:var(--gray5)}:where([data-sonner-toast][data-swiping=true])::before{content:'';position:absolute;left:0;right:0;height:100%;z-index:-1}:where([data-sonner-toast][data-y-position=top][data-swiping=true])::before{bottom:50%;transform:scaleY(3) translateY(50%)}:where([data-sonner-toast][data-y-position=bottom][data-swiping=true])::before{top:50%;transform:scaleY(3) translateY(-50%)}:where([data-sonner-toast][data-swiping=false][data-removed=true])::before{content:'';position:absolute;inset:0;transform:scaleY(2)}:where([data-sonner-toast])::after{content:'';position:absolute;left:0;height:calc(var(--gap) + 1px);bottom:100%;width:100%}:where([data-sonner-toast][data-mounted=true]){--y:translateY(0);opacity:1}:where([data-sonner-toast][data-expanded=false][data-front=false]){--scale:var(--toasts-before) * 0.05 + 1;--y:translateY(calc(var(--lift-amount) * var(--toasts-before))) scale(calc(-1 * var(--scale)));height:var(--front-toast-height)}:where([data-sonner-toast])>*{transition:opacity .4s}:where([data-sonner-toast][data-expanded=false][data-front=false][data-styled=true])>*{opacity:0}:where([data-sonner-toast][data-visible=false]){opacity:0;pointer-events:none}:where([data-sonner-toast][data-mounted=true][data-expanded=true]){--y:translateY(calc(var(--lift) * var(--offset)));height:var(--initial-height)}:where([data-sonner-toast][data-removed=true][data-front=true][data-swipe-out=false]){--y:translateY(calc(var(--lift) * -100%));opacity:0}:where([data-sonner-toast][data-removed=true][data-front=false][data-swipe-out=false][data-expanded=true]){--y:translateY(calc(var(--lift) * var(--offset) + var(--lift) * -100%));opacity:0}:where([data-sonner-toast][data-removed=true][data-front=false][data-swipe-out=false][data-expanded=false]){--y:translateY(40%);opacity:0;transition:transform .5s,opacity .2s}:where([data-sonner-toast][data-removed=true][data-front=false])::before{height:calc(var(--initial-height) + 20%)}[data-sonner-toast][data-swiping=true]{transform:var(--y) translateY(var(--swipe-amount,0));transition:none}[data-sonner-toast][data-swiped=true]{user-select:none}[data-sonner-toast][data-swipe-out=true][data-y-position=bottom],[data-sonner-toast][data-swipe-out=true][data-y-position=top]{animation:swipe-out .2s ease-out forwards}@keyframes swipe-out{from{transform:translateY(calc(var(--lift) * var(--offset) + var(--swipe-amount)));opacity:1}to{transform:translateY(calc(var(--lift) * var(--offset) + var(--swipe-amount) + var(--lift) * -100%));opacity:0}}@media (max-width:600px){[data-sonner-toaster]{position:fixed;--mobile-offset:16px;right:var(--mobile-offset);left:var(--mobile-offset);width:100%}[data-sonner-toaster][dir=rtl]{left:calc(var(--mobile-offset) * -1)}[data-sonner-toaster] [data-sonner-toast]{left:0;right:0;width:calc(100% - var(--mobile-offset) * 2)}[data-sonner-toaster][data-x-position=left]{left:var(--mobile-offset)}[data-sonner-toaster][data-y-position=bottom]{bottom:20px}[data-sonner-toaster][data-y-position=top]{top:20px}[data-sonner-toaster][data-x-position=center]{left:var(--mobile-offset);right:var(--mobile-offset);transform:none}}[data-sonner-toaster][data-theme=light]{--normal-bg:#fff;--normal-border:var(--gray4);--normal-text:var(--gray12);--success-bg:hsl(143, 85%, 96%);--success-border:hsl(145, 92%, 91%);--success-text:hsl(140, 100%, 27%);--info-bg:hsl(208, 100%, 97%);--info-border:hsl(221, 91%, 91%);--info-text:hsl(210, 92%, 45%);--warning-bg:hsl(49, 100%, 97%);--warning-border:hsl(49, 91%, 91%);--warning-text:hsl(31, 92%, 45%);--error-bg:hsl(359, 100%, 97%);--error-border:hsl(359, 100%, 94%);--error-text:hsl(360, 100%, 45%)}[data-sonner-toaster][data-theme=light] [data-sonner-toast][data-invert=true]{--normal-bg:#000;--normal-border:hsl(0, 0%, 20%);--normal-text:var(--gray1)}[data-sonner-toaster][data-theme=dark] [data-sonner-toast][data-invert=true]{--normal-bg:#fff;--normal-border:var(--gray3);--normal-text:var(--gray12)}[data-sonner-toaster][data-theme=dark]{--normal-bg:#000;--normal-border:hsl(0, 0%, 20%);--normal-text:var(--gray1);--success-bg:hsl(150, 100%, 6%);--success-border:hsl(147, 100%, 12%);--success-text:hsl(150, 86%, 65%);--info-bg:hsl(215, 100%, 6%);--info-border:hsl(223, 100%, 12%);--info-text:hsl(216, 87%, 65%);--warning-bg:hsl(64, 100%, 6%);--warning-border:hsl(60, 100%, 12%);--warning-text:hsl(46, 87%, 65%);--error-bg:hsl(358, 76%, 10%);--error-border:hsl(357, 89%, 16%);--error-text:hsl(358, 100%, 81%)}[data-rich-colors=true][data-sonner-toast][data-type=success]{background:var(--success-bg);border-color:var(--success-border);color:var(--success-text)}[data-rich-colors=true][data-sonner-toast][data-type=success] [data-close-button]{background:var(--success-bg);border-color:var(--success-border);color:var(--success-text)}[data-rich-colors=true][data-sonner-toast][data-type=info]{background:var(--info-bg);border-color:var(--info-border);color:var(--info-text)}[data-rich-colors=true][data-sonner-toast][data-type=info] [data-close-button]{background:var(--info-bg);border-color:var(--info-border);color:var(--info-text)}[data-rich-colors=true][data-sonner-toast][data-type=warning]{background:var(--warning-bg);border-color:var(--warning-border);color:var(--warning-text)}[data-rich-colors=true][data-sonner-toast][data-type=warning] [data-close-button]{background:var(--warning-bg);border-color:var(--warning-border);color:var(--warning-text)}[data-rich-colors=true][data-sonner-toast][data-type=error]{background:var(--error-bg);border-color:var(--error-border);color:var(--error-text)}[data-rich-colors=true][data-sonner-toast][data-type=error] [data-close-button]{background:var(--error-bg);border-color:var(--error-border);color:var(--error-text)}.sonner-loading-wrapper{--size:16px;height:var(--size);width:var(--size);position:absolute;inset:0;z-index:10}.sonner-loading-wrapper[data-visible=false]{transform-origin:center;animation:sonner-fade-out .2s ease forwards}.sonner-spinner{position:relative;top:50%;left:50%;height:var(--size);width:var(--size)}.sonner-loading-bar{animation:sonner-spin 1.2s linear infinite;background:var(--gray11);border-radius:6px;height:8%;left:-10%;position:absolute;top:-3.9%;width:24%}.sonner-loading-bar:first-child{animation-delay:-1.2s;transform:rotate(.0001deg) translate(146%)}.sonner-loading-bar:nth-child(2){animation-delay:-1.1s;transform:rotate(30deg) translate(146%)}.sonner-loading-bar:nth-child(3){animation-delay:-1s;transform:rotate(60deg) translate(146%)}.sonner-loading-bar:nth-child(4){animation-delay:-.9s;transform:rotate(90deg) translate(146%)}.sonner-loading-bar:nth-child(5){animation-delay:-.8s;transform:rotate(120deg) translate(146%)}.sonner-loading-bar:nth-child(6){animation-delay:-.7s;transform:rotate(150deg) translate(146%)}.sonner-loading-bar:nth-child(7){animation-delay:-.6s;transform:rotate(180deg) translate(146%)}.sonner-loading-bar:nth-child(8){animation-delay:-.5s;transform:rotate(210deg) translate(146%)}.sonner-loading-bar:nth-child(9){animation-delay:-.4s;transform:rotate(240deg) translate(146%)}.sonner-loading-bar:nth-child(10){animation-delay:-.3s;transform:rotate(270deg) translate(146%)}.sonner-loading-bar:nth-child(11){animation-delay:-.2s;transform:rotate(300deg) translate(146%)}.sonner-loading-bar:nth-child(12){animation-delay:-.1s;transform:rotate(330deg) translate(146%)}@keyframes sonner-fade-in{0%{opacity:0;transform:scale(.8)}100%{opacity:1;transform:scale(1)}}@keyframes sonner-fade-out{0%{opacity:1;transform:scale(1)}100%{opacity:0;transform:scale(.8)}}@keyframes sonner-spin{0%{opacity:1}100%{opacity:.15}}@media (prefers-reduced-motion){.sonner-loading-bar,[data-sonner-toast],[data-sonner-toast]>*{transition:none!important;animation:none!important}}.sonner-loader{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);transform-origin:center;transition:opacity .2s,transform .2s}.sonner-loader[data-visible=false]{opacity:0;transform:scale(.8) translate(-50%,-50%)}");
let vt = 0;
class ae {
  constructor() {
    x(this, "subscribers");
    x(this, "toasts");
    // We use arrow functions to maintain the correct `this` reference
    x(this, "subscribe", (a) => (this.subscribers.push(a), () => {
      const t = this.subscribers.indexOf(a);
      this.subscribers.splice(t, 1);
    }));
    x(this, "publish", (a) => {
      this.subscribers.forEach((t) => t(a));
    });
    x(this, "addToast", (a) => {
      this.publish(a), this.toasts = [...this.toasts, a];
    });
    x(this, "create", (a) => {
      var P;
      const { message: t, ...i } = a, n = typeof a.id == "number" || a.id && ((P = a.id) == null ? void 0 : P.length) > 0 ? a.id : vt++, g = this.toasts.find((h) => h.id === n), T = a.dismissible === void 0 ? !0 : a.dismissible;
      return g ? this.toasts = this.toasts.map((h) => h.id === n ? (this.publish({ ...h, ...a, id: n, title: t }), {
        ...h,
        ...a,
        id: n,
        dismissible: T,
        title: t
      }) : h) : this.addToast({ title: t, ...i, dismissible: T, id: n }), n;
    });
    x(this, "dismiss", (a) => (a || this.toasts.forEach((t) => {
      this.subscribers.forEach(
        (i) => i({ id: t.id, dismiss: !0 })
      );
    }), this.subscribers.forEach((t) => t({ id: a, dismiss: !0 })), a));
    x(this, "message", (a, t) => this.create({ ...t, message: a, type: "default" }));
    x(this, "error", (a, t) => this.create({ ...t, type: "error", message: a }));
    x(this, "success", (a, t) => this.create({ ...t, type: "success", message: a }));
    x(this, "info", (a, t) => this.create({ ...t, type: "info", message: a }));
    x(this, "warning", (a, t) => this.create({ ...t, type: "warning", message: a }));
    x(this, "loading", (a, t) => this.create({ ...t, type: "loading", message: a }));
    x(this, "promise", (a, t) => {
      if (!t)
        return;
      let i;
      t.loading !== void 0 && (i = this.create({
        ...t,
        promise: a,
        type: "loading",
        message: t.loading,
        description: typeof t.description != "function" ? t.description : void 0
      }));
      const n = a instanceof Promise ? a : a();
      let g = i !== void 0, T;
      const P = n.then(async (u) => {
        if (T = ["resolve", u], se(u) && !u.ok) {
          g = !1;
          const m = typeof t.error == "function" ? await t.error(
            `HTTP error! status: ${u.status}`
          ) : t.error, y = typeof t.description == "function" ? (
            // @ts-expect-error
            await t.description(`HTTP error! status: ${u.status}`)
          ) : t.description;
          this.create({ id: i, type: "error", message: m, description: y });
        } else if (t.success !== void 0) {
          g = !1;
          const m = typeof t.success == "function" ? await t.success(u) : t.success, y = typeof t.description == "function" ? await t.description(u) : t.description;
          this.create({ id: i, type: "success", message: m, description: y });
        }
      }).catch(async (u) => {
        if (T = ["reject", u], t.error !== void 0) {
          g = !1;
          const m = typeof t.error == "function" ? await t.error(u) : t.error, y = typeof t.description == "function" ? await t.description(
            u
          ) : t.description;
          this.create({ id: i, type: "error", message: m, description: y });
        }
      }).finally(() => {
        var u;
        g && (this.dismiss(i), i = void 0), (u = t.finally) == null || u.call(t);
      }), h = () => new Promise(
        (u, m) => P.then(
          () => T[0] === "reject" ? m(T[1]) : u(T[1])
        ).catch(m)
      );
      return typeof i != "string" && typeof i != "number" ? { unwrap: h } : Object.assign(i, { unwrap: h });
    });
    // We can't provide the toast we just created as a prop as we didn't create it yet, so we can create a default toast object, I just don't know how to use function in argument when calling()?
    x(this, "custom", (a, t) => {
      const i = (t == null ? void 0 : t.id) || vt++;
      return this.publish({ component: a, id: i, ...t }), i;
    });
    this.subscribers = [], this.toasts = [];
  }
}
const I = new ae();
function oe(s, a) {
  const t = (a == null ? void 0 : a.id) || vt++;
  return I.create({
    message: s,
    id: t,
    type: "default",
    ...a
  }), t;
}
const se = (s) => s && typeof s == "object" && "ok" in s && typeof s.ok == "boolean" && "status" in s && typeof s.status == "number", ne = oe, re = () => I.toasts, Ke = Object.assign(
  ne,
  {
    success: I.success,
    info: I.info,
    warning: I.warning,
    error: I.error,
    custom: I.custom,
    message: I.message,
    promise: I.promise,
    dismiss: I.dismiss,
    loading: I.loading
  },
  {
    getHistory: re
  }
);
function ut(s) {
  return s.label !== void 0;
}
function ie() {
  const s = f(!1);
  return F(() => {
    const a = () => {
      s.value = document.hidden;
    };
    return document.addEventListener("visibilitychange", a), () => window.removeEventListener("visibilitychange", a);
  }), {
    isDocumentHidden: s
  };
}
function Xe() {
  const s = f([]);
  return F((a) => {
    const t = I.subscribe((i) => {
      if ("dismiss" in i && i.dismiss)
        return s.value.filter((g) => g.id !== i.id);
      const n = s.value.findIndex(
        (g) => g.id === i.id
      );
      if (n !== -1) {
        const g = [...s.value];
        g[n] = {
          ...g[n],
          ...i
        }, s.value = g;
      } else
        s.value = [i, ...s.value];
    });
    a(() => {
      t();
    });
  }), {
    activeToasts: s
  };
}
const le = ["aria-live", "data-rich-colors", "data-styled", "data-mounted", "data-promise", "data-removed", "data-visible", "data-y-position", "data-x-position", "data-index", "data-front", "data-swiping", "data-dismissible", "data-type", "data-invert", "data-swipe-out", "data-expanded"], de = ["aria-label", "data-disabled"], Wt = 4e3, ue = 20, ce = 200, fe = /* @__PURE__ */ yt({
  __name: "Toast",
  props: {
    toast: {},
    toasts: {},
    index: {},
    expanded: { type: Boolean },
    invert: { type: Boolean },
    heights: {},
    gap: {},
    position: {},
    visibleToasts: {},
    expandByDefault: { type: Boolean },
    closeButton: { type: Boolean },
    interacting: { type: Boolean },
    style: {},
    cancelButtonStyle: {},
    actionButtonStyle: {},
    duration: {},
    class: {},
    unstyled: { type: Boolean },
    descriptionClass: {},
    loadingIcon: {},
    classes: {},
    icons: {},
    closeButtonAriaLabel: {},
    pauseWhenPageIsHidden: { type: Boolean },
    cn: { type: Function },
    defaultRichColors: { type: Boolean }
  },
  emits: ["update:heights", "removeToast"],
  setup(s, { emit: a }) {
    const t = s, i = a, n = f(!1), g = f(!1), T = f(!1), P = f(!1), h = f(!1), u = f(0), m = f(0), y = f(
      t.toast.duration || t.duration || Wt
    ), H = f(null), B = f(null), pt = v(() => t.index === 0), ht = v(() => t.index + 1 <= t.visibleToasts), E = v(() => t.toast.type), Y = v(() => t.toast.dismissible !== !1), gt = v(() => t.toast.class || ""), o = v(() => t.descriptionClass || ""), r = t.toast.style || {}, l = v(
      () => t.heights.findIndex((e) => e.toastId === t.toast.id) || 0
    ), k = v(() => t.toast.closeButton ?? t.closeButton);
    v(
      () => t.toast.duration || t.duration || Wt
    );
    const b = f(0), z = f(0), O = f(null), G = v(() => t.position.split("-")), Q = v(() => G.value[0]), ot = v(() => G.value[1]), st = v(() => typeof t.toast.title != "string"), nt = v(
      () => typeof t.toast.description != "string"
    ), rt = v(() => t.heights.reduce((e, c, S) => S >= l.value ? e : e + c.height, 0)), it = ie(), lt = v(() => t.toast.invert || t.invert), V = v(() => E.value === "loading"), M = v(() => l.value * t.gap + rt.value || 0);
    Ft(() => {
      if (!n.value) return;
      const e = B.value, c = e == null ? void 0 : e.style.height;
      e.style.height = "auto";
      const S = e.getBoundingClientRect().height;
      e.style.height = c, m.value = S;
      let C;
      t.heights.find(
        (w) => w.toastId === t.toast.id
      ) ? C = t.heights.map(
        (w) => w.toastId === t.toast.id ? { ...w, height: S } : w
      ) : C = [
        {
          toastId: t.toast.id,
          height: S,
          position: t.toast.position
        },
        ...t.heights
      ], i("update:heights", C);
    });
    function W() {
      g.value = !0, u.value = M.value;
      const e = t.heights.filter(
        (c) => c.toastId !== t.toast.id
      );
      i("update:heights", e), setTimeout(() => {
        i("removeToast", t.toast);
      }, ce);
    }
    function bt() {
      var e, c;
      if (V.value || !Y.value)
        return {};
      W(), (c = (e = t.toast).onDismiss) == null || c.call(e, t.toast);
    }
    function Xt(e) {
      V.value || !Y.value || (H.value = /* @__PURE__ */ new Date(), u.value = M.value, e.target.setPointerCapture(e.pointerId), e.target.tagName !== "BUTTON" && (T.value = !0, O.value = { x: e.clientX, y: e.clientY }));
    }
    function Gt() {
      var C, $, w, q, J;
      if (P.value || !Y) return;
      O.value = null;
      const e = Number(
        ((C = B.value) == null ? void 0 : C.style.getPropertyValue("--swipe-amount").replace("px", "")) || 0
      ), c = (/* @__PURE__ */ new Date()).getTime() - (($ = H.value) == null ? void 0 : $.getTime()), S = Math.abs(e) / c;
      if (Math.abs(e) >= ue || S > 0.11) {
        u.value = M.value, (q = (w = t.toast).onDismiss) == null || q.call(w, t.toast), W(), P.value = !0, h.value = !1;
        return;
      }
      (J = B.value) == null || J.style.setProperty("--swipe-amount", "0px"), T.value = !1;
    }
    function Qt(e) {
      var $, w;
      if (!O.value || !Y.value) return;
      const c = e.clientY - O.value.y, S = (($ = window.getSelection()) == null ? void 0 : $.toString().length) > 0, C = Q.value === "top" ? Math.min(0, c) : Math.max(0, c);
      Math.abs(C) > 0 && (h.value = !0), !S && ((w = B.value) == null || w.style.setProperty("--swipe-amount", `${C}px`));
    }
    return F((e) => {
      if (t.toast.promise && E.value === "loading" || t.toast.duration === 1 / 0 || t.toast.type === "loading")
        return;
      let c;
      const S = () => {
        if (z.value < b.value) {
          const $ = (/* @__PURE__ */ new Date()).getTime() - b.value;
          y.value = y.value - $;
        }
        z.value = (/* @__PURE__ */ new Date()).getTime();
      }, C = () => {
        y.value !== 1 / 0 && (b.value = (/* @__PURE__ */ new Date()).getTime(), c = setTimeout(() => {
          var $, w;
          (w = ($ = t.toast).onAutoClose) == null || w.call($, t.toast), W();
        }, y.value));
      };
      t.expanded || t.interacting || t.pauseWhenPageIsHidden && it ? S() : C(), e(() => {
        clearTimeout(c);
      });
    }), Kt(
      () => t.toast.delete,
      () => {
        t.toast.delete && W();
      },
      {
        deep: !0
      }
    ), Ft(() => {
      if (n.value = !0, B.value) {
        const e = B.value.getBoundingClientRect().height;
        m.value = e;
        const c = [
          { toastId: t.toast.id, height: e, position: t.toast.position },
          ...t.heights
        ];
        i("update:heights", c);
      }
    }), _t(() => {
      if (B.value) {
        const e = t.heights.filter(
          (c) => c.toastId !== t.toast.id
        );
        i("update:heights", e);
      }
    }), (e, c) => {
      var S, C, $, w, q, J, wt, kt, xt, Tt, Bt, St, Ct, $t, It, Et, Pt, Dt, Ht, zt, Mt, Ot, At, Lt, Yt, Nt, Rt;
      return d(), p("li", {
        ref_key: "toastRef",
        ref: B,
        "aria-live": e.toast.important ? "assertive" : "polite",
        "aria-atomic": "true",
        role: "status",
        tabindex: "0",
        "data-sonner-toast": "true",
        class: A(
          e.cn(
            t.class,
            gt.value,
            (S = e.classes) == null ? void 0 : S.toast,
            (C = e.toast.classes) == null ? void 0 : C.toast,
            // @ts-ignore
            ($ = e.classes) == null ? void 0 : $[E.value],
            // @ts-ignore
            (q = (w = e.toast) == null ? void 0 : w.classes) == null ? void 0 : q[E.value]
          )
        ),
        "data-rich-colors": e.toast.richColors ?? e.defaultRichColors,
        "data-styled": !(e.toast.component || (J = e.toast) != null && J.unstyled || e.unstyled),
        "data-mounted": n.value,
        "data-promise": !!e.toast.promise,
        "data-removed": g.value,
        "data-visible": ht.value,
        "data-y-position": Q.value,
        "data-x-position": ot.value,
        "data-index": e.index,
        "data-front": pt.value,
        "data-swiping": T.value,
        "data-dismissible": Y.value,
        "data-type": E.value,
        "data-invert": lt.value,
        "data-swipe-out": P.value,
        "data-expanded": !!(e.expanded || e.expandByDefault && n.value),
        style: ct({
          "--index": e.index,
          "--toasts-before": e.index,
          "--z-index": e.toasts.length - e.index,
          "--offset": `${g.value ? u.value : M.value}px`,
          "--initial-height": e.expandByDefault ? "auto" : `${m.value}px`,
          ...e.style,
          ...N(r)
        }),
        onPointerdown: Xt,
        onPointerup: Gt,
        onPointermove: Qt
      }, [
        k.value && !e.toast.component ? (d(), p("button", {
          key: 0,
          "aria-label": e.closeButtonAriaLabel || "Close toast",
          "data-disabled": V.value,
          "data-close-button": "true",
          class: A(e.cn((wt = e.classes) == null ? void 0 : wt.closeButton, (xt = (kt = e.toast) == null ? void 0 : kt.classes) == null ? void 0 : xt.closeButton)),
          onClick: bt
        }, [
          (Tt = e.icons) != null && Tt.close ? (d(), X(et((Bt = e.icons) == null ? void 0 : Bt.close), { key: 0 })) : D(e.$slots, "close-icon", { key: 1 })
        ], 10, de)) : R("", !0),
        e.toast.component ? (d(), X(et(e.toast.component), ft({ key: 1 }, e.toast.componentProps, { onCloseToast: bt }), null, 16)) : (d(), p(j, { key: 2 }, [
          E.value !== "default" || e.toast.icon || e.toast.promise ? (d(), p("div", {
            key: 0,
            "data-icon": "",
            class: A(e.cn((St = e.classes) == null ? void 0 : St.icon, ($t = (Ct = e.toast) == null ? void 0 : Ct.classes) == null ? void 0 : $t.icon))
          }, [
            (e.toast.promise || E.value === "loading") && !e.toast.icon ? D(e.$slots, "loading-icon", { key: 0 }) : R("", !0),
            e.toast.icon ? (d(), X(et(e.toast.icon), { key: 1 })) : (d(), p(j, { key: 2 }, [
              E.value === "success" ? D(e.$slots, "success-icon", { key: 0 }) : E.value === "error" ? D(e.$slots, "error-icon", { key: 1 }) : E.value === "warning" ? D(e.$slots, "warning-icon", { key: 2 }) : E.value === "info" ? D(e.$slots, "info-icon", { key: 3 }) : R("", !0)
            ], 64))
          ], 2)) : R("", !0),
          L("div", {
            "data-content": "",
            class: A(e.cn((It = e.classes) == null ? void 0 : It.content, (Pt = (Et = e.toast) == null ? void 0 : Et.classes) == null ? void 0 : Pt.content))
          }, [
            L("div", {
              "data-title": "",
              class: A(e.cn((Dt = e.classes) == null ? void 0 : Dt.title, (Ht = e.toast.classes) == null ? void 0 : Ht.title))
            }, [
              st.value ? (d(), X(et(e.toast.title), jt(ft({ key: 0 }, e.toast.componentProps)), null, 16)) : (d(), p(j, { key: 1 }, [
                Vt(dt(e.toast.title), 1)
              ], 64))
            ], 2),
            e.toast.description ? (d(), p("div", {
              key: 0,
              "data-description": "",
              class: A(
                e.cn(
                  e.descriptionClass,
                  o.value,
                  (zt = e.classes) == null ? void 0 : zt.description,
                  (Mt = e.toast.classes) == null ? void 0 : Mt.description
                )
              )
            }, [
              nt.value ? (d(), X(et(e.toast.description), jt(ft({ key: 0 }, e.toast.componentProps)), null, 16)) : (d(), p(j, { key: 1 }, [
                Vt(dt(e.toast.description), 1)
              ], 64))
            ], 2)) : R("", !0)
          ], 2),
          e.toast.cancel ? (d(), p("button", {
            key: 1,
            style: ct(e.toast.cancelButtonStyle || e.cancelButtonStyle),
            class: A(e.cn((Ot = e.classes) == null ? void 0 : Ot.cancelButton, (At = e.toast.classes) == null ? void 0 : At.cancelButton)),
            "data-button": "",
            "data-cancel": "",
            onClick: c[0] || (c[0] = (Z) => {
              var _, tt;
              N(ut)(e.toast.cancel) && Y.value && ((tt = (_ = e.toast.cancel).onClick) == null || tt.call(_, Z), W());
            })
          }, dt(N(ut)(e.toast.cancel) ? (Lt = e.toast.cancel) == null ? void 0 : Lt.label : e.toast.cancel), 7)) : R("", !0),
          e.toast.action ? (d(), p("button", {
            key: 2,
            style: ct(e.toast.actionButtonStyle || e.actionButtonStyle),
            class: A(e.cn((Yt = e.classes) == null ? void 0 : Yt.actionButton, (Nt = e.toast.classes) == null ? void 0 : Nt.actionButton)),
            "data-button": "",
            "data-action": "",
            onClick: c[1] || (c[1] = (Z) => {
              var _, tt;
              N(ut)(e.toast.action) && (Z.defaultPrevented || ((tt = (_ = e.toast.action).onClick) == null || tt.call(_, Z), !Z.defaultPrevented && W()));
            })
          }, dt(N(ut)(e.toast.action) ? (Rt = e.toast.action) == null ? void 0 : Rt.label : e.toast.action), 7)) : R("", !0)
        ], 64))
      ], 46, le);
    };
  }
}), at = (s, a) => {
  const t = s.__vccOpts || s;
  for (const [i, n] of a)
    t[i] = n;
  return t;
}, pe = {}, he = {
  xmlns: "http://www.w3.org/2000/svg",
  width: "12",
  height: "12",
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  "stoke-width": "1.5",
  "stroke-linecap": "round",
  "stroke-linejoin": "round"
};
function ge(s, a) {
  return d(), p("svg", he, a[0] || (a[0] = [
    L("line", {
      x1: "18",
      y1: "6",
      x2: "6",
      y2: "18"
    }, null, -1),
    L("line", {
      x1: "6",
      y1: "6",
      x2: "18",
      y2: "18"
    }, null, -1)
  ]));
}
const me = /* @__PURE__ */ at(pe, [["render", ge]]), ve = ["data-visible"], ye = { class: "sonner-spinner" }, be = /* @__PURE__ */ yt({
  __name: "Loader",
  props: {
    visible: { type: Boolean }
  },
  setup(s) {
    const a = Array(12).fill(0);
    return (t, i) => (d(), p("div", {
      class: "sonner-loading-wrapper",
      "data-visible": t.visible
    }, [
      L("div", ye, [
        (d(!0), p(j, null, mt(N(a), (n) => (d(), p("div", {
          key: `spinner-bar-${n}`,
          class: "sonner-loading-bar"
        }))), 128))
      ])
    ], 8, ve));
  }
}), we = {}, ke = {
  xmlns: "http://www.w3.org/2000/svg",
  viewBox: "0 0 20 20",
  fill: "currentColor",
  height: "20",
  width: "20"
};
function xe(s, a) {
  return d(), p("svg", ke, a[0] || (a[0] = [
    L("path", {
      "fill-rule": "evenodd",
      d: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z",
      "clip-rule": "evenodd"
    }, null, -1)
  ]));
}
const Te = /* @__PURE__ */ at(we, [["render", xe]]), Be = {}, Se = {
  xmlns: "http://www.w3.org/2000/svg",
  viewBox: "0 0 20 20",
  fill: "currentColor",
  height: "20",
  width: "20"
};
function Ce(s, a) {
  return d(), p("svg", Se, a[0] || (a[0] = [
    L("path", {
      "fill-rule": "evenodd",
      d: "M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z",
      "clip-rule": "evenodd"
    }, null, -1)
  ]));
}
const $e = /* @__PURE__ */ at(Be, [["render", Ce]]), Ie = {}, Ee = {
  xmlns: "http://www.w3.org/2000/svg",
  viewBox: "0 0 24 24",
  fill: "currentColor",
  height: "20",
  width: "20"
};
function Pe(s, a) {
  return d(), p("svg", Ee, a[0] || (a[0] = [
    L("path", {
      "fill-rule": "evenodd",
      d: "M9.401 3.003c1.155-2 4.043-2 5.197 0l7.355 12.748c1.154 2-.29 4.5-2.599 4.5H4.645c-2.309 0-3.752-2.5-2.598-4.5L9.4 3.003zM12 8.25a.75.75 0 01.75.75v3.75a.75.75 0 01-1.5 0V9a.75.75 0 01.75-.75zm0 8.25a.75.75 0 100-1.5.75.75 0 000 1.5z",
      "clip-rule": "evenodd"
    }, null, -1)
  ]));
}
const De = /* @__PURE__ */ at(Ie, [["render", Pe]]), He = {}, ze = {
  xmlns: "http://www.w3.org/2000/svg",
  viewBox: "0 0 20 20",
  fill: "currentColor",
  height: "20",
  width: "20"
};
function Me(s, a) {
  return d(), p("svg", ze, a[0] || (a[0] = [
    L("path", {
      "fill-rule": "evenodd",
      d: "M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-5a.75.75 0 01.75.75v4.5a.75.75 0 01-1.5 0v-4.5A.75.75 0 0110 5zm0 10a1 1 0 100-2 1 1 0 000 2z",
      "clip-rule": "evenodd"
    }, null, -1)
  ]));
}
const Oe = /* @__PURE__ */ at(He, [["render", Me]]), Ae = ["aria-label"], Le = ["dir", "data-theme", "data-rich-colors", "data-y-position", "data-x-position", "data-lifted"], Ye = 3, Ut = "32px", Ne = 356, Re = 14, Fe = typeof window < "u" && typeof document < "u";
function je(...s) {
  return s.filter(Boolean).join(" ");
}
const Ve = /* @__PURE__ */ yt({
  name: "Toaster",
  inheritAttrs: !1,
  __name: "Toaster",
  props: {
    invert: { type: Boolean, default: !1 },
    theme: { default: "light" },
    position: { default: "bottom-right" },
    hotkey: { default: () => ["altKey", "KeyT"] },
    richColors: { type: Boolean, default: !1 },
    expand: { type: Boolean, default: !1 },
    duration: {},
    gap: { default: Re },
    visibleToasts: { default: Ye },
    closeButton: { type: Boolean, default: !1 },
    toastOptions: { default: () => ({}) },
    class: { default: "" },
    style: { default: () => ({}) },
    offset: { default: Ut },
    dir: { default: "auto" },
    icons: {},
    containerAriaLabel: { default: "Notifications" },
    pauseWhenPageIsHidden: { type: Boolean, default: !1 },
    cn: { type: Function, default: je }
  },
  setup(s) {
    const a = s;
    function t() {
      if (typeof window > "u" || typeof document > "u") return "ltr";
      const o = document.documentElement.getAttribute("dir");
      return o === "auto" || !o ? window.getComputedStyle(document.documentElement).direction : o;
    }
    const i = te(), n = f([]), g = v(() => (o, r) => n.value.filter(
      (l) => !l.position && r === 0 || l.position === o
    )), T = v(() => {
      const o = n.value.filter((r) => r.position).map((r) => r.position);
      return o.length > 0 ? Array.from(new Set([a.position].concat(o))) : [a.position];
    }), P = f([]), h = f(!1), u = f(!1), m = f(
      a.theme !== "system" ? a.theme : typeof window < "u" && window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
    ), y = f(null), H = f(null), B = f(!1), pt = a.hotkey.join("+").replace(/Key/g, "").replace(/Digit/g, "");
    function ht(o) {
      var r;
      (r = n.value.find((l) => l.id === o.id)) != null && r.delete || I.dismiss(o.id), n.value = n.value.filter(({ id: l }) => l !== o.id);
    }
    function E(o) {
      var r, l;
      B.value && !((l = (r = o.currentTarget) == null ? void 0 : r.contains) != null && l.call(r, o.relatedTarget)) && (B.value = !1, H.value && (H.value.focus({ preventScroll: !0 }), H.value = null));
    }
    function Y(o) {
      o.target instanceof HTMLElement && o.target.dataset.dismissible === "false" || B.value || (B.value = !0, H.value = o.relatedTarget);
    }
    function gt(o) {
      o.target && o.target instanceof HTMLElement && o.target.dataset.dismissible === "false" || (u.value = !0);
    }
    return F((o) => {
      const r = I.subscribe((l) => {
        if (l.dismiss) {
          n.value = n.value.map(
            (k) => k.id === l.id ? { ...k, delete: !0 } : k
          );
          return;
        }
        ee(() => {
          const k = n.value.findIndex(
            (b) => b.id === l.id
          );
          k !== -1 ? n.value = [
            ...n.value.slice(0, k),
            { ...n.value[k], ...l },
            ...n.value.slice(k + 1)
          ] : n.value = [l, ...n.value];
        });
      });
      o(r);
    }), Kt(
      () => a.theme,
      (o) => {
        if (o !== "system") {
          m.value = o;
          return;
        }
        if (o === "system" && (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? m.value = "dark" : m.value = "light"), typeof window > "u") return;
        const r = window.matchMedia("(prefers-color-scheme: dark)");
        try {
          r.addEventListener("change", ({ matches: l }) => {
            l ? m.value = "dark" : m.value = "light";
          });
        } catch {
          r.addListener(({ matches: k }) => {
            try {
              k ? m.value = "dark" : m.value = "light";
            } catch (b) {
              console.error(b);
            }
          });
        }
      }
    ), F(() => {
      y.value && H.value && (H.value.focus({ preventScroll: !0 }), H.value = null, B.value = !1);
    }), F(() => {
      n.value.length <= 1 && (h.value = !1);
    }), F((o) => {
      function r(l) {
        const k = a.hotkey.every(
          (O) => l[O] || l.code === O
        ), b = Array.isArray(y.value) ? y.value[0] : y.value;
        k && (h.value = !0, b == null || b.focus());
        const z = document.activeElement === y.value || (b == null ? void 0 : b.contains(document.activeElement));
        l.code === "Escape" && z && (h.value = !1);
      }
      Fe && (document.addEventListener("keydown", r), o(() => {
        document.removeEventListener("keydown", r);
      }));
    }), (o, r) => (d(), p("section", {
      "aria-label": `${o.containerAriaLabel} ${N(pt)}`,
      tabIndex: -1,
      "aria-live": "polite",
      "aria-relevant": "additions text",
      "aria-atomic": "false"
    }, [
      (d(!0), p(j, null, mt(T.value, (l, k) => {
        var b;
        return d(), p("ol", ft({
          key: l,
          ref_for: !0,
          ref_key: "listRef",
          ref: y,
          "data-sonner-toaster": "",
          class: a.class,
          dir: o.dir === "auto" ? t() : o.dir,
          tabIndex: -1,
          "data-theme": o.theme,
          "data-rich-colors": o.richColors,
          "data-y-position": l.split("-")[0],
          "data-x-position": l.split("-")[1],
          "data-lifted": h.value && n.value.length > 1 && !o.expand,
          style: {
            "--front-toast-height": `${(b = P.value[0]) == null ? void 0 : b.height}px`,
            "--offset": typeof o.offset == "number" ? `${o.offset}px` : o.offset || Ut,
            "--width": `${Ne}px`,
            "--gap": `${o.gap}px`,
            ...o.style,
            ...N(i).style
          }
        }, o.$attrs, {
          onBlur: E,
          onFocus: Y,
          onMouseenter: r[1] || (r[1] = () => h.value = !0),
          onMousemove: r[2] || (r[2] = () => h.value = !0),
          onMouseleave: r[3] || (r[3] = () => {
            u.value || (h.value = !1);
          }),
          onPointerdown: gt,
          onPointerup: r[4] || (r[4] = () => u.value = !1)
        }), [
          (d(!0), p(j, null, mt(g.value(l, k), (z, O) => {
            var G, Q, ot, st, nt, rt, it, lt, V;
            return d(), X(fe, {
              key: z.id,
              heights: P.value.filter((M) => M.position === z.position),
              icons: o.icons,
              index: O,
              toast: z,
              defaultRichColors: o.richColors,
              duration: ((G = o.toastOptions) == null ? void 0 : G.duration) ?? o.duration,
              class: A(((Q = o.toastOptions) == null ? void 0 : Q.class) ?? ""),
              descriptionClass: (ot = o.toastOptions) == null ? void 0 : ot.descriptionClass,
              invert: o.invert,
              visibleToasts: o.visibleToasts,
              closeButton: ((st = o.toastOptions) == null ? void 0 : st.closeButton) ?? o.closeButton,
              interacting: u.value,
              position: l,
              style: ct((nt = o.toastOptions) == null ? void 0 : nt.style),
              unstyled: (rt = o.toastOptions) == null ? void 0 : rt.unstyled,
              classes: (it = o.toastOptions) == null ? void 0 : it.classes,
              cancelButtonStyle: (lt = o.toastOptions) == null ? void 0 : lt.cancelButtonStyle,
              actionButtonStyle: (V = o.toastOptions) == null ? void 0 : V.actionButtonStyle,
              toasts: n.value.filter((M) => M.position === z.position),
              expandByDefault: o.expand,
              gap: o.gap,
              expanded: h.value,
              pauseWhenPageIsHidden: o.pauseWhenPageIsHidden,
              cn: o.cn,
              "onUpdate:heights": r[0] || (r[0] = (M) => {
                P.value = M;
              }),
              onRemoveToast: ht
            }, {
              "close-icon": U(() => [
                D(o.$slots, "close-icon", {}, () => [
                  K(me)
                ])
              ]),
              "loading-icon": U(() => [
                D(o.$slots, "loading-icon", {}, () => [
                  K(be, {
                    visible: z.type === "loading"
                  }, null, 8, ["visible"])
                ])
              ]),
              "success-icon": U(() => [
                D(o.$slots, "success-icon", {}, () => [
                  K(Te)
                ])
              ]),
              "error-icon": U(() => [
                D(o.$slots, "error-icon", {}, () => [
                  K(Oe)
                ])
              ]),
              "warning-icon": U(() => [
                D(o.$slots, "warning-icon", {}, () => [
                  K(De)
                ])
              ]),
              "info-icon": U(() => [
                D(o.$slots, "info-icon", {}, () => [
                  K($e)
                ])
              ]),
              _: 2
            }, 1032, ["heights", "icons", "index", "toast", "defaultRichColors", "duration", "class", "descriptionClass", "invert", "visibleToasts", "closeButton", "interacting", "position", "style", "unstyled", "classes", "cancelButtonStyle", "actionButtonStyle", "toasts", "expandByDefault", "gap", "expanded", "pauseWhenPageIsHidden", "cn"]);
          }), 128))
        ], 16, Le);
      }), 128))
    ], 8, Ae));
  }
}), Ge = {
  install(s) {
    s.component("Toaster", Ve);
  }
};
export {
  Ve as Toaster,
  Ge as default,
  Ke as toast,
  Xe as useVueSonner
};
//# sourceMappingURL=vue-sonner.js.map
