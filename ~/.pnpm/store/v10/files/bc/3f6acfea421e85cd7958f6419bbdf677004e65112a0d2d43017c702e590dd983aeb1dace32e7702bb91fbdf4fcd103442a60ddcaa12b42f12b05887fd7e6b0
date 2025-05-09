import * as No from "vue";
import { inject as ul, provide as dl, shallowRef as Fn, watchEffect as Ce, readonly as Wa, customRef as cl, ref as T, computed as B, watch as ee, nextTick as oe, getCurrentScope as gr, onScopeDispose as fl, effectScope as pl, unref as o, onBeforeUnmount as Nn, onMounted as le, isRef as et, reactive as Fa, getCurrentInstance as gt, onUpdated as vl, Fragment as _e, defineComponent as x, toRefs as ae, renderSlot as w, onBeforeUpdate as br, toHandlerKey as Cr, camelize as ml, toRef as wr, onUnmounted as Be, mergeProps as k, h as mt, Comment as hl, cloneVNode as Ln, openBlock as b, createBlock as S, withCtx as y, createVNode as q, createCommentVNode as ce, withKeys as ie, Teleport as qt, normalizeProps as W, guardReactiveProps as U, normalizeStyle as Me, withModifiers as ue, createElementBlock as ve, withDirectives as ja, vShow as zn, createElementVNode as Ye, toDisplayString as De, createTextVNode as ye, mergeDefaults as yl, watchPostEffect as _r, renderList as ma, markRaw as xr, watchSyncEffect as Sr, resolveDynamicComponent as Xe, toHandlers as Kn, triggerRef as Lo, useSlots as Ua, onBeforeMount as gl, vModelSelect as Er, toRaw as Pr } from "vue";
import { DateFormatter as lt, createCalendar as Dr, toCalendar as zo, CalendarDateTime as $r, CalendarDate as Br, today as Ir, getLocalTimeZone as Hn, isEqualMonth as Ko, isSameDay as Oe, isEqualDay as ke, isToday as bl, isSameMonth as Cl } from "@internationalized/date";
import { k as ia, t as ze, j as wl, d as Pt, n as Pa, m as Ke, l as Ze, o as Tr, x as _l, u as Rr, r as Ar } from "./calendar-ChFCRr4K.js";
import { useFloating as Or, autoUpdate as kr, offset as Mr, flip as Ho, shift as Vr, limitShift as Fr, size as Nr, arrow as Lr, hide as zr } from "@floating-ui/vue";
import { NumberFormatter as Kr, NumberParser as Hr } from "@internationalized/number";
function te(a, t) {
  const e = typeof a == "string" && !t ? `${a}Context` : t, n = Symbol(e);
  return [(r) => {
    const i = ul(n, r);
    if (i || i === null)
      return i;
    throw new Error(
      `Injection \`${n.toString()}\` not found. Component must be used within ${Array.isArray(a) ? `one of the following components: ${a.join(
        ", "
      )}` : `\`${a}\``}`
    );
  }, (r) => (dl(n, r), r)];
}
function jt(a, t, e) {
  const n = e.originalEvent.target, l = new CustomEvent(a, {
    bubbles: !1,
    cancelable: !0,
    detail: e
  });
  t && n.addEventListener(a, t, { once: !0 }), n.dispatchEvent(l);
}
function Ut(a, t = Number.NEGATIVE_INFINITY, e = Number.POSITIVE_INFINITY) {
  return Math.min(e, Math.max(t, a));
}
function Da(a, t) {
  let e = a;
  const n = t.toString(), l = n.indexOf("."), s = l >= 0 ? n.length - l : 0;
  if (s > 0) {
    const r = 10 ** s;
    e = Math.round(e * r) / r;
  }
  return e;
}
function Wr(a, t, e, n) {
  t = Number(t), e = Number(e);
  const l = (a - (Number.isNaN(t) ? 0 : t)) % n;
  let s = Da(Math.abs(l) * 2 >= n ? a + Math.sign(l) * (n - Math.abs(l)) : a - l, n);
  return Number.isNaN(t) ? !Number.isNaN(e) && s > e && (s = Math.floor(Da(e / n, n)) * n) : s < t ? s = t : !Number.isNaN(e) && s > e && (s = t + Math.floor(Da((e - t) / n, n)) * n), s = Da(s, n), s;
}
function jr(a) {
  return a && a.__esModule && Object.prototype.hasOwnProperty.call(a, "default") ? a.default : a;
}
var Ur = function a(t, e) {
  if (t === e) return !0;
  if (t && e && typeof t == "object" && typeof e == "object") {
    if (t.constructor !== e.constructor) return !1;
    var n, l, s;
    if (Array.isArray(t)) {
      if (n = t.length, n != e.length) return !1;
      for (l = n; l-- !== 0; )
        if (!a(t[l], e[l])) return !1;
      return !0;
    }
    if (t.constructor === RegExp) return t.source === e.source && t.flags === e.flags;
    if (t.valueOf !== Object.prototype.valueOf) return t.valueOf() === e.valueOf();
    if (t.toString !== Object.prototype.toString) return t.toString() === e.toString();
    if (s = Object.keys(t), n = s.length, n !== Object.keys(e).length) return !1;
    for (l = n; l-- !== 0; )
      if (!Object.prototype.hasOwnProperty.call(e, s[l])) return !1;
    for (l = n; l-- !== 0; ) {
      var r = s[l];
      if (!a(t[r], e[r])) return !1;
    }
    return !0;
  }
  return t !== t && e !== e;
};
const Qe = /* @__PURE__ */ jr(Ur);
function Gr(a, t) {
  if (a.length !== t.length)
    return !1;
  for (let e = 0; e < a.length; e++)
    if (a[e] !== t[e])
      return !1;
  return !0;
}
function Bt(a, t, e) {
  const n = a.findIndex((i) => Qe(i, t)), l = a.findIndex((i) => Qe(i, e));
  if (n === -1 || l === -1)
    return [];
  const [s, r] = [n, l].sort((i, u) => i - u);
  return a.slice(s, r + 1);
}
const ha = typeof document < "u";
function ht(a) {
  return a == null;
}
function Yt(a) {
  const { defaultValue: t, defaultPlaceholder: e, granularity: n = "day", locale: l = "en" } = a;
  if (Array.isArray(t) && t.length)
    return t.at(-1).copy();
  if (t && !Array.isArray(t))
    return t.copy();
  if (e)
    return e.copy();
  const s = /* @__PURE__ */ new Date(), r = s.getFullYear(), i = s.getMonth() + 1, u = s.getDate(), d = ["hour", "minute", "second"], c = new lt(l), f = Dr(c.resolvedOptions().calendar);
  return d.includes(n ?? "day") ? zo(new $r(r, i, u, 0, 0, 0), f) : zo(new Br(r, i, u), f);
}
const qr = [
  "ach",
  "af",
  "am",
  "an",
  "ar",
  "ast",
  "az",
  "be",
  "bg",
  "bn",
  "br",
  "bs",
  "ca",
  "cak",
  "ckb",
  "cs",
  "cy",
  "da",
  "de",
  "dsb",
  "el",
  "en",
  "eo",
  "es",
  "et",
  "eu",
  "fa",
  "ff",
  "fi",
  "fr",
  "fy",
  "ga",
  "gd",
  "gl",
  "he",
  "hr",
  "hsb",
  "hu",
  "ia",
  "id",
  "it",
  "ja",
  "ka",
  "kk",
  "kn",
  "ko",
  "lb",
  "lo",
  "lt",
  "lv",
  "meh",
  "ml",
  "ms",
  "nl",
  "nn",
  "no",
  "oc",
  "pl",
  "pt",
  "rm",
  "ro",
  "ru",
  "sc",
  "scn",
  "sk",
  "sl",
  "sr",
  "sv",
  "szl",
  "tg",
  "th",
  "tr",
  "uk",
  "zh-CN",
  "zh-TW"
], Yr = ["year", "month", "day"], gn = {
  ach: { year: "mwaka", month: "dwe", day: "nino" },
  af: { year: "jjjj", month: "mm", day: "dd" },
  am: { year: "ዓዓዓዓ", month: "ሚሜ", day: "ቀቀ" },
  an: { year: "aaaa", month: "mm", day: "dd" },
  ar: { year: "سنة", month: "شهر", day: "يوم" },
  ast: { year: "aaaa", month: "mm", day: "dd" },
  az: { year: "iiii", month: "aa", day: "gg" },
  be: { year: "гггг", month: "мм", day: "дд" },
  bg: { year: "гггг", month: "мм", day: "дд" },
  bn: { year: "yyyy", month: "মিমি", day: "dd" },
  br: { year: "bbbb", month: "mm", day: "dd" },
  bs: { year: "gggg", month: "mm", day: "dd" },
  ca: { year: "aaaa", month: "mm", day: "dd" },
  cak: { year: "jjjj", month: "ii", day: "q'q'" },
  ckb: { year: "ساڵ", month: "مانگ", day: "ڕۆژ" },
  cs: { year: "rrrr", month: "mm", day: "dd" },
  cy: { year: "bbbb", month: "mm", day: "dd" },
  da: { year: "åååå", month: "mm", day: "dd" },
  de: { year: "jjjj", month: "mm", day: "tt" },
  dsb: { year: "llll", month: "mm", day: "źź" },
  el: { year: "εεεε", month: "μμ", day: "ηη" },
  en: { year: "yyyy", month: "mm", day: "dd" },
  eo: { year: "jjjj", month: "mm", day: "tt" },
  es: { year: "aaaa", month: "mm", day: "dd" },
  et: { year: "aaaa", month: "kk", day: "pp" },
  eu: { year: "uuuu", month: "hh", day: "ee" },
  fa: { year: "سال", month: "ماه", day: "روز" },
  ff: { year: "hhhh", month: "ll", day: "ññ" },
  fi: { year: "vvvv", month: "kk", day: "pp" },
  fr: { year: "aaaa", month: "mm", day: "jj" },
  fy: { year: "jjjj", month: "mm", day: "dd" },
  ga: { year: "bbbb", month: "mm", day: "ll" },
  gd: { year: "bbbb", month: "mm", day: "ll" },
  gl: { year: "aaaa", month: "mm", day: "dd" },
  he: { year: "שנה", month: "חודש", day: "יום" },
  hr: { year: "gggg", month: "mm", day: "dd" },
  hsb: { year: "llll", month: "mm", day: "dd" },
  hu: { year: "éééé", month: "hh", day: "nn" },
  ia: { year: "aaaa", month: "mm", day: "dd" },
  id: { year: "tttt", month: "bb", day: "hh" },
  it: { year: "aaaa", month: "mm", day: "gg" },
  ja: { year: " 年 ", month: "月", day: "日" },
  ka: { year: "წწწწ", month: "თთ", day: "რრ" },
  kk: { year: "жжжж", month: "аа", day: "кк" },
  kn: { year: "ವವವವ", month: "ಮಿಮೀ", day: "ದಿದಿ" },
  ko: { year: "연도", month: "월", day: "일" },
  lb: { year: "jjjj", month: "mm", day: "dd" },
  lo: { year: "ປປປປ", month: "ດດ", day: "ວວ" },
  lt: { year: "mmmm", month: "mm", day: "dd" },
  lv: { year: "gggg", month: "mm", day: "dd" },
  meh: { year: "aaaa", month: "mm", day: "dd" },
  ml: { year: "വർഷം", month: "മാസം", day: "തീയതി" },
  ms: { year: "tttt", month: "mm", day: "hh" },
  nl: { year: "jjjj", month: "mm", day: "dd" },
  nn: { year: "åååå", month: "mm", day: "dd" },
  no: { year: "åååå", month: "mm", day: "dd" },
  oc: { year: "aaaa", month: "mm", day: "jj" },
  pl: { year: "rrrr", month: "mm", day: "dd" },
  pt: { year: "aaaa", month: "mm", day: "dd" },
  rm: { year: "oooo", month: "mm", day: "dd" },
  ro: { year: "aaaa", month: "ll", day: "zz" },
  ru: { year: "гггг", month: "мм", day: "дд" },
  sc: { year: "aaaa", month: "mm", day: "dd" },
  scn: { year: "aaaa", month: "mm", day: "jj" },
  sk: { year: "rrrr", month: "mm", day: "dd" },
  sl: { year: "llll", month: "mm", day: "dd" },
  sr: { year: "гггг", month: "мм", day: "дд" },
  sv: { year: "åååå", month: "mm", day: "dd" },
  szl: { year: "rrrr", month: "mm", day: "dd" },
  tg: { year: "сссс", month: "мм", day: "рр" },
  th: { year: "ปปปป", month: "ดด", day: "วว" },
  tr: { year: "yyyy", month: "aa", day: "gg" },
  uk: { year: "рррр", month: "мм", day: "дд" },
  "zh-CN": { year: "年", month: "月", day: "日" },
  "zh-TW": { year: "年", month: "月", day: "日" }
};
function Xr(a) {
  if (Wo(a))
    return gn[a];
  {
    const t = ei(a);
    return Wo(t) ? gn[t] : gn.en;
  }
}
function bn(a, t, e) {
  return Zr(a) ? Xr(e)[a] : Qr(a) ? t : Jr(a) ? "––" : "";
}
function Wo(a) {
  return qr.includes(a);
}
function Zr(a) {
  return Yr.includes(a);
}
function Jr(a) {
  return a === "hour" || a === "minute" || a === "second";
}
function Qr(a) {
  return a === "era" || a === "dayPeriod";
}
function ei(a) {
  return Intl.Locale ? new Intl.Locale(a).language : a.split("-")[0];
}
const Wn = ["day", "month", "year"], xl = ["hour", "minute", "second", "dayPeriod"], Sl = [...Wn, ...xl];
function ti(a) {
  return Wn.includes(a);
}
function El(a) {
  return Sl.includes(a);
}
function ai(a, t) {
  const e = {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    timeZoneName: "short",
    hourCycle: t === 24 ? "h24" : void 0,
    hour12: t === 24 ? !1 : void 0
  };
  return a === "day" && (delete e.second, delete e.hour, delete e.minute, delete e.timeZoneName), a === "hour" && (delete e.minute, delete e.second), a === "minute" && delete e.second, e;
}
function Pl(a) {
  const t = a.querySelector("[data-selected]");
  if (t)
    return t.focus();
  const e = a.querySelector("[data-today]");
  if (e)
    return e.focus();
  const n = a.querySelector("[data-radix-vue-calendar-day]");
  if (n)
    return n.focus();
}
function ni(a, t) {
  var e;
  const n = Fn();
  return Ce(() => {
    n.value = a();
  }, {
    ...t,
    flush: (e = void 0) != null ? e : "sync"
  }), Wa(n);
}
function oi(a, t) {
  let e, n, l;
  const s = T(!0), r = () => {
    s.value = !0, l();
  };
  ee(a, r, { flush: "sync" });
  const i = typeof t == "function" ? t : t.get, u = typeof t == "function" ? void 0 : t.set, d = cl((c, f) => (n = c, l = f, {
    get() {
      return s.value && (e = i(), s.value = !1), n(), e;
    },
    set(v) {
      u == null || u(v);
    }
  }));
  return Object.isExtensible(d) && (d.trigger = r), d;
}
function bt(a) {
  return gr() ? (fl(a), !0) : !1;
}
function ua() {
  const a = /* @__PURE__ */ new Set(), t = (l) => {
    a.delete(l);
  };
  return {
    on: (l) => {
      a.add(l);
      const s = () => t(l);
      return bt(s), {
        off: s
      };
    },
    off: t,
    trigger: (...l) => Promise.all(Array.from(a).map((s) => s(...l)))
  };
}
function li(a) {
  let t = !1, e;
  const n = pl(!0);
  return (...l) => (t || (e = n.run(() => a(...l)), t = !0), e);
}
function Dl(a) {
  let t = 0, e, n;
  const l = () => {
    t -= 1, n && t <= 0 && (n.stop(), e = void 0, n = void 0);
  };
  return (...s) => (t += 1, e || (n = pl(!0), e = n.run(() => a(...s))), bt(l), e);
}
function je(a) {
  return typeof a == "function" ? a() : o(a);
}
function si(a) {
  if (!et(a))
    return Fa(a);
  const t = new Proxy({}, {
    get(e, n, l) {
      return o(Reflect.get(a.value, n, l));
    },
    set(e, n, l) {
      return et(a.value[n]) && !et(l) ? a.value[n].value = l : a.value[n] = l, !0;
    },
    deleteProperty(e, n) {
      return Reflect.deleteProperty(a.value, n);
    },
    has(e, n) {
      return Reflect.has(a.value, n);
    },
    ownKeys() {
      return Object.keys(a.value);
    },
    getOwnPropertyDescriptor() {
      return {
        enumerable: !0,
        configurable: !0
      };
    }
  });
  return Fa(t);
}
function $l(a) {
  return si(B(a));
}
const Je = typeof window < "u" && typeof document < "u";
typeof WorkerGlobalScope < "u" && globalThis instanceof WorkerGlobalScope;
const ri = (a) => typeof a < "u", ii = (a) => a != null, ui = Object.prototype.toString, di = (a) => ui.call(a) === "[object Object]", Na = () => {
}, jo = /* @__PURE__ */ ci();
function ci() {
  var a, t;
  return Je && ((a = window == null ? void 0 : window.navigator) == null ? void 0 : a.userAgent) && (/iP(?:ad|hone|od)/.test(window.navigator.userAgent) || ((t = window == null ? void 0 : window.navigator) == null ? void 0 : t.maxTouchPoints) > 2 && /iPad|Macintosh/.test(window == null ? void 0 : window.navigator.userAgent));
}
function Bl(a, t) {
  function e(...n) {
    return new Promise((l, s) => {
      Promise.resolve(a(() => t.apply(this, n), { fn: t, thisArg: this, args: n })).then(l).catch(s);
    });
  }
  return e;
}
const Il = (a) => a();
function fi(a, t = {}) {
  let e, n, l = Na;
  const s = (i) => {
    clearTimeout(i), l(), l = Na;
  };
  return (i) => {
    const u = je(a), d = je(t.maxWait);
    return e && s(e), u <= 0 || d !== void 0 && d <= 0 ? (n && (s(n), n = null), Promise.resolve(i())) : new Promise((c, f) => {
      l = t.rejectOnCancel ? f : c, d && !n && (n = setTimeout(() => {
        e && s(e), n = null, c(i());
      }, d)), e = setTimeout(() => {
        n && s(n), n = null, c(i());
      }, u);
    });
  };
}
function pi(a = Il) {
  const t = T(!0);
  function e() {
    t.value = !1;
  }
  function n() {
    t.value = !0;
  }
  const l = (...s) => {
    t.value && a(...s);
  };
  return { isActive: Wa(t), pause: e, resume: n, eventFilter: l };
}
function Tl(a) {
  return gt();
}
function Tt(a, t = 1e4) {
  return cl((e, n) => {
    let l = je(a), s;
    const r = () => setTimeout(() => {
      l = je(a), n();
    }, je(t));
    return bt(() => {
      clearTimeout(s);
    }), {
      get() {
        return e(), l;
      },
      set(i) {
        l = i, n(), clearTimeout(s), s = r();
      }
    };
  });
}
function jn(a, t = 200, e = {}) {
  return Bl(
    fi(t, e),
    a
  );
}
function vi(a, t, e = {}) {
  const {
    eventFilter: n = Il,
    ...l
  } = e;
  return ee(
    a,
    Bl(
      n,
      t
    ),
    l
  );
}
function Uo(a, t, e = {}) {
  const {
    eventFilter: n,
    ...l
  } = e, { eventFilter: s, pause: r, resume: i, isActive: u } = pi(n);
  return { stop: vi(
    a,
    t,
    {
      ...l,
      eventFilter: s
    }
  ), pause: r, resume: i, isActive: u };
}
function mi(a, t, ...[e]) {
  const {
    flush: n = "sync",
    deep: l = !1,
    immediate: s = !0,
    direction: r = "both",
    transform: i = {}
  } = e || {}, u = [], d = "ltr" in i && i.ltr || ((v) => v), c = "rtl" in i && i.rtl || ((v) => v);
  return (r === "both" || r === "ltr") && u.push(Uo(
    a,
    (v) => {
      u.forEach((p) => p.pause()), t.value = d(v), u.forEach((p) => p.resume());
    },
    { flush: n, deep: l, immediate: s }
  )), (r === "both" || r === "rtl") && u.push(Uo(
    t,
    (v) => {
      u.forEach((p) => p.pause()), a.value = c(v), u.forEach((p) => p.resume());
    },
    { flush: n, deep: l, immediate: s }
  )), () => {
    u.forEach((v) => v.stop());
  };
}
function hi(a, t) {
  Tl() && Nn(a, t);
}
function yi(a, t = !0, e) {
  Tl() ? le(a, e) : t ? a() : oe(a);
}
function Un(a, t, e = {}) {
  const {
    immediate: n = !0
  } = e, l = T(!1);
  let s = null;
  function r() {
    s && (clearTimeout(s), s = null);
  }
  function i() {
    l.value = !1, r();
  }
  function u(...d) {
    r(), l.value = !0, s = setTimeout(() => {
      l.value = !1, s = null, a(...d);
    }, je(t));
  }
  return n && (l.value = !0, Je && u()), bt(i), {
    isPending: Wa(l),
    start: u,
    stop: i
  };
}
function gi(a = 1e3, t = {}) {
  const {
    controls: e = !1,
    callback: n
  } = t, l = Un(
    n ?? Na,
    a,
    t
  ), s = B(() => !l.isPending.value);
  return e ? {
    ready: s,
    ...l
  } : s;
}
function bi(a, t, e) {
  const n = ee(a, (...l) => (oe(() => n()), t(...l)), e);
  return n;
}
function $e(a) {
  var t;
  const e = je(a);
  return (t = e == null ? void 0 : e.$el) != null ? t : e;
}
const Rt = Je ? window : void 0;
function He(...a) {
  let t, e, n, l;
  if (typeof a[0] == "string" || Array.isArray(a[0]) ? ([e, n, l] = a, t = Rt) : [t, e, n, l] = a, !t)
    return Na;
  Array.isArray(e) || (e = [e]), Array.isArray(n) || (n = [n]);
  const s = [], r = () => {
    s.forEach((c) => c()), s.length = 0;
  }, i = (c, f, v, p) => (c.addEventListener(f, v, p), () => c.removeEventListener(f, v, p)), u = ee(
    () => [$e(t), je(l)],
    ([c, f]) => {
      if (r(), !c)
        return;
      const v = di(f) ? { ...f } : f;
      s.push(
        ...e.flatMap((p) => n.map((g) => i(c, p, g, v)))
      );
    },
    { immediate: !0, flush: "post" }
  ), d = () => {
    u(), r();
  };
  return bt(d), d;
}
function Ci(a) {
  return typeof a == "function" ? a : typeof a == "string" ? (t) => t.key === a : Array.isArray(a) ? (t) => a.includes(t.key) : () => !0;
}
function Gn(...a) {
  let t, e, n = {};
  a.length === 3 ? (t = a[0], e = a[1], n = a[2]) : a.length === 2 ? typeof a[1] == "object" ? (t = !0, e = a[0], n = a[1]) : (t = a[0], e = a[1]) : (t = !0, e = a[0]);
  const {
    target: l = Rt,
    eventName: s = "keydown",
    passive: r = !1,
    dedupe: i = !1
  } = n, u = Ci(t);
  return He(l, s, (c) => {
    c.repeat && je(i) || u(c) && e(c);
  }, r);
}
function Ga() {
  const a = T(!1), t = gt();
  return t && le(() => {
    a.value = !0;
  }, t), a;
}
function Rl(a) {
  const t = Ga();
  return B(() => (t.value, !!a()));
}
function Al(a, t, e = {}) {
  const { window: n = Rt, ...l } = e;
  let s;
  const r = Rl(() => n && "MutationObserver" in n), i = () => {
    s && (s.disconnect(), s = void 0);
  }, u = B(() => {
    const v = je(a), p = (Array.isArray(v) ? v : [v]).map($e).filter(ii);
    return new Set(p);
  }), d = ee(
    () => u.value,
    (v) => {
      i(), r.value && v.size && (s = new MutationObserver(t), v.forEach((p) => s.observe(p, l)));
    },
    { immediate: !0, flush: "post" }
  ), c = () => s == null ? void 0 : s.takeRecords(), f = () => {
    i(), d();
  };
  return bt(f), {
    isSupported: r,
    stop: f,
    takeRecords: c
  };
}
function wi(a = {}) {
  var t;
  const {
    window: e = Rt,
    deep: n = !0,
    triggerOnRemoval: l = !1
  } = a, s = (t = a.document) != null ? t : e == null ? void 0 : e.document, r = () => {
    var d;
    let c = s == null ? void 0 : s.activeElement;
    if (n)
      for (; c != null && c.shadowRoot; )
        c = (d = c == null ? void 0 : c.shadowRoot) == null ? void 0 : d.activeElement;
    return c;
  }, i = T(), u = () => {
    i.value = r();
  };
  return e && (He(e, "blur", (d) => {
    d.relatedTarget === null && u();
  }, !0), He(e, "focus", u, !0)), l && Al(s, (d) => {
    d.filter((c) => c.removedNodes.length).map((c) => Array.from(c.removedNodes)).flat().forEach((c) => {
      c === i.value && u();
    });
  }, {
    childList: !0,
    subtree: !0
  }), u(), i;
}
function Ol(a, t = {}) {
  const {
    immediate: e = !0,
    fpsLimit: n = void 0,
    window: l = Rt
  } = t, s = T(!1), r = n ? 1e3 / n : null;
  let i = 0, u = null;
  function d(v) {
    if (!s.value || !l)
      return;
    i || (i = v);
    const p = v - i;
    if (r && p < r) {
      u = l.requestAnimationFrame(d);
      return;
    }
    i = v, a({ delta: p, timestamp: v }), u = l.requestAnimationFrame(d);
  }
  function c() {
    !s.value && l && (s.value = !0, i = 0, u = l.requestAnimationFrame(d));
  }
  function f() {
    s.value = !1, u != null && l && (l.cancelAnimationFrame(u), u = null);
  }
  return e && c(), bt(f), {
    isActive: Wa(s),
    pause: f,
    resume: c
  };
}
function _i(a) {
  return JSON.parse(JSON.stringify(a));
}
function xi(a) {
  const t = gt(), e = oi(
    () => null,
    () => t.proxy.$el
  );
  return vl(e.trigger), le(e.trigger), e;
}
function tt(a, t, e = {}) {
  const { window: n = Rt, ...l } = e;
  let s;
  const r = Rl(() => n && "ResizeObserver" in n), i = () => {
    s && (s.disconnect(), s = void 0);
  }, u = B(() => Array.isArray(a) ? a.map((f) => $e(f)) : [$e(a)]), d = ee(
    u,
    (f) => {
      if (i(), r.value && n) {
        s = new ResizeObserver(t);
        for (const v of f)
          v && s.observe(v, l);
      }
    },
    { immediate: !0, flush: "post" }
  ), c = () => {
    i(), d();
  };
  return bt(c), {
    isSupported: r,
    stop: c
  };
}
function Si(a, t = {}) {
  const e = wi(t), n = B(() => $e(a));
  return { focused: B(() => n.value && e.value ? n.value.contains(e.value) : !1) };
}
function kl(a = xi()) {
  const t = Fn(), e = () => {
    const n = $e(a);
    n && (t.value = n.parentElement);
  };
  return yi(e), ee(() => je(a), e), t;
}
function ne(a, t, e, n = {}) {
  var l, s, r;
  const {
    clone: i = !1,
    passive: u = !1,
    eventName: d,
    deep: c = !1,
    defaultValue: f,
    shouldEmit: v
  } = n, p = gt(), g = e || (p == null ? void 0 : p.emit) || ((l = p == null ? void 0 : p.$emit) == null ? void 0 : l.bind(p)) || ((r = (s = p == null ? void 0 : p.proxy) == null ? void 0 : s.$emit) == null ? void 0 : r.bind(p == null ? void 0 : p.proxy));
  let m = d;
  t || (t = "modelValue"), m = m || `update:${t.toString()}`;
  const _ = (h) => i ? typeof i == "function" ? i(h) : _i(h) : h, C = () => ri(a[t]) ? _(a[t]) : f, $ = (h) => {
    v ? v(h) && g(m, h) : g(m, h);
  };
  if (u) {
    const h = C(), E = T(h);
    let P = !1;
    return ee(
      () => a[t],
      (D) => {
        P || (P = !0, E.value = _(D), oe(() => P = !1));
      }
    ), ee(
      E,
      (D) => {
        !P && (D !== a[t] || c) && $(D);
      },
      { deep: c }
    ), E;
  } else
    return B({
      get() {
        return C();
      },
      set(h) {
        $(h);
      }
    });
}
function qa(a) {
  return a ? a.flatMap((t) => t.type === _e ? qa(t.children) : [t]) : [];
}
function me() {
  let a = document.activeElement;
  if (a == null)
    return null;
  for (; a != null && a.shadowRoot != null && a.shadowRoot.activeElement != null; )
    a = a.shadowRoot.activeElement;
  return a;
}
const Ei = ["INPUT", "TEXTAREA"];
function At(a, t, e, n = {}) {
  if (!t || n.enableIgnoredElement && Ei.includes(t.nodeName))
    return null;
  const {
    arrowKeyOptions: l = "both",
    attributeName: s = "[data-radix-vue-collection-item]",
    itemsArray: r = [],
    loop: i = !0,
    dir: u = "ltr",
    preventScroll: d = !0,
    focus: c = !1
  } = n, [f, v, p, g, m, _] = [
    a.key === "ArrowRight",
    a.key === "ArrowLeft",
    a.key === "ArrowUp",
    a.key === "ArrowDown",
    a.key === "Home",
    a.key === "End"
  ], C = p || g, $ = f || v;
  if (!m && !_ && (!C && !$ || l === "vertical" && $ || l === "horizontal" && C))
    return null;
  const h = e ? Array.from(e.querySelectorAll(s)) : r;
  if (!h.length)
    return null;
  d && a.preventDefault();
  let E = null;
  return $ || C ? E = Ml(h, t, {
    goForward: C ? g : u === "ltr" ? f : v,
    loop: i
  }) : m ? E = h.at(0) || null : _ && (E = h.at(-1) || null), c && (E == null || E.focus()), E;
}
function Ml(a, t, e, n = a.length) {
  if (--n === 0)
    return null;
  const l = a.indexOf(t), s = e.goForward ? l + 1 : l - 1;
  if (!e.loop && (s < 0 || s >= a.length))
    return null;
  const r = (s + a.length) % a.length, i = a[r];
  return i ? i.hasAttribute("disabled") && i.getAttribute("disabled") !== "false" ? Ml(
    a,
    i,
    e,
    n
  ) : i : null;
}
function Cn(a) {
  if (a === null || typeof a != "object")
    return !1;
  const t = Object.getPrototypeOf(a);
  return t !== null && t !== Object.prototype && Object.getPrototypeOf(t) !== null || Symbol.iterator in a ? !1 : Symbol.toStringTag in a ? Object.prototype.toString.call(a) === "[object Module]" : !0;
}
function $n(a, t, e = ".", n) {
  if (!Cn(t))
    return $n(a, {}, e, n);
  const l = Object.assign({}, t);
  for (const s in a) {
    if (s === "__proto__" || s === "constructor")
      continue;
    const r = a[s];
    r != null && (n && n(l, s, r, e) || (Array.isArray(r) && Array.isArray(l[s]) ? l[s] = [...r, ...l[s]] : Cn(r) && Cn(l[s]) ? l[s] = $n(
      r,
      l[s],
      (e ? `${e}.` : "") + s.toString(),
      n
    ) : l[s] = r));
  }
  return l;
}
function Pi(a) {
  return (...t) => (
    // eslint-disable-next-line unicorn/no-array-reduce
    t.reduce((e, n) => $n(e, n, "", a), {})
  );
}
const Di = Pi(), [Ya, $i] = te("ConfigProvider"), xv = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ConfigProvider",
  props: {
    dir: { default: "ltr" },
    scrollBody: { type: [Boolean, Object], default: !0 },
    nonce: { default: void 0 },
    useId: { type: Function, default: void 0 }
  },
  setup(a) {
    const t = a, { dir: e, scrollBody: n, nonce: l } = ae(t);
    return $i({
      dir: e,
      scrollBody: n,
      nonce: l,
      useId: t.useId
    }), (s, r) => w(s.$slots, "default");
  }
});
let Bi = "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict", Ii = (a = 21) => {
  let t = "", e = a;
  for (; e--; )
    t += Bi[Math.random() * 64 | 0];
  return t;
};
const Ti = Dl(() => {
  const a = T(/* @__PURE__ */ new Map()), t = T(), e = B(() => {
    for (const r of a.value.values())
      if (r)
        return !0;
    return !1;
  }), n = Ya({
    scrollBody: T(!0)
  });
  let l = null;
  const s = () => {
    document.body.style.paddingRight = "", document.body.style.marginRight = "", document.body.style.pointerEvents = "", document.body.style.removeProperty("--scrollbar-width"), document.body.style.overflow = t.value ?? "", jo && (l == null || l()), t.value = void 0;
  };
  return ee(e, (r, i) => {
    var f;
    if (!Je)
      return;
    if (!r) {
      i && s();
      return;
    }
    t.value === void 0 && (t.value = document.body.style.overflow);
    const u = window.innerWidth - document.documentElement.clientWidth, d = { padding: u, margin: 0 }, c = (f = n.scrollBody) != null && f.value ? typeof n.scrollBody.value == "object" ? Di({
      padding: n.scrollBody.value.padding === !0 ? u : n.scrollBody.value.padding,
      margin: n.scrollBody.value.margin === !0 ? u : n.scrollBody.value.margin
    }, d) : d : { padding: 0, margin: 0 };
    u > 0 && (document.body.style.paddingRight = typeof c.padding == "number" ? `${c.padding}px` : String(c.padding), document.body.style.marginRight = typeof c.margin == "number" ? `${c.margin}px` : String(c.margin), document.body.style.setProperty("--scrollbar-width", `${u}px`), document.body.style.overflow = "hidden"), jo && (l = He(
      document,
      "touchmove",
      (v) => Ri(v),
      { passive: !1 }
    )), oe(() => {
      document.body.style.pointerEvents = "none", document.body.style.overflow = "hidden";
    });
  }, { immediate: !0, flush: "sync" }), a;
});
function ya(a) {
  const t = Ii(6), e = Ti();
  e.value.set(t, a ?? !1);
  const n = B({
    get: () => e.value.get(t) ?? !1,
    set: (l) => e.value.set(t, l)
  });
  return hi(() => {
    e.value.delete(t);
  }), n;
}
function Vl(a) {
  const t = window.getComputedStyle(a);
  if (t.overflowX === "scroll" || t.overflowY === "scroll" || t.overflowX === "auto" && a.clientWidth < a.scrollWidth || t.overflowY === "auto" && a.clientHeight < a.scrollHeight)
    return !0;
  {
    const e = a.parentNode;
    return !(e instanceof Element) || e.tagName === "BODY" ? !1 : Vl(e);
  }
}
function Ri(a) {
  const t = a || window.event, e = t.target;
  return e instanceof Element && Vl(e) ? !1 : t.touches.length > 1 ? !0 : (t.preventDefault && t.cancelable && t.preventDefault(), !1);
}
const Ai = "data-radix-vue-collection-item";
function Fe(a, t = Ai) {
  const e = a ?? Symbol();
  return { createCollection: (s) => {
    const r = T([]);
    function i() {
      const u = $e(s);
      return u ? r.value = Array.from(
        u.querySelectorAll(`[${t}]:not([data-disabled])`)
      ) : r.value = [];
    }
    return br(() => {
      r.value = [];
    }), le(i), vl(i), ee(() => s == null ? void 0 : s.value, i, { immediate: !0 }), dl(e, r), r;
  }, injectCollection: () => ul(e, T([])) };
}
function qn(a) {
  const t = T(a);
  function e() {
    return t.value;
  }
  function n(m) {
    t.value = m;
  }
  function l(m, _) {
    return new lt(t.value, _).format(m);
  }
  function s(m, _ = !0) {
    return ia(m) && _ ? l(ze(m), {
      dateStyle: "long",
      timeStyle: "long"
    }) : l(ze(m), {
      dateStyle: "long"
    });
  }
  function r(m, _ = {}) {
    return new lt(t.value, { month: "long", year: "numeric", ..._ }).format(m);
  }
  function i(m, _ = {}) {
    return new lt(t.value, { month: "long", ..._ }).format(m);
  }
  function u() {
    const m = Ir(Hn());
    return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map((C) => ({ label: i(ze(m.set({ month: C }))), value: C }));
  }
  function d(m, _ = {}) {
    return new lt(t.value, { year: "numeric", ..._ }).format(m);
  }
  function c(m, _) {
    return wl(m) ? new lt(t.value, {
      ..._,
      timeZone: m.timeZone
    }).formatToParts(ze(m)) : new lt(t.value, _).formatToParts(ze(m));
  }
  function f(m, _ = "narrow") {
    return new lt(t.value, { weekday: _ }).format(m);
  }
  function v(m) {
    var $;
    return (($ = new lt(t.value, {
      hour: "numeric",
      minute: "numeric"
    }).formatToParts(m).find((h) => h.type === "dayPeriod")) == null ? void 0 : $.value) === "PM" ? "PM" : "AM";
  }
  const p = {
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric"
  };
  function g(m, _, C = {}) {
    const $ = { ...p, ...C }, E = c(m, $).find((P) => P.type === _);
    return E ? E.value : "";
  }
  return {
    setLocale: n,
    getLocale: e,
    fullMonth: i,
    fullYear: d,
    fullMonthAndYear: r,
    toParts: c,
    custom: l,
    part: g,
    dayPeriod: v,
    selectedDate: s,
    dayOfWeek: f,
    getMonths: u
  };
}
function we(a) {
  const t = Ya({
    dir: T("ltr")
  });
  return B(() => {
    var e;
    return (a == null ? void 0 : a.value) || ((e = t.dir) == null ? void 0 : e.value) || "ltr";
  });
}
function Te(a) {
  const t = gt(), e = t == null ? void 0 : t.type.emits, n = {};
  return e != null && e.length || console.warn(
    `No emitted event found. Please check component: ${t == null ? void 0 : t.type.__name}`
  ), e == null || e.forEach((l) => {
    n[Cr(ml(l))] = (...s) => a(l, ...s);
  }), n;
}
let wn = 0;
function Yn() {
  Ce((a) => {
    if (!Je)
      return;
    const t = document.querySelectorAll("[data-radix-focus-guard]");
    document.body.insertAdjacentElement(
      "afterbegin",
      t[0] ?? Go()
    ), document.body.insertAdjacentElement(
      "beforeend",
      t[1] ?? Go()
    ), wn++, a(() => {
      wn === 1 && document.querySelectorAll("[data-radix-focus-guard]").forEach((e) => e.remove()), wn--;
    });
  });
}
function Go() {
  const a = document.createElement("span");
  return a.setAttribute("data-radix-focus-guard", ""), a.tabIndex = 0, a.style.outline = "none", a.style.opacity = "0", a.style.position = "fixed", a.style.pointerEvents = "none", a;
}
function at(a) {
  return B(() => {
    var t;
    return je(a) ? !!((t = $e(a)) != null && t.closest("form")) : !0;
  });
}
function Ot(a) {
  const t = gt(), e = Object.keys((t == null ? void 0 : t.type.props) ?? {}).reduce((l, s) => {
    const r = (t == null ? void 0 : t.type.props[s]).default;
    return r !== void 0 && (l[s] = r), l;
  }, {}), n = wr(a);
  return B(() => {
    const l = {}, s = (t == null ? void 0 : t.vnode.props) ?? {};
    return Object.keys(s).forEach((r) => {
      l[ml(r)] = s[r];
    }), Object.keys({ ...e, ...l }).reduce((r, i) => (n.value[i] !== void 0 && (r[i] = n.value[i]), r), {});
  });
}
function Se(a, t) {
  const e = Ot(a), n = t ? Te(t) : {};
  return B(() => ({
    ...e.value,
    ...n
  }));
}
function R() {
  const a = gt(), t = T(), e = B(() => {
    var r, i;
    return ["#text", "#comment"].includes((r = t.value) == null ? void 0 : r.$el.nodeName) ? (i = t.value) == null ? void 0 : i.$el.nextElementSibling : $e(t);
  }), n = Object.assign({}, a.exposed), l = {};
  for (const r in a.props)
    Object.defineProperty(l, r, {
      enumerable: !0,
      configurable: !0,
      get: () => a.props[r]
    });
  if (Object.keys(n).length > 0)
    for (const r in n)
      Object.defineProperty(l, r, {
        enumerable: !0,
        configurable: !0,
        get: () => n[r]
      });
  Object.defineProperty(l, "$el", {
    enumerable: !0,
    configurable: !0,
    get: () => a.vnode.el
  }), a.exposed = l;
  function s(r) {
    t.value = r, r && (Object.defineProperty(l, "$el", {
      enumerable: !0,
      configurable: !0,
      get: () => r instanceof Element ? r : r.$el
    }), a.exposed = l);
  }
  return { forwardRef: s, currentRef: t, currentElement: e };
}
function Fl(a, t) {
  const e = Tt(!1, 300), n = T(null), l = ua();
  function s() {
    n.value = null, e.value = !1;
  }
  function r(i, u) {
    const d = i.currentTarget, c = { x: i.clientX, y: i.clientY }, f = Oi(c, d.getBoundingClientRect()), v = ki(c, f), p = Mi(u.getBoundingClientRect()), g = Fi([...v, ...p]);
    n.value = g, e.value = !0;
  }
  return Ce((i) => {
    if (a.value && t.value) {
      const u = (c) => r(c, t.value), d = (c) => r(c, a.value);
      a.value.addEventListener("pointerleave", u), t.value.addEventListener("pointerleave", d), i(() => {
        var c, f;
        (c = a.value) == null || c.removeEventListener("pointerleave", u), (f = t.value) == null || f.removeEventListener("pointerleave", d);
      });
    }
  }), Ce((i) => {
    var u;
    if (n.value) {
      const d = (c) => {
        var _, C;
        if (!n.value)
          return;
        const f = c.target, v = { x: c.clientX, y: c.clientY }, p = ((_ = a.value) == null ? void 0 : _.contains(f)) || ((C = t.value) == null ? void 0 : C.contains(f)), g = !Vi(v, n.value), m = !!f.closest("[data-grace-area-trigger]");
        p ? s() : (g || m) && (s(), l.trigger());
      };
      (u = a.value) == null || u.ownerDocument.addEventListener("pointermove", d), i(() => {
        var c;
        return (c = a.value) == null ? void 0 : c.ownerDocument.removeEventListener("pointermove", d);
      });
    }
  }), {
    isPointerInTransit: e,
    onPointerExit: l.on
  };
}
function Oi(a, t) {
  const e = Math.abs(t.top - a.y), n = Math.abs(t.bottom - a.y), l = Math.abs(t.right - a.x), s = Math.abs(t.left - a.x);
  switch (Math.min(e, n, l, s)) {
    case s:
      return "left";
    case l:
      return "right";
    case e:
      return "top";
    case n:
      return "bottom";
    default:
      throw new Error("unreachable");
  }
}
function ki(a, t, e = 5) {
  const n = [];
  switch (t) {
    case "top":
      n.push(
        { x: a.x - e, y: a.y + e },
        { x: a.x + e, y: a.y + e }
      );
      break;
    case "bottom":
      n.push(
        { x: a.x - e, y: a.y - e },
        { x: a.x + e, y: a.y - e }
      );
      break;
    case "left":
      n.push(
        { x: a.x + e, y: a.y - e },
        { x: a.x + e, y: a.y + e }
      );
      break;
    case "right":
      n.push(
        { x: a.x - e, y: a.y - e },
        { x: a.x - e, y: a.y + e }
      );
      break;
  }
  return n;
}
function Mi(a) {
  const { top: t, right: e, bottom: n, left: l } = a;
  return [
    { x: l, y: t },
    { x: e, y: t },
    { x: e, y: n },
    { x: l, y: n }
  ];
}
function Vi(a, t) {
  const { x: e, y: n } = a;
  let l = !1;
  for (let s = 0, r = t.length - 1; s < t.length; r = s++) {
    const i = t[s].x, u = t[s].y, d = t[r].x, c = t[r].y;
    u > n != c > n && e < (d - i) * (n - u) / (c - u) + i && (l = !l);
  }
  return l;
}
function Fi(a) {
  const t = a.slice();
  return t.sort((e, n) => e.x < n.x ? -1 : e.x > n.x ? 1 : e.y < n.y ? -1 : e.y > n.y ? 1 : 0), Ni(t);
}
function Ni(a) {
  if (a.length <= 1)
    return a.slice();
  const t = [];
  for (let n = 0; n < a.length; n++) {
    const l = a[n];
    for (; t.length >= 2; ) {
      const s = t[t.length - 1], r = t[t.length - 2];
      if ((s.x - r.x) * (l.y - r.y) >= (s.y - r.y) * (l.x - r.x))
        t.pop();
      else break;
    }
    t.push(l);
  }
  t.pop();
  const e = [];
  for (let n = a.length - 1; n >= 0; n--) {
    const l = a[n];
    for (; e.length >= 2; ) {
      const s = e[e.length - 1], r = e[e.length - 2];
      if ((s.x - r.x) * (l.y - r.y) >= (s.y - r.y) * (l.x - r.x))
        e.pop();
      else break;
    }
    e.push(l);
  }
  return e.pop(), t.length === 1 && e.length === 1 && t[0].x === e[0].x && t[0].y === e[0].y ? t : t.concat(e);
}
var Li = function(a) {
  if (typeof document > "u")
    return null;
  var t = Array.isArray(a) ? a[0] : a;
  return t.ownerDocument.body;
}, Kt = /* @__PURE__ */ new WeakMap(), $a = /* @__PURE__ */ new WeakMap(), Ba = {}, _n = 0, Nl = function(a) {
  return a && (a.host || Nl(a.parentNode));
}, zi = function(a, t) {
  return t.map(function(e) {
    if (a.contains(e))
      return e;
    var n = Nl(e);
    return n && a.contains(n) ? n : (console.error("aria-hidden", e, "in not contained inside", a, ". Doing nothing"), null);
  }).filter(function(e) {
    return !!e;
  });
}, Ki = function(a, t, e, n) {
  var l = zi(t, Array.isArray(a) ? a : [a]);
  Ba[e] || (Ba[e] = /* @__PURE__ */ new WeakMap());
  var s = Ba[e], r = [], i = /* @__PURE__ */ new Set(), u = new Set(l), d = function(f) {
    !f || i.has(f) || (i.add(f), d(f.parentNode));
  };
  l.forEach(d);
  var c = function(f) {
    !f || u.has(f) || Array.prototype.forEach.call(f.children, function(v) {
      if (i.has(v))
        c(v);
      else
        try {
          var p = v.getAttribute(n), g = p !== null && p !== "false", m = (Kt.get(v) || 0) + 1, _ = (s.get(v) || 0) + 1;
          Kt.set(v, m), s.set(v, _), r.push(v), m === 1 && g && $a.set(v, !0), _ === 1 && v.setAttribute(e, "true"), g || v.setAttribute(n, "true");
        } catch (C) {
          console.error("aria-hidden: cannot operate on ", v, C);
        }
    });
  };
  return c(t), i.clear(), _n++, function() {
    r.forEach(function(f) {
      var v = Kt.get(f) - 1, p = s.get(f) - 1;
      Kt.set(f, v), s.set(f, p), v || ($a.has(f) || f.removeAttribute(n), $a.delete(f)), p || f.removeAttribute(e);
    }), _n--, _n || (Kt = /* @__PURE__ */ new WeakMap(), Kt = /* @__PURE__ */ new WeakMap(), $a = /* @__PURE__ */ new WeakMap(), Ba = {});
  };
}, Hi = function(a, t, e) {
  e === void 0 && (e = "data-aria-hidden");
  var n = Array.from(Array.isArray(a) ? a : [a]), l = Li(a);
  return l ? (n.push.apply(n, Array.from(l.querySelectorAll("[aria-live]"))), Ki(n, l, e, "aria-hidden")) : function() {
    return null;
  };
};
function ga(a) {
  let t;
  ee(() => $e(a), (e) => {
    e ? t = Hi(e) : t && t();
  }), Be(() => {
    t && t();
  });
}
let Wi = 0;
function ge(a, t = "radix") {
  if (a)
    return a;
  const e = Ya({ useId: void 0 });
  return No.useId ? `${t}-${No.useId()}` : e.useId ? `${t}-${e.useId()}` : `${t}-${++Wi}`;
}
function ji(a, t) {
  const e = T(), n = (s, r) => {
    if (t.multiple && Array.isArray(a.value))
      if (t.selectionBehavior === "replace")
        a.value = [s], e.value = s;
      else {
        const i = a.value.findIndex((u) => r(u));
        i !== -1 ? a.value.splice(i, 1) : a.value.push(s);
      }
    else
      t.selectionBehavior === "replace" ? a.value = { ...s } : !Array.isArray(a.value) && r(a.value) ? a.value = void 0 : a.value = { ...s };
    return a.value;
  };
  function l(s, r, i, u) {
    var v;
    if (!(e != null && e.value) || !t.multiple || !Array.isArray(a.value))
      return;
    const c = (v = i().filter((p) => p.ref.dataset.disabled !== "").find((p) => p.ref === r)) == null ? void 0 : v.value;
    if (!c)
      return;
    let f = null;
    switch (s) {
      case "prev":
      case "next": {
        f = Bt(u, e.value, c);
        break;
      }
      case "first": {
        f = Bt(u, e.value, u == null ? void 0 : u[0]);
        break;
      }
      case "last": {
        f = Bt(u, e.value, u == null ? void 0 : u[u.length - 1]);
        break;
      }
    }
    a.value = f;
  }
  return {
    firstValue: e,
    onSelectItem: n,
    handleMultipleReplace: l
  };
}
function Ll(a) {
  const t = T(), e = B(() => {
    var l;
    return ((l = t.value) == null ? void 0 : l.width) ?? 0;
  }), n = B(() => {
    var l;
    return ((l = t.value) == null ? void 0 : l.height) ?? 0;
  });
  return le(() => {
    const l = $e(a);
    if (l) {
      t.value = { width: l.offsetWidth, height: l.offsetHeight };
      const s = new ResizeObserver((r) => {
        if (!Array.isArray(r) || !r.length)
          return;
        const i = r[0];
        let u, d;
        if ("borderBoxSize" in i) {
          const c = i.borderBoxSize, f = Array.isArray(c) ? c[0] : c;
          u = f.inlineSize, d = f.blockSize;
        } else
          u = l.offsetWidth, d = l.offsetHeight;
        t.value = { width: u, height: d };
      });
      return s.observe(l, { box: "border-box" }), () => s.unobserve(l);
    } else
      t.value = void 0;
  }), {
    width: e,
    height: n
  };
}
function zl(a, t) {
  const e = T(a);
  function n(s) {
    return t[e.value][s] ?? e.value;
  }
  return {
    state: e,
    dispatch: (s) => {
      e.value = n(s);
    }
  };
}
const Ui = "data-item-text";
function ba(a) {
  const t = Tt("", 1e3);
  return {
    search: t,
    handleTypeaheadSearch: (l, s) => {
      if (!(a != null && a.value) && !s)
        return;
      t.value = t.value + l;
      const r = (a == null ? void 0 : a.value) ?? s, i = me(), u = r.map((p) => {
        var g;
        return {
          ref: p,
          textValue: ((g = (p.querySelector(`[${Ui}]`) ?? p).textContent) == null ? void 0 : g.trim()) ?? ""
        };
      }), d = u.find((p) => p.ref === i), c = u.map((p) => p.textValue), f = Zn(c, t.value, d == null ? void 0 : d.textValue), v = u.find((p) => p.textValue === f);
      return v && v.ref.focus(), v == null ? void 0 : v.ref;
    },
    resetTypeahead: () => {
      t.value = "";
    }
  };
}
function Xn(a, t) {
  return a.map((e, n) => a[(t + n) % a.length]);
}
function Zn(a, t, e) {
  const l = t.length > 1 && Array.from(t).every((d) => d === t[0]) ? t[0] : t, s = e ? a.indexOf(e) : -1;
  let r = Xn(a, Math.max(s, 0));
  l.length === 1 && (r = r.filter((d) => d !== e));
  const u = r.find(
    (d) => d.toLowerCase().startsWith(l.toLowerCase())
  );
  return u !== e ? u : void 0;
}
function Sv(a, t) {
  return {
    inheritAttrs: !1,
    name: `${a.__name ?? ""}Wrapper`,
    setup(e, n) {
      return () => {
        const l = typeof (t == null ? void 0 : t.props) == "function" ? t == null ? void 0 : t.props(n.attrs) : t == null ? void 0 : t.props, { forwardRef: s } = R(), r = k(l, n.attrs);
        return mt(a, { ...r, ref: s }, n.slots);
      };
    }
  };
}
function nt() {
  return {
    ALT: "Alt",
    ARROW_DOWN: "ArrowDown",
    ARROW_LEFT: "ArrowLeft",
    ARROW_RIGHT: "ArrowRight",
    ARROW_UP: "ArrowUp",
    BACKSPACE: "Backspace",
    CAPS_LOCK: "CapsLock",
    CONTROL: "Control",
    DELETE: "Delete",
    END: "End",
    ENTER: "Enter",
    ESCAPE: "Escape",
    F1: "F1",
    F10: "F10",
    F11: "F11",
    F12: "F12",
    F2: "F2",
    F3: "F3",
    F4: "F4",
    F5: "F5",
    F6: "F6",
    F7: "F7",
    F8: "F8",
    F9: "F9",
    HOME: "Home",
    META: "Meta",
    PAGE_DOWN: "PageDown",
    PAGE_UP: "PageUp",
    SHIFT: "Shift",
    SPACE: " ",
    TAB: "Tab",
    CTRL: "Control",
    ASTERISK: "*",
    SPACE_CODE: "Space"
  };
}
const Jn = x({
  name: "PrimitiveSlot",
  inheritAttrs: !1,
  setup(a, { attrs: t, slots: e }) {
    return () => {
      var u, d;
      if (!e.default)
        return null;
      const n = qa(e.default()), l = n.findIndex((c) => c.type !== hl);
      if (l === -1)
        return n;
      const s = n[l];
      (u = s.props) == null || delete u.ref;
      const r = s.props ? k(t, s.props) : t;
      t.class && ((d = s.props) != null && d.class) && delete s.props.class;
      const i = Ln(s, r);
      for (const c in r)
        c.startsWith("on") && (i.props || (i.props = {}), i.props[c] = r[c]);
      return n.length === 1 ? i : (n[l] = i, n);
    };
  }
}), O = x({
  name: "Primitive",
  inheritAttrs: !1,
  props: {
    asChild: {
      type: Boolean,
      default: !1
    },
    as: {
      type: [String, Object],
      default: "div"
    }
  },
  setup(a, { attrs: t, slots: e }) {
    const n = a.asChild ? "template" : a.as;
    return typeof n == "string" && ["area", "img", "input"].includes(n) ? () => mt(n, t) : n !== "template" ? () => mt(a.as, t, { default: e.default }) : () => mt(Jn, t, { default: e.default });
  }
});
function Re() {
  const a = T(), t = B(() => {
    var e, n;
    return ["#text", "#comment"].includes((e = a.value) == null ? void 0 : e.$el.nodeName) ? (n = a.value) == null ? void 0 : n.$el.nextElementSibling : $e(a);
  });
  return {
    primitiveElement: a,
    currentElement: t
  };
}
const [Kl, Gi] = te("CollapsibleRoot"), qi = /* @__PURE__ */ x({
  __name: "CollapsibleRoot",
  props: {
    defaultOpen: { type: Boolean, default: !1 },
    open: { type: Boolean, default: void 0 },
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:open"],
  setup(a, { expose: t, emit: e }) {
    const n = a, s = ne(n, "open", e, {
      defaultValue: n.defaultOpen,
      passive: n.open === void 0
    }), r = ne(n, "disabled");
    return Gi({
      contentId: "",
      disabled: r,
      open: s,
      onOpenToggle: () => {
        s.value = !s.value;
      }
    }), t({ open: s }), R(), (i, u) => (b(), S(o(O), {
      as: i.as,
      "as-child": n.asChild,
      "data-state": o(s) ? "open" : "closed",
      "data-disabled": o(r) ? "" : void 0
    }, {
      default: y(() => [
        w(i.$slots, "default", { open: o(s) })
      ]),
      _: 3
    }, 8, ["as", "as-child", "data-state", "data-disabled"]));
  }
}), Yi = /* @__PURE__ */ x({
  __name: "CollapsibleTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = Kl();
    return (n, l) => {
      var s, r;
      return b(), S(o(O), {
        type: n.as === "button" ? "button" : void 0,
        as: n.as,
        "as-child": t.asChild,
        "aria-controls": o(e).contentId,
        "aria-expanded": o(e).open.value,
        "data-state": o(e).open.value ? "open" : "closed",
        "data-disabled": (s = o(e).disabled) != null && s.value ? "" : void 0,
        disabled: (r = o(e).disabled) == null ? void 0 : r.value,
        onClick: o(e).onOpenToggle
      }, {
        default: y(() => [
          w(n.$slots, "default")
        ]),
        _: 3
      }, 8, ["type", "as", "as-child", "aria-controls", "aria-expanded", "data-state", "data-disabled", "disabled", "onClick"]);
    };
  }
});
function Xi(a, t) {
  var _;
  const e = T({}), n = T("none"), l = T(a), s = a.value ? "mounted" : "unmounted";
  let r;
  const i = ((_ = t.value) == null ? void 0 : _.ownerDocument.defaultView) ?? Rt, { state: u, dispatch: d } = zl(s, {
    mounted: {
      UNMOUNT: "unmounted",
      ANIMATION_OUT: "unmountSuspended"
    },
    unmountSuspended: {
      MOUNT: "mounted",
      ANIMATION_END: "unmounted"
    },
    unmounted: {
      MOUNT: "mounted"
    }
  }), c = (C) => {
    var $;
    if (Je) {
      const h = new CustomEvent(C, { bubbles: !1, cancelable: !1 });
      ($ = t.value) == null || $.dispatchEvent(h);
    }
  };
  ee(
    a,
    async (C, $) => {
      var E;
      const h = $ !== C;
      if (await oe(), h) {
        const P = n.value, D = Ia(t.value);
        C ? (d("MOUNT"), c("enter"), D === "none" && c("after-enter")) : D === "none" || ((E = e.value) == null ? void 0 : E.display) === "none" ? (d("UNMOUNT"), c("leave"), c("after-leave")) : $ && P !== D ? (d("ANIMATION_OUT"), c("leave")) : (d("UNMOUNT"), c("after-leave"));
      }
    },
    { immediate: !0 }
  );
  const f = (C) => {
    const $ = Ia(t.value), h = $.includes(
      C.animationName
    ), E = u.value === "mounted" ? "enter" : "leave";
    if (C.target === t.value && h && (c(`after-${E}`), d("ANIMATION_END"), !l.value)) {
      const P = t.value.style.animationFillMode;
      t.value.style.animationFillMode = "forwards", r = i == null ? void 0 : i.setTimeout(() => {
        var D;
        ((D = t.value) == null ? void 0 : D.style.animationFillMode) === "forwards" && (t.value.style.animationFillMode = P);
      });
    }
    C.target === t.value && $ === "none" && d("ANIMATION_END");
  }, v = (C) => {
    C.target === t.value && (n.value = Ia(t.value));
  }, p = ee(
    t,
    (C, $) => {
      C ? (e.value = getComputedStyle(C), C.addEventListener("animationstart", v), C.addEventListener("animationcancel", f), C.addEventListener("animationend", f)) : (d("ANIMATION_END"), r !== void 0 && (i == null || i.clearTimeout(r)), $ == null || $.removeEventListener("animationstart", v), $ == null || $.removeEventListener("animationcancel", f), $ == null || $.removeEventListener("animationend", f));
    },
    { immediate: !0 }
  ), g = ee(u, () => {
    const C = Ia(t.value);
    n.value = u.value === "mounted" ? C : "none";
  });
  return Be(() => {
    p(), g();
  }), {
    isPresent: B(
      () => ["mounted", "unmountSuspended"].includes(u.value)
    )
  };
}
function Ia(a) {
  return a && getComputedStyle(a).animationName || "none";
}
const Pe = x({
  name: "Presence",
  props: {
    present: {
      type: Boolean,
      required: !0
    },
    forceMount: {
      type: Boolean
    }
  },
  slots: {},
  setup(a, { slots: t, expose: e }) {
    var d;
    const { present: n, forceMount: l } = ae(a), s = T(), { isPresent: r } = Xi(n, s);
    e({ present: r });
    let i = t.default({ present: r });
    i = qa(i || []);
    const u = gt();
    if (i && (i == null ? void 0 : i.length) > 1) {
      const c = (d = u == null ? void 0 : u.parent) != null && d.type.name ? `<${u.parent.type.name} />` : "component";
      throw new Error(
        [
          `Detected an invalid children for \`${c}\` for  \`Presence\` component.`,
          "",
          "Note: Presence works similarly to `v-if` directly, but it waits for animation/transition to finished before unmounting. So it expect only one direct child of valid VNode type.",
          "You can apply a few solutions:",
          [
            "Provide a single child element so that `presence` directive attach correctly.",
            "Ensure the first child is an actual element instead of a raw text node or comment node."
          ].map((f) => `  - ${f}`).join(`
`)
        ].join(`
`)
      );
    }
    return () => l.value || n.value || r.value ? mt(t.default({ present: r })[0], {
      ref: (c) => {
        const f = $e(c);
        return typeof (f == null ? void 0 : f.hasAttribute) > "u" || (f != null && f.hasAttribute("data-radix-popper-content-wrapper") ? s.value = f.firstElementChild : s.value = f), f;
      }
    }) : null;
  }
}), Zi = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "CollapsibleContent",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Kl();
    e.contentId || (e.contentId = ge(void 0, "radix-vue-collapsible-content"));
    const n = T(), { forwardRef: l, currentElement: s } = R(), r = T(0), i = T(0), u = B(() => e.open.value), d = T(u.value), c = T();
    return ee(
      () => {
        var f;
        return [u.value, (f = n.value) == null ? void 0 : f.present];
      },
      async () => {
        await oe();
        const f = s.value;
        if (!f)
          return;
        c.value = c.value || {
          transitionDuration: f.style.transitionDuration,
          animationName: f.style.animationName
        }, f.style.transitionDuration = "0s", f.style.animationName = "none";
        const v = f.getBoundingClientRect();
        i.value = v.height, r.value = v.width, d.value || (f.style.transitionDuration = c.value.transitionDuration, f.style.animationName = c.value.animationName);
      },
      {
        immediate: !0
      }
    ), le(() => {
      requestAnimationFrame(() => {
        d.value = !1;
      });
    }), (f, v) => (b(), S(o(Pe), {
      ref_key: "presentRef",
      ref: n,
      present: f.forceMount || o(e).open.value,
      "force-mount": !0
    }, {
      default: y(() => {
        var p, g;
        return [
          q(o(O), k(f.$attrs, {
            id: o(e).contentId,
            ref: o(l),
            "as-child": t.asChild,
            as: f.as,
            "data-state": o(e).open.value ? "open" : "closed",
            "data-disabled": (p = o(e).disabled) != null && p.value ? "" : void 0,
            hidden: !((g = n.value) != null && g.present),
            style: {
              "--radix-collapsible-content-height": `${i.value}px`,
              "--radix-collapsible-content-width": `${r.value}px`
            }
          }), {
            default: y(() => {
              var m;
              return [
                (m = n.value) != null && m.present ? w(f.$slots, "default", { key: 0 }) : ce("", !0)
              ];
            }),
            _: 3
          }, 16, ["id", "as-child", "as", "data-state", "data-disabled", "hidden", "style"])
        ];
      }),
      _: 3
    }, 8, ["present"]));
  }
});
function Hl({ type: a, defaultValue: t, modelValue: e }) {
  const n = e || t;
  if (ht(a) && ht(e) && ht(t))
    throw new Error("Either the `type` or the `value` or `default-value` prop must be defined.");
  if (e !== void 0 && t !== void 0 && typeof e != typeof t)
    throw new Error(
      `Invalid prop \`value\` of value \`${e}\` supplied, should be the same type as the \`defaultValue\` prop, which is \`${t}\`. The \`value\` prop must be:
  ${a === "single" ? "- a string" : a === "multiple" ? "- an array of strings" : `- a string
- an array of strings`}
  - \`undefined\``
    );
  const l = e !== void 0 || t !== void 0;
  if (a && l) {
    const s = Array.isArray(e) || Array.isArray(t), r = e !== void 0 ? "modelValue" : "defaultValue", i = r === "modelValue" ? typeof e : typeof t;
    if (a === "single" && s)
      return console.error(`Invalid prop \`${r}\` of type ${i} supplied with type \`single\`. The \`modelValue\` prop must be a string or \`undefined\`.
    You can remove the \`type\` prop to let the component infer the type from the ${r} prop.`), "multiple";
    if (a === "multiple" && !s)
      return console.error(`Invalid prop \`${r}\` of type ${i} supplied with type \`multiple\`. The \`modelValue\` prop must be an array of strings or \`undefined\`.
    You can remove the \`type\` prop to let the component infer the type from the ${r} prop.`), "single";
  }
  return l ? Array.isArray(n) ? "multiple" : "single" : a;
}
function Ji({ type: a, defaultValue: t, modelValue: e }) {
  return a || Hl({ type: a, defaultValue: t, modelValue: e });
}
function Qi({ type: a, defaultValue: t }) {
  return t !== void 0 ? t : a === "single" ? void 0 : [];
}
function Wl(a, t) {
  const e = T(Ji(a)), n = ne(a, "modelValue", t, {
    defaultValue: Qi(a),
    passive: a.modelValue === void 0,
    deep: !0
  });
  ee(
    () => [a.type, a.modelValue, a.defaultValue],
    () => {
      const r = Hl(a);
      e.value !== r && (e.value = r);
    },
    { immediate: !0 }
  );
  function l(r) {
    if (e.value === "single")
      n.value = r === n.value ? void 0 : r;
    else {
      const i = [...n.value || []];
      if (i.includes(r)) {
        const u = i.findIndex((d) => d === r);
        i.splice(u, 1);
      } else
        i.push(r);
      n.value = i;
    }
  }
  const s = B(() => e.value === "single");
  return {
    modelValue: n,
    type: e,
    changeModelValue: l,
    isSingle: s
  };
}
const [Xa, eu] = te("AccordionRoot"), Ev = /* @__PURE__ */ x({
  __name: "AccordionRoot",
  props: {
    collapsible: { type: Boolean, default: !1 },
    disabled: { type: Boolean, default: !1 },
    dir: {},
    orientation: { default: "vertical" },
    asChild: { type: Boolean },
    as: {},
    type: {},
    modelValue: {},
    defaultValue: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { dir: l, disabled: s } = ae(e), r = we(l), { modelValue: i, changeModelValue: u, isSingle: d } = Wl(e, n), { forwardRef: c, currentElement: f } = R();
    return eu({
      disabled: s,
      direction: r,
      orientation: e.orientation,
      parentElement: f,
      isSingle: d,
      collapsible: e.collapsible,
      modelValue: i,
      changeModelValue: u
    }), (v, p) => (b(), S(o(O), {
      ref: o(c),
      "as-child": v.asChild,
      as: v.as
    }, {
      default: y(() => [
        w(v.$slots, "default", { modelValue: o(i) })
      ]),
      _: 3
    }, 8, ["as-child", "as"]));
  }
}), [Qn, tu] = te("AccordionItem"), Pv = /* @__PURE__ */ x({
  __name: "AccordionItem",
  props: {
    disabled: { type: Boolean },
    value: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a, { expose: t }) {
    const e = a, n = Xa(), l = B(
      () => n.isSingle.value ? e.value === n.modelValue.value : Array.isArray(n.modelValue.value) && n.modelValue.value.includes(e.value)
    ), s = B(() => n.disabled.value || e.disabled), r = B(() => s.value ? "" : void 0), i = B(
      () => l.value ? "open" : "closed"
      /* Closed */
    );
    t({ open: l, dataDisabled: r });
    const { currentRef: u, currentElement: d } = R();
    tu({
      open: l,
      dataState: i,
      disabled: s,
      dataDisabled: r,
      triggerId: "",
      currentRef: u,
      currentElement: d,
      value: B(() => e.value)
    });
    function c(f) {
      var m;
      const v = f.target;
      if (Array.from(((m = n.parentElement.value) == null ? void 0 : m.querySelectorAll("[data-radix-vue-collection-item]")) ?? []).findIndex((_) => _ === v) === -1)
        return null;
      At(
        f,
        d.value,
        n.parentElement.value,
        {
          arrowKeyOptions: n.orientation,
          dir: n.direction.value,
          focus: !0
        }
      );
    }
    return (f, v) => (b(), S(o(qi), {
      "data-orientation": o(n).orientation,
      "data-disabled": r.value,
      "data-state": i.value,
      disabled: s.value,
      open: l.value,
      as: e.as,
      "as-child": e.asChild,
      onKeydown: ie(c, ["up", "down", "left", "right", "home", "end"])
    }, {
      default: y(() => [
        w(f.$slots, "default", { open: l.value })
      ]),
      _: 3
    }, 8, ["data-orientation", "data-disabled", "data-state", "disabled", "open", "as", "as-child"]));
  }
}), Dv = /* @__PURE__ */ x({
  __name: "AccordionContent",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Xa(), n = Qn();
    return R(), (l, s) => (b(), S(o(Zi), {
      role: "region",
      hidden: !o(n).open.value,
      "as-child": t.asChild,
      "force-mount": t.forceMount,
      "aria-labelledby": o(n).triggerId,
      "data-state": o(n).dataState.value,
      "data-disabled": o(n).dataDisabled.value,
      "data-orientation": o(e).orientation,
      style: { "--radix-accordion-content-width": "var(--radix-collapsible-content-width)", "--radix-accordion-content-height": "var(--radix-collapsible-content-height)" }
    }, {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 8, ["hidden", "as-child", "force-mount", "aria-labelledby", "data-state", "data-disabled", "data-orientation"]));
  }
}), $v = /* @__PURE__ */ x({
  __name: "AccordionHeader",
  props: {
    asChild: { type: Boolean },
    as: { default: "h3" }
  },
  setup(a) {
    const t = a, e = Xa(), n = Qn();
    return R(), (l, s) => (b(), S(o(O), {
      as: t.as,
      "as-child": t.asChild,
      "data-orientation": o(e).orientation,
      "data-state": o(n).dataState.value,
      "data-disabled": o(n).dataDisabled.value
    }, {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child", "data-orientation", "data-state", "data-disabled"]));
  }
}), Bv = /* @__PURE__ */ x({
  __name: "AccordionTrigger",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Xa(), n = Qn();
    n.triggerId || (n.triggerId = ge(void 0, "radix-vue-accordion-trigger"));
    function l() {
      const s = e.isSingle.value && n.open.value && !e.collapsible;
      n.disabled.value || s || e.changeModelValue(n.value.value);
    }
    return (s, r) => (b(), S(o(Yi), {
      id: o(n).triggerId,
      ref: o(n).currentRef,
      "data-radix-vue-collection-item": "",
      as: t.as,
      "as-child": t.asChild,
      "aria-disabled": o(n).disabled.value || void 0,
      "aria-expanded": o(n).open.value || !1,
      "data-disabled": o(n).dataDisabled.value,
      "data-orientation": o(e).orientation,
      "data-state": o(n).dataState.value,
      disabled: o(n).disabled.value,
      onClick: l
    }, {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 8, ["id", "as", "as-child", "aria-disabled", "aria-expanded", "data-disabled", "data-orientation", "data-state", "disabled"]));
  }
}), [ot, au] = te("DialogRoot"), nu = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "DialogRoot",
  props: {
    open: { type: Boolean, default: void 0 },
    defaultOpen: { type: Boolean, default: !1 },
    modal: { type: Boolean, default: !0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "open", t, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    }), s = T(), r = T(), { modal: i } = ae(e);
    return au({
      open: l,
      modal: i,
      openModal: () => {
        l.value = !0;
      },
      onOpenChange: (u) => {
        l.value = u;
      },
      onOpenToggle: () => {
        l.value = !l.value;
      },
      contentId: "",
      titleId: "",
      descriptionId: "",
      triggerElement: s,
      contentElement: r
    }), (u, d) => w(u.$slots, "default", { open: o(l) });
  }
}), ou = /* @__PURE__ */ x({
  __name: "DialogTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = ot(), { forwardRef: n, currentElement: l } = R();
    return e.contentId || (e.contentId = ge(void 0, "radix-vue-dialog-content")), le(() => {
      e.triggerElement.value = l.value;
    }), (s, r) => (b(), S(o(O), k(t, {
      ref: o(n),
      type: s.as === "button" ? "button" : void 0,
      "aria-haspopup": "dialog",
      "aria-expanded": o(e).open.value || !1,
      "aria-controls": o(e).open.value ? o(e).contentId : void 0,
      "data-state": o(e).open.value ? "open" : "closed",
      onClick: o(e).onOpenToggle
    }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16, ["type", "aria-expanded", "aria-controls", "data-state", "onClick"]));
  }
}), rt = /* @__PURE__ */ x({
  __name: "Teleport",
  props: {
    to: { default: "body" },
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = Ga();
    return (e, n) => o(t) || e.forceMount ? (b(), S(qt, {
      key: 0,
      to: e.to,
      disabled: e.disabled
    }, [
      w(e.$slots, "default")
    ], 8, ["to", "disabled"])) : ce("", !0);
  }
}), Iv = /* @__PURE__ */ x({
  __name: "DialogPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), lu = "dismissableLayer.pointerDownOutside", su = "dismissableLayer.focusOutside";
function jl(a, t) {
  const e = t.closest(
    "[data-dismissable-layer]"
  ), n = a.dataset.dismissableLayer === "" ? a : a.querySelector(
    "[data-dismissable-layer]"
  ), l = Array.from(
    a.ownerDocument.querySelectorAll("[data-dismissable-layer]")
  );
  return !!(e && n === e || l.indexOf(n) < l.indexOf(e));
}
function Ul(a, t) {
  var s;
  const e = ((s = t == null ? void 0 : t.value) == null ? void 0 : s.ownerDocument) ?? (globalThis == null ? void 0 : globalThis.document), n = T(!1), l = T(() => {
  });
  return Ce((r) => {
    if (!Je)
      return;
    const i = async (d) => {
      const c = d.target;
      if (t != null && t.value) {
        if (jl(t.value, c)) {
          n.value = !1;
          return;
        }
        if (d.target && !n.value) {
          let f = function() {
            jt(
              lu,
              a,
              v
            );
          };
          const v = { originalEvent: d };
          d.pointerType === "touch" ? (e.removeEventListener("click", l.value), l.value = f, e.addEventListener("click", l.value, {
            once: !0
          })) : f();
        } else
          e.removeEventListener("click", l.value);
        n.value = !1;
      }
    }, u = window.setTimeout(() => {
      e.addEventListener("pointerdown", i);
    }, 0);
    r(() => {
      window.clearTimeout(u), e.removeEventListener("pointerdown", i), e.removeEventListener("click", l.value);
    });
  }), {
    onPointerDownCapture: () => n.value = !0
  };
}
function Gl(a, t) {
  var l;
  const e = ((l = t == null ? void 0 : t.value) == null ? void 0 : l.ownerDocument) ?? (globalThis == null ? void 0 : globalThis.document), n = T(!1);
  return Ce((s) => {
    if (!Je)
      return;
    const r = async (i) => {
      t != null && t.value && (await oe(), !(!t.value || jl(t.value, i.target)) && i.target && !n.value && jt(
        su,
        a,
        { originalEvent: i }
      ));
    };
    e.addEventListener("focusin", r), s(() => e.removeEventListener("focusin", r));
  }), {
    onFocusCapture: () => n.value = !0,
    onBlurCapture: () => n.value = !1
  };
}
const Ge = Fa({
  layersRoot: /* @__PURE__ */ new Set(),
  layersWithOutsidePointerEventsDisabled: /* @__PURE__ */ new Set(),
  branches: /* @__PURE__ */ new Set()
}), Ct = /* @__PURE__ */ x({
  __name: "DismissableLayer",
  props: {
    disableOutsidePointerEvents: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "dismiss"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l, currentElement: s } = R(), r = B(
      () => {
        var g;
        return ((g = s.value) == null ? void 0 : g.ownerDocument) ?? globalThis.document;
      }
    ), i = B(() => Ge.layersRoot), u = B(() => s.value ? Array.from(i.value).indexOf(s.value) : -1), d = B(() => Ge.layersWithOutsidePointerEventsDisabled.size > 0), c = B(() => {
      const g = Array.from(i.value), [m] = [...Ge.layersWithOutsidePointerEventsDisabled].slice(-1), _ = g.indexOf(m);
      return u.value >= _;
    }), f = Ul(async (g) => {
      const m = [...Ge.branches].some(
        (_) => _ == null ? void 0 : _.contains(g.target)
      );
      !c.value || m || (n("pointerDownOutside", g), n("interactOutside", g), await oe(), g.defaultPrevented || n("dismiss"));
    }, s), v = Gl((g) => {
      [...Ge.branches].some(
        (_) => _ == null ? void 0 : _.contains(g.target)
      ) || (n("focusOutside", g), n("interactOutside", g), g.defaultPrevented || n("dismiss"));
    }, s);
    Gn("Escape", (g) => {
      u.value === i.value.size - 1 && (n("escapeKeyDown", g), g.defaultPrevented || n("dismiss"));
    });
    let p;
    return Ce((g) => {
      s.value && (e.disableOutsidePointerEvents && (Ge.layersWithOutsidePointerEventsDisabled.size === 0 && (p = r.value.body.style.pointerEvents, r.value.body.style.pointerEvents = "none"), Ge.layersWithOutsidePointerEventsDisabled.add(s.value)), i.value.add(s.value), g(() => {
        e.disableOutsidePointerEvents && Ge.layersWithOutsidePointerEventsDisabled.size === 1 && (r.value.body.style.pointerEvents = p);
      }));
    }), Ce((g) => {
      g(() => {
        s.value && (i.value.delete(s.value), Ge.layersWithOutsidePointerEventsDisabled.delete(s.value));
      });
    }), (g, m) => (b(), S(o(O), {
      ref: o(l),
      "as-child": g.asChild,
      as: g.as,
      "data-dismissable-layer": "",
      style: Me({
        pointerEvents: d.value ? c.value ? "auto" : "none" : void 0
      }),
      onFocusCapture: o(v).onFocusCapture,
      onBlurCapture: o(v).onBlurCapture,
      onPointerdownCapture: o(f).onPointerDownCapture
    }, {
      default: y(() => [
        w(g.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as", "style", "onFocusCapture", "onBlurCapture", "onPointerdownCapture"]));
  }
}), ru = /* @__PURE__ */ x({
  __name: "DismissableLayerBranch",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e, currentElement: n } = R();
    return le(() => {
      Ge.branches.add(n.value);
    }), Be(() => {
      Ge.branches.delete(n.value);
    }), (l, s) => (b(), S(o(O), k({ ref: o(e) }, t), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), xn = "focusScope.autoFocusOnMount", Sn = "focusScope.autoFocusOnUnmount", qo = { bubbles: !1, cancelable: !0 };
function Ma(a, { select: t = !1 } = {}) {
  const e = me();
  for (const n of a)
    if (pt(n, { select: t }), me() !== e)
      return !0;
}
function iu(a) {
  const t = eo(a), e = Yo(t, a), n = Yo(t.reverse(), a);
  return [e, n];
}
function eo(a) {
  const t = [], e = document.createTreeWalker(a, NodeFilter.SHOW_ELEMENT, {
    acceptNode: (n) => {
      const l = n.tagName === "INPUT" && n.type === "hidden";
      return n.disabled || n.hidden || l ? NodeFilter.FILTER_SKIP : n.tabIndex >= 0 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
    }
  });
  for (; e.nextNode(); ) t.push(e.currentNode);
  return t;
}
function Yo(a, t) {
  for (const e of a)
    if (!uu(e, { upTo: t }))
      return e;
}
function uu(a, { upTo: t }) {
  if (getComputedStyle(a).visibility === "hidden")
    return !0;
  for (; a; ) {
    if (t !== void 0 && a === t)
      return !1;
    if (getComputedStyle(a).display === "none")
      return !0;
    a = a.parentElement;
  }
  return !1;
}
function du(a) {
  return a instanceof HTMLInputElement && "select" in a;
}
function pt(a, { select: t = !1 } = {}) {
  if (a && a.focus) {
    const e = me();
    a.focus({ preventScroll: !0 }), a !== e && du(a) && t && a.select();
  }
}
const cu = li(() => T([]));
function fu() {
  const a = cu();
  return {
    add(t) {
      const e = a.value[0];
      t !== e && (e == null || e.pause()), a.value = Xo(a.value, t), a.value.unshift(t);
    },
    remove(t) {
      var e;
      a.value = Xo(a.value, t), (e = a.value[0]) == null || e.resume();
    }
  };
}
function Xo(a, t) {
  const e = [...a], n = e.indexOf(t);
  return n !== -1 && e.splice(n, 1), e;
}
function pu(a) {
  return a.filter((t) => t.tagName !== "A");
}
const Za = /* @__PURE__ */ x({
  __name: "FocusScope",
  props: {
    loop: { type: Boolean, default: !1 },
    trapped: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["mountAutoFocus", "unmountAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, { currentRef: l, currentElement: s } = R(), r = T(null), i = fu(), u = Fa({
      paused: !1,
      pause() {
        this.paused = !0;
      },
      resume() {
        this.paused = !1;
      }
    });
    Ce((c) => {
      if (!Je)
        return;
      const f = s.value;
      if (!e.trapped)
        return;
      function v(_) {
        if (u.paused || !f)
          return;
        const C = _.target;
        f.contains(C) ? r.value = C : pt(r.value, { select: !0 });
      }
      function p(_) {
        if (u.paused || !f)
          return;
        const C = _.relatedTarget;
        C !== null && (f.contains(C) || pt(r.value, { select: !0 }));
      }
      function g(_) {
        f.contains(r.value) || pt(f);
      }
      document.addEventListener("focusin", v), document.addEventListener("focusout", p);
      const m = new MutationObserver(g);
      f && m.observe(f, { childList: !0, subtree: !0 }), c(() => {
        document.removeEventListener("focusin", v), document.removeEventListener("focusout", p), m.disconnect();
      });
    }), Ce(async (c) => {
      const f = s.value;
      if (await oe(), !f)
        return;
      i.add(u);
      const v = me();
      if (!f.contains(v)) {
        const g = new CustomEvent(xn, qo);
        f.addEventListener(xn, (m) => n("mountAutoFocus", m)), f.dispatchEvent(g), g.defaultPrevented || (Ma(pu(eo(f)), {
          select: !0
        }), me() === v && pt(f));
      }
      c(() => {
        f.removeEventListener(xn, (_) => n("mountAutoFocus", _));
        const g = new CustomEvent(Sn, qo), m = (_) => {
          n("unmountAutoFocus", _);
        };
        f.addEventListener(Sn, m), f.dispatchEvent(g), setTimeout(() => {
          g.defaultPrevented || pt(v ?? document.body, { select: !0 }), f.removeEventListener(Sn, m), i.remove(u);
        }, 0);
      });
    });
    function d(c) {
      if (!e.loop && !e.trapped || u.paused)
        return;
      const f = c.key === "Tab" && !c.altKey && !c.ctrlKey && !c.metaKey, v = me();
      if (f && v) {
        const p = c.currentTarget, [g, m] = iu(p);
        g && m ? !c.shiftKey && v === m ? (c.preventDefault(), e.loop && pt(g, { select: !0 })) : c.shiftKey && v === g && (c.preventDefault(), e.loop && pt(m, { select: !0 })) : v === p && c.preventDefault();
      }
    }
    return (c, f) => (b(), S(o(O), {
      ref_key: "currentRef",
      ref: l,
      tabindex: "-1",
      "as-child": c.asChild,
      as: c.as,
      onKeydown: d
    }, {
      default: y(() => [
        w(c.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as"]));
  }
}), vu = "menu.itemSelect", Bn = ["Enter", " "], mu = ["ArrowDown", "PageUp", "Home"], ql = ["ArrowUp", "PageDown", "End"], hu = [...mu, ...ql], yu = {
  ltr: [...Bn, "ArrowRight"],
  rtl: [...Bn, "ArrowLeft"]
}, gu = {
  ltr: ["ArrowLeft"],
  rtl: ["ArrowRight"]
};
function to(a) {
  return a ? "open" : "closed";
}
function La(a) {
  return a === "indeterminate";
}
function ao(a) {
  return La(a) ? "indeterminate" : a ? "checked" : "unchecked";
}
function In(a) {
  const t = me();
  for (const e of a)
    if (e === t || (e.focus(), me() !== t))
      return;
}
function bu(a, t) {
  const { x: e, y: n } = a;
  let l = !1;
  for (let s = 0, r = t.length - 1; s < t.length; r = s++) {
    const i = t[s].x, u = t[s].y, d = t[r].x, c = t[r].y;
    u > n != c > n && e < (d - i) * (n - u) / (c - u) + i && (l = !l);
  }
  return l;
}
function Cu(a, t) {
  if (!t)
    return !1;
  const e = { x: a.clientX, y: a.clientY };
  return bu(e, t);
}
function da(a) {
  return a.pointerType === "mouse";
}
const wu = "DialogTitle", _u = "DialogContent";
function xu({
  titleName: a = wu,
  contentName: t = _u,
  componentLink: e = "dialog.html#title",
  titleId: n,
  descriptionId: l,
  contentElement: s
}) {
  const r = `Warning: \`${t}\` requires a \`${a}\` for the component to be accessible for screen reader users.

If you want to hide the \`${a}\`, you can wrap it with our VisuallyHidden component.

For more information, see https://www.radix-vue.com/components/${e}`, i = `Warning: Missing \`Description\` or \`aria-describedby="undefined"\` for ${t}.`;
  le(() => {
    var c;
    document.getElementById(n) || console.warn(r);
    const d = (c = s.value) == null ? void 0 : c.getAttribute("aria-describedby");
    l && d && (document.getElementById(l) || console.warn(i));
  });
}
const Yl = /* @__PURE__ */ x({
  __name: "DialogContentImpl",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = ot(), { forwardRef: s, currentElement: r } = R();
    return l.titleId || (l.titleId = ge(void 0, "radix-vue-dialog-title")), l.descriptionId || (l.descriptionId = ge(void 0, "radix-vue-dialog-description")), le(() => {
      l.contentElement = r, me() !== document.body && (l.triggerElement.value = me());
    }), process.env.NODE_ENV !== "production" && xu({
      titleName: "DialogTitle",
      contentName: "DialogContent",
      componentLink: "dialog.html#title",
      titleId: l.titleId,
      descriptionId: l.descriptionId,
      contentElement: r
    }), (i, u) => (b(), S(o(Za), {
      "as-child": "",
      loop: "",
      trapped: e.trapFocus,
      onMountAutoFocus: u[5] || (u[5] = (d) => n("openAutoFocus", d)),
      onUnmountAutoFocus: u[6] || (u[6] = (d) => n("closeAutoFocus", d))
    }, {
      default: y(() => [
        q(o(Ct), k({
          id: o(l).contentId,
          ref: o(s),
          as: i.as,
          "as-child": i.asChild,
          "disable-outside-pointer-events": i.disableOutsidePointerEvents,
          role: "dialog",
          "aria-describedby": o(l).descriptionId,
          "aria-labelledby": o(l).titleId,
          "data-state": o(to)(o(l).open.value)
        }, i.$attrs, {
          onDismiss: u[0] || (u[0] = (d) => o(l).onOpenChange(!1)),
          onEscapeKeyDown: u[1] || (u[1] = (d) => n("escapeKeyDown", d)),
          onFocusOutside: u[2] || (u[2] = (d) => n("focusOutside", d)),
          onInteractOutside: u[3] || (u[3] = (d) => n("interactOutside", d)),
          onPointerDownOutside: u[4] || (u[4] = (d) => n("pointerDownOutside", d))
        }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16, ["id", "as", "as-child", "disable-outside-pointer-events", "aria-describedby", "aria-labelledby", "data-state"])
      ]),
      _: 3
    }, 8, ["trapped"]));
  }
}), Su = /* @__PURE__ */ x({
  __name: "DialogContentModal",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = ot(), s = Te(n), { forwardRef: r, currentElement: i } = R();
    return ga(i), (u, d) => (b(), S(Yl, k({ ...e, ...o(s) }, {
      ref: o(r),
      "trap-focus": o(l).open.value,
      "disable-outside-pointer-events": !0,
      onCloseAutoFocus: d[0] || (d[0] = (c) => {
        var f;
        c.defaultPrevented || (c.preventDefault(), (f = o(l).triggerElement.value) == null || f.focus());
      }),
      onPointerDownOutside: d[1] || (d[1] = (c) => {
        const f = c.detail.originalEvent, v = f.button === 0 && f.ctrlKey === !0;
        (f.button === 2 || v) && c.preventDefault();
      }),
      onFocusOutside: d[2] || (d[2] = (c) => {
        c.preventDefault();
      })
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16, ["trap-focus"]));
  }
}), Eu = /* @__PURE__ */ x({
  __name: "DialogContentNonModal",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    R();
    const s = ot(), r = T(!1), i = T(!1);
    return (u, d) => (b(), S(Yl, k({ ...e, ...o(l) }, {
      "trap-focus": !1,
      "disable-outside-pointer-events": !1,
      onCloseAutoFocus: d[0] || (d[0] = (c) => {
        var f;
        c.defaultPrevented || (r.value || (f = o(s).triggerElement.value) == null || f.focus(), c.preventDefault()), r.value = !1, i.value = !1;
      }),
      onInteractOutside: d[1] || (d[1] = (c) => {
        var p;
        c.defaultPrevented || (r.value = !0, c.detail.originalEvent.type === "pointerdown" && (i.value = !0));
        const f = c.target;
        ((p = o(s).triggerElement.value) == null ? void 0 : p.contains(f)) && c.preventDefault(), c.detail.originalEvent.type === "focusin" && i.value && c.preventDefault();
      })
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Pu = /* @__PURE__ */ x({
  __name: "DialogContent",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = ot(), s = Te(n), { forwardRef: r } = R();
    return (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(l).open.value
    }, {
      default: y(() => [
        o(l).modal.value ? (b(), S(Su, k({
          key: 0,
          ref: o(r)
        }, { ...e, ...o(s), ...i.$attrs }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16)) : (b(), S(Eu, k({
          key: 1,
          ref: o(r)
        }, { ...e, ...o(s), ...i.$attrs }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16))
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Du = /* @__PURE__ */ x({
  __name: "DialogOverlayImpl",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = ot();
    return ya(!0), R(), (e, n) => (b(), S(o(O), {
      as: e.as,
      "as-child": e.asChild,
      "data-state": o(t).open.value ? "open" : "closed",
      style: { "pointer-events": "auto" }
    }, {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child", "data-state"]));
  }
}), $u = /* @__PURE__ */ x({
  __name: "DialogOverlay",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = ot(), { forwardRef: e } = R();
    return (n, l) => {
      var s;
      return (s = o(t)) != null && s.modal.value ? (b(), S(o(Pe), {
        key: 0,
        present: n.forceMount || o(t).open.value
      }, {
        default: y(() => [
          q(Du, k(n.$attrs, {
            ref: o(e),
            as: n.as,
            "as-child": n.asChild
          }), {
            default: y(() => [
              w(n.$slots, "default")
            ]),
            _: 3
          }, 16, ["as", "as-child"])
        ]),
        _: 3
      }, 8, ["present"])) : ce("", !0);
    };
  }
}), Xl = /* @__PURE__ */ x({
  __name: "DialogClose",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = ot();
    return (n, l) => (b(), S(o(O), k(t, {
      type: n.as === "button" ? "button" : void 0,
      onClick: l[0] || (l[0] = (s) => o(e).onOpenChange(!1))
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["type"]));
  }
}), Bu = /* @__PURE__ */ x({
  __name: "DialogTitle",
  props: {
    asChild: { type: Boolean },
    as: { default: "h2" }
  },
  setup(a) {
    const t = a, e = ot();
    return R(), (n, l) => (b(), S(o(O), k(t, {
      id: o(e).titleId
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), Iu = /* @__PURE__ */ x({
  __name: "DialogDescription",
  props: {
    asChild: { type: Boolean },
    as: { default: "p" }
  },
  setup(a) {
    const t = a;
    R();
    const e = ot();
    return (n, l) => (b(), S(o(O), k(t, {
      id: o(e).descriptionId
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), Tv = /* @__PURE__ */ x({
  __name: "AlertDialogRoot",
  props: {
    open: { type: Boolean },
    defaultOpen: { type: Boolean }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return R(), (s, r) => (b(), S(o(nu), k(o(l), { modal: !0 }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Rv = /* @__PURE__ */ x({
  __name: "AlertDialogTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(ou), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Av = /* @__PURE__ */ x({
  __name: "AlertDialogPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [Tu, Ru] = te("AlertDialogContent"), Ov = /* @__PURE__ */ x({
  __name: "AlertDialogContent",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    R();
    const s = T();
    return Ru({
      onCancelElementChange: (r) => {
        s.value = r;
      }
    }), (r, i) => (b(), S(o(Pu), k({ ...e, ...o(l) }, {
      role: "alertdialog",
      onPointerDownOutside: i[0] || (i[0] = ue(() => {
      }, ["prevent"])),
      onInteractOutside: i[1] || (i[1] = ue(() => {
      }, ["prevent"])),
      onOpenAutoFocus: i[2] || (i[2] = () => {
        oe(() => {
          var u;
          (u = s.value) == null || u.focus({
            preventScroll: !0
          });
        });
      })
    }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), kv = /* @__PURE__ */ x({
  __name: "AlertDialogOverlay",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o($u), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Mv = /* @__PURE__ */ x({
  __name: "AlertDialogCancel",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = Tu(), { forwardRef: n, currentElement: l } = R();
    return le(() => {
      e.onCancelElementChange(l.value);
    }), (s, r) => (b(), S(o(Xl), k(t, { ref: o(n) }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Vv = /* @__PURE__ */ x({
  __name: "AlertDialogTitle",
  props: {
    asChild: { type: Boolean },
    as: { default: "h2" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Bu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Fv = /* @__PURE__ */ x({
  __name: "AlertDialogDescription",
  props: {
    asChild: { type: Boolean },
    as: { default: "p" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Iu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Nv = /* @__PURE__ */ x({
  __name: "AlertDialogAction",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Xl), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Lv = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "AspectRatio",
  props: {
    ratio: { default: 1 },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), n = B(() => 1 / t.ratio * 100);
    return (l, s) => (b(), ve("div", {
      style: Me(`position: relative; width: 100%; padding-bottom: ${n.value}%`),
      "data-radix-aspect-ratio-wrapper": ""
    }, [
      q(o(O), k({
        ref: o(e),
        "as-child": l.asChild,
        as: l.as,
        style: { position: "absolute", inset: "0px" }
      }, l.$attrs), {
        default: y(() => [
          w(l.$slots, "default", { aspect: n.value })
        ]),
        _: 3
      }, 16, ["as-child", "as"])
    ], 4));
  }
}), [Zl, Au] = te("AvatarRoot"), zv = /* @__PURE__ */ x({
  __name: "AvatarRoot",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    return R(), Au({
      imageLoadingStatus: T("loading")
    }), (t, e) => (b(), S(o(O), {
      "as-child": t.asChild,
      as: t.as
    }, {
      default: y(() => [
        w(t.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as"]));
  }
});
function Ou(a, t) {
  const e = T("idle"), n = T(!1), l = (s) => () => {
    n.value && (e.value = s);
  };
  return le(() => {
    n.value = !0, ee([() => a.value, () => t == null ? void 0 : t.value], ([s, r]) => {
      if (!s)
        e.value = "error";
      else {
        const i = new window.Image();
        e.value = "loading", i.onload = l("loaded"), i.onerror = l("error"), i.src = s, r && (i.referrerPolicy = r);
      }
    }, { immediate: !0 });
  }), Be(() => {
    n.value = !1;
  }), e;
}
const Kv = /* @__PURE__ */ x({
  __name: "AvatarImage",
  props: {
    src: {},
    referrerPolicy: {},
    asChild: { type: Boolean },
    as: { default: "img" }
  },
  emits: ["loadingStatusChange"],
  setup(a, { emit: t }) {
    const e = a, n = t, { src: l, referrerPolicy: s } = ae(e);
    R();
    const r = Zl(), i = Ou(l, s);
    return ee(
      i,
      (u) => {
        n("loadingStatusChange", u), u !== "idle" && (r.imageLoadingStatus.value = u);
      },
      { immediate: !0 }
    ), (u, d) => ja((b(), S(o(O), {
      role: "img",
      "as-child": u.asChild,
      as: u.as,
      src: o(l),
      "referrer-policy": o(s)
    }, {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as", "src", "referrer-policy"])), [
      [zn, o(i) === "loaded"]
    ]);
  }
}), Hv = /* @__PURE__ */ x({
  __name: "AvatarFallback",
  props: {
    delayMs: { default: 0 },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, e = Zl();
    R();
    const n = T(!1);
    let l;
    return ee(e.imageLoadingStatus, (s) => {
      s === "loading" && (n.value = !1, t.delayMs ? l = setTimeout(() => {
        n.value = !0, clearTimeout(l);
      }, t.delayMs) : n.value = !0);
    }, { immediate: !0 }), (s, r) => n.value && o(e).imageLoadingStatus.value !== "loaded" ? (b(), S(o(O), {
      key: 0,
      "as-child": s.asChild,
      as: s.as
    }, {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as"])) : ce("", !0);
  }
});
function ku(a) {
  function t(n) {
    return Array.isArray(a.date.value) ? a.date.value.some((l) => Oe(l, n)) : a.date.value ? Oe(a.date.value, n) : !1;
  }
  const e = B(
    () => {
      var n, l, s, r;
      if (Array.isArray(a.date.value)) {
        if (!a.date.value.length)
          return !1;
        for (const i of a.date.value)
          if ((n = a.isDateDisabled) != null && n.call(a, i) || (l = a.isDateUnavailable) != null && l.call(a, i))
            return !0;
      } else {
        if (!a.date.value)
          return !1;
        if ((s = a.isDateDisabled) != null && s.call(a, a.date.value) || (r = a.isDateUnavailable) != null && r.call(a, a.date.value))
          return !0;
      }
      return !1;
    }
  );
  return {
    isDateSelected: t,
    isInvalid: e
  };
}
function Mu(a, t) {
  const e = t(a), n = e.compare(a), l = {};
  return n >= 7 && (l.day = 1), n >= Ze(a) && (l.month = 1), e.set({ ...l });
}
function Vu(a, t) {
  const e = t(a), n = a.compare(e), l = {};
  return n >= 7 && (l.day = 35), n >= Ze(a) && (l.month = 13), e.set({ ...l });
}
function Fu(a, t) {
  return t(a);
}
function Nu(a, t) {
  return t(a);
}
function Jl(a) {
  const t = qn(a.locale.value), e = B(() => {
    const m = {
      calendar: a.placeholder.value.calendar.identifier
    };
    return a.placeholder.value.calendar.identifier === "gregory" && a.placeholder.value.era === "BC" && (m.era = "short"), m;
  }), n = T(Pt({
    dateObj: a.placeholder.value,
    weekStartsOn: a.weekStartsOn.value,
    locale: a.locale.value,
    fixedWeeks: a.fixedWeeks.value,
    numberOfMonths: a.numberOfMonths.value
  })), l = B(() => n.value.map((m) => m.value));
  function s(m) {
    return !l.value.some((_) => Ko(m, _));
  }
  const r = (m = "month", _) => {
    if (!a.maxValue.value || !n.value.length)
      return !1;
    if (a.disabled.value)
      return !0;
    const C = n.value[n.value.length - 1].value;
    if (_ || a.nextPage.value) {
      const h = Mu(C, _ || a.nextPage.value);
      return Pa(h, a.maxValue.value);
    }
    if (m === "year") {
      const h = C.add({ years: 1 }).set({ day: 1, month: 1 });
      return Pa(h, a.maxValue.value);
    }
    const $ = C.add({ months: 1 }).set({ day: 1 });
    return Pa($, a.maxValue.value);
  }, i = (m = "month", _) => {
    if (!a.minValue.value || !n.value.length)
      return !1;
    if (a.disabled.value)
      return !0;
    const C = n.value[0].value;
    if (_ || a.prevPage.value) {
      const h = Vu(C, _ || a.prevPage.value);
      return Ke(h, a.minValue.value);
    }
    if (m === "year") {
      const h = C.subtract({ years: 1 }).set({ day: 35, month: 13 });
      return Ke(h, a.minValue.value);
    }
    const $ = C.subtract({ months: 1 }).set({ day: 35 });
    return Ke($, a.minValue.value);
  };
  function u(m) {
    var _;
    return !!((_ = a.isDateDisabled) != null && _.call(a, m) || a.disabled.value || a.maxValue.value && Pa(m, a.maxValue.value) || a.minValue.value && Ke(m, a.minValue.value));
  }
  const d = (m) => {
    var _;
    return !!((_ = a.isDateUnavailable) != null && _.call(a, m));
  }, c = B(() => n.value.length ? n.value[0].rows[0].map((m) => t.dayOfWeek(ze(m), a.weekdayFormat.value)) : []), f = (m = "month", _) => {
    const C = n.value[0].value;
    if (_ || a.nextPage.value) {
      const E = Fu(C, _ || a.nextPage.value), P = Pt({
        dateObj: E,
        weekStartsOn: a.weekStartsOn.value,
        locale: a.locale.value,
        fixedWeeks: a.fixedWeeks.value,
        numberOfMonths: a.numberOfMonths.value
      });
      n.value = P;
      const D = {};
      if (!_) {
        const I = P[0].value.compare(C);
        I >= Ze(C) && (D.day = 1), I >= 365 && (D.month = 1);
      }
      a.placeholder.value = P[0].value.set({ ...D });
      return;
    }
    const $ = m === "month" ? C.add({ months: a.pagedNavigation.value ? a.numberOfMonths.value : 1 }) : C.add({ years: 1 }), h = Pt({
      dateObj: $,
      weekStartsOn: a.weekStartsOn.value,
      locale: a.locale.value,
      fixedWeeks: a.fixedWeeks.value,
      numberOfMonths: a.numberOfMonths.value
    });
    n.value = h, a.placeholder.value = h[0].value.set({ day: 1 });
  }, v = (m = "month", _) => {
    const C = n.value[0].value;
    if (_ || a.prevPage.value) {
      const E = Nu(C, _ || a.prevPage.value), P = Pt({
        dateObj: E,
        weekStartsOn: a.weekStartsOn.value,
        locale: a.locale.value,
        fixedWeeks: a.fixedWeeks.value,
        numberOfMonths: a.numberOfMonths.value
      });
      n.value = P;
      const D = {};
      if (!_) {
        const I = C.compare(P[0].value);
        I >= Ze(C) && (D.day = 1), I >= 365 && (D.month = 1);
      }
      a.placeholder.value = P[0].value.set({ ...D });
      return;
    }
    const $ = m === "month" ? C.subtract({ months: a.pagedNavigation.value ? a.numberOfMonths.value : 1 }) : C.subtract({ years: 1 }), h = Pt({
      dateObj: $,
      weekStartsOn: a.weekStartsOn.value,
      locale: a.locale.value,
      fixedWeeks: a.fixedWeeks.value,
      numberOfMonths: a.numberOfMonths.value
    });
    n.value = h, a.placeholder.value = h[0].value.set({ day: 1 });
  };
  ee(a.placeholder, (m) => {
    l.value.some((_) => Ko(_, m)) || (n.value = Pt({
      dateObj: m,
      weekStartsOn: a.weekStartsOn.value,
      locale: a.locale.value,
      fixedWeeks: a.fixedWeeks.value,
      numberOfMonths: a.numberOfMonths.value
    }));
  }), ee([a.locale, a.weekStartsOn, a.fixedWeeks, a.numberOfMonths], () => {
    n.value = Pt({
      dateObj: a.placeholder.value,
      weekStartsOn: a.weekStartsOn.value,
      locale: a.locale.value,
      fixedWeeks: a.fixedWeeks.value,
      numberOfMonths: a.numberOfMonths.value
    });
  });
  const p = B(() => {
    if (!n.value.length)
      return "";
    if (a.locale.value !== t.getLocale() && t.setLocale(a.locale.value), n.value.length === 1) {
      const D = n.value[0].value;
      return `${t.fullMonthAndYear(ze(D), e.value)}`;
    }
    const m = ze(n.value[0].value), _ = ze(n.value[n.value.length - 1].value), C = t.fullMonth(m, e.value), $ = t.fullMonth(_, e.value), h = t.fullYear(m, e.value), E = t.fullYear(_, e.value);
    return h === E ? `${C} - ${$} ${E}` : `${C} ${h} - ${$} ${E}`;
  }), g = B(() => `${a.calendarLabel.value ?? "Event Date"}, ${p.value}`);
  return {
    isDateDisabled: u,
    isDateUnavailable: d,
    isNextButtonDisabled: r,
    isPrevButtonDisabled: i,
    grid: n,
    weekdays: c,
    visibleView: l,
    isOutsideVisibleView: s,
    formatter: t,
    nextPage: f,
    prevPage: v,
    headingValue: p,
    fullCalendarLabel: g
  };
}
const Lu = { style: { border: "0px", clip: "rect(0px, 0px, 0px, 0px)", "clip-path": "inset(50%)", height: "1px", margin: "-1px", overflow: "hidden", padding: "0px", position: "absolute", "white-space": "nowrap", width: "1px" } }, zu = {
  role: "heading",
  "aria-level": "2"
}, [Xt, Ku] = te("CalendarRoot"), Hu = /* @__PURE__ */ x({
  __name: "CalendarRoot",
  props: {
    modelValue: {},
    multiple: { type: Boolean, default: !1 },
    defaultValue: { default: void 0 },
    defaultPlaceholder: {},
    placeholder: { default: void 0 },
    pagedNavigation: { type: Boolean, default: !1 },
    preventDeselect: { type: Boolean, default: !1 },
    weekStartsOn: { default: 0 },
    weekdayFormat: { default: "narrow" },
    calendarLabel: {},
    fixedWeeks: { type: Boolean, default: !1 },
    maxValue: {},
    minValue: {},
    locale: { default: "en" },
    numberOfMonths: { default: 1 },
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean, default: !1 },
    initialFocus: { type: Boolean, default: !1 },
    isDateDisabled: { type: Function, default: void 0 },
    isDateUnavailable: { type: Function, default: void 0 },
    dir: {},
    nextPage: {},
    prevPage: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  emits: ["update:modelValue", "update:placeholder"],
  setup(a, { emit: t }) {
    const e = a, n = t, {
      locale: l,
      disabled: s,
      readonly: r,
      initialFocus: i,
      pagedNavigation: u,
      weekStartsOn: d,
      weekdayFormat: c,
      fixedWeeks: f,
      multiple: v,
      minValue: p,
      maxValue: g,
      numberOfMonths: m,
      preventDeselect: _,
      isDateDisabled: C,
      isDateUnavailable: $,
      calendarLabel: h,
      defaultValue: E,
      nextPage: P,
      prevPage: D,
      dir: I
    } = ae(e), { primitiveElement: M, currentElement: V } = Re(), A = we(I), F = ne(e, "modelValue", n, {
      defaultValue: E.value,
      passive: e.modelValue === void 0
    }), j = Yt({
      defaultPlaceholder: e.placeholder,
      defaultValue: F.value,
      locale: e.locale
    }), H = ne(e, "placeholder", n, {
      defaultValue: e.defaultPlaceholder ?? j.copy(),
      passive: e.placeholder === void 0
    });
    function Q(de) {
      H.value = de.copy();
    }
    const {
      fullCalendarLabel: G,
      headingValue: J,
      isDateDisabled: z,
      isDateUnavailable: K,
      isNextButtonDisabled: L,
      isPrevButtonDisabled: N,
      weekdays: Z,
      isOutsideVisibleView: Y,
      nextPage: re,
      prevPage: X,
      formatter: se,
      grid: fe
    } = Jl({
      locale: l,
      placeholder: H,
      weekStartsOn: d,
      fixedWeeks: f,
      numberOfMonths: m,
      minValue: p,
      maxValue: g,
      disabled: s,
      weekdayFormat: c,
      pagedNavigation: u,
      isDateDisabled: C.value,
      isDateUnavailable: $.value,
      calendarLabel: h,
      nextPage: P,
      prevPage: D
    }), {
      isInvalid: xe,
      isDateSelected: Ee
    } = ku({
      date: F,
      isDateDisabled: z,
      isDateUnavailable: K
    });
    ee(F, (de) => {
      if (Array.isArray(de) && de.length) {
        const Ie = de[de.length - 1];
        Ie && !ke(H.value, Ie) && Q(Ie);
      } else !Array.isArray(de) && de && !ke(H.value, de) && Q(de);
    });
    function be(de) {
      if (v.value) {
        if (!F.value)
          F.value = [de.copy()];
        else if (Array.isArray(F.value)) {
          if (F.value.findIndex((Ae) => Oe(Ae, de)) === -1)
            F.value = [...F.value, de];
          else if (!_.value) {
            const Ae = F.value.filter((We) => !Oe(We, de));
            if (!Ae.length) {
              H.value = de.copy(), F.value = void 0;
              return;
            }
            F.value = Ae.map((We) => We.copy());
          }
        }
      } else {
        if (!F.value) {
          F.value = de.copy();
          return;
        }
        !_.value && ke(F.value, de) ? (H.value = de.copy(), F.value = void 0) : F.value = de.copy();
      }
    }
    return le(() => {
      i.value && Pl(V.value);
    }), Ku({
      isDateUnavailable: K,
      dir: A,
      isDateDisabled: z,
      locale: l,
      formatter: se,
      modelValue: F,
      placeholder: H,
      disabled: s,
      initialFocus: i,
      pagedNavigation: u,
      weekStartsOn: d,
      weekdayFormat: c,
      fixedWeeks: f,
      multiple: v,
      numberOfMonths: m,
      readonly: r,
      preventDeselect: _,
      fullCalendarLabel: G,
      headingValue: J,
      isInvalid: xe,
      isDateSelected: Ee,
      isNextButtonDisabled: L,
      isPrevButtonDisabled: N,
      isOutsideVisibleView: Y,
      nextPage: re,
      prevPage: X,
      parentElement: V,
      onPlaceholderChange: Q,
      onDateChange: be
    }), (de, Ie) => (b(), S(o(O), {
      ref_key: "primitiveElement",
      ref: M,
      as: de.as,
      "as-child": de.asChild,
      role: "application",
      "aria-label": o(G),
      "data-readonly": o(r) ? "" : void 0,
      "data-disabled": o(s) ? "" : void 0,
      "data-invalid": o(xe) ? "" : void 0,
      dir: o(A)
    }, {
      default: y(() => [
        w(de.$slots, "default", {
          date: o(H),
          grid: o(fe),
          weekDays: o(Z),
          weekStartsOn: o(d),
          locale: o(l),
          fixedWeeks: o(f)
        }),
        Ye("div", Lu, [
          Ye("div", zu, De(o(G)), 1)
        ])
      ]),
      _: 3
    }, 8, ["as", "as-child", "aria-label", "data-readonly", "data-disabled", "data-invalid", "dir"]));
  }
}), Wu = /* @__PURE__ */ x({
  __name: "CalendarHeader",
  props: {
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ju = /* @__PURE__ */ x({
  __name: "CalendarHeading",
  props: {
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = Xt();
    return (n, l) => (b(), S(o(O), k(t, {
      "data-disabled": o(e).disabled.value ? "" : void 0
    }), {
      default: y(() => [
        w(n.$slots, "default", {
          headingValue: o(e).headingValue.value
        }, () => [
          ye(De(o(e).headingValue.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["data-disabled"]));
  }
}), Uu = /* @__PURE__ */ x({
  __name: "CalendarGrid",
  props: {
    asChild: { type: Boolean },
    as: { default: "table" }
  },
  setup(a) {
    const t = a, e = Xt(), n = B(() => e.disabled.value ? !0 : void 0), l = B(() => e.readonly.value ? !0 : void 0);
    return (s, r) => (b(), S(o(O), k(t, {
      tabindex: "-1",
      role: "grid",
      "aria-readonly": l.value,
      "aria-disabled": n.value,
      "data-readonly": l.value && "",
      "data-disabled": n.value && ""
    }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-readonly", "aria-disabled", "data-readonly", "data-disabled"]));
  }
}), Gu = /* @__PURE__ */ x({
  __name: "CalendarCell",
  props: {
    date: {},
    asChild: { type: Boolean },
    as: { default: "td" }
  },
  setup(a) {
    const t = Xt();
    return (e, n) => {
      var l, s;
      return b(), S(o(O), {
        as: e.as,
        "as-child": e.asChild,
        role: "gridcell",
        "aria-selected": o(t).isDateSelected(e.date) ? !0 : void 0,
        "aria-disabled": o(t).isDateDisabled(e.date) || ((s = (l = o(t)).isDateUnavailable) == null ? void 0 : s.call(l, e.date)),
        "data-disabled": o(t).isDateDisabled(e.date) ? "" : void 0
      }, {
        default: y(() => [
          w(e.$slots, "default")
        ]),
        _: 3
      }, 8, ["as", "as-child", "aria-selected", "aria-disabled", "data-disabled"]);
    };
  }
}), qu = /* @__PURE__ */ x({
  __name: "CalendarHeadCell",
  props: {
    asChild: { type: Boolean },
    as: { default: "th" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Yu = /* @__PURE__ */ x({
  __name: "CalendarNext",
  props: {
    step: { default: "month" },
    nextPage: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = B(() => n.disabled.value || n.isNextButtonDisabled(t.step, t.nextPage)), n = Xt();
    return (l, s) => (b(), S(o(O), {
      as: t.as,
      "as-child": t.asChild,
      "aria-label": "Next page",
      type: l.as === "button" ? "button" : void 0,
      "aria-disabled": e.value || void 0,
      "data-disabled": e.value || void 0,
      disabled: e.value,
      onClick: s[0] || (s[0] = (r) => o(n).nextPage(t.step, t.nextPage))
    }, {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Next page")
        ])
      ]),
      _: 3
    }, 8, ["as", "as-child", "type", "aria-disabled", "data-disabled", "disabled"]));
  }
}), Xu = /* @__PURE__ */ x({
  __name: "CalendarPrev",
  props: {
    step: { default: "month" },
    prevPage: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = B(() => n.disabled.value || n.isPrevButtonDisabled(t.step, t.prevPage)), n = Xt();
    return (l, s) => (b(), S(o(O), {
      "aria-label": "Previous page",
      as: t.as,
      "as-child": t.asChild,
      type: l.as === "button" ? "button" : void 0,
      "aria-disabled": e.value || void 0,
      "data-disabled": e.value || void 0,
      disabled: e.value,
      onClick: s[0] || (s[0] = (r) => o(n).prevPage(t.step, t.prevPage))
    }, {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Prev page")
        ])
      ]),
      _: 3
    }, 8, ["as", "as-child", "type", "aria-disabled", "data-disabled", "disabled"]));
  }
}), Zu = /* @__PURE__ */ x({
  __name: "CalendarGridHead",
  props: {
    asChild: { type: Boolean },
    as: { default: "thead" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), k(t, { "aria-hidden": "true" }), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ju = /* @__PURE__ */ x({
  __name: "CalendarGridBody",
  props: {
    asChild: { type: Boolean },
    as: { default: "tbody" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Qu = /* @__PURE__ */ x({
  __name: "CalendarGridRow",
  props: {
    asChild: { type: Boolean },
    as: { default: "tr" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ed = /* @__PURE__ */ x({
  __name: "CalendarCellTrigger",
  props: {
    day: {},
    month: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = nt(), n = Xt(), { primitiveElement: l, currentElement: s } = Re(), r = B(() => t.day.day.toLocaleString(n.locale.value)), i = B(() => n.formatter.custom(ze(t.day), {
      weekday: "long",
      month: "long",
      day: "numeric",
      year: "numeric"
    })), u = B(() => n.isDateDisabled(t.day)), d = B(
      () => {
        var h;
        return (h = n.isDateUnavailable) == null ? void 0 : h.call(n, t.day);
      }
    ), c = B(() => bl(t.day, Hn())), f = B(() => !Cl(t.day, t.month)), v = B(
      () => n.isOutsideVisibleView(t.day)
    ), p = B(() => !n.disabled.value && Oe(t.day, n.placeholder.value)), g = B(() => n.isDateSelected(t.day)), m = "[data-radix-vue-calendar-cell-trigger]:not([data-disabled]):not([data-outside-view]):not([data-outside-visible-view])";
    function _(h) {
      var E;
      n.readonly.value || n.isDateDisabled(h) || (E = n.isDateUnavailable) != null && E.call(n, h) || n.onDateChange(h);
    }
    function C() {
      _(t.day);
    }
    function $(h) {
      h.preventDefault(), h.stopPropagation();
      const E = n.parentElement.value, P = E ? Array.from(E.querySelectorAll(m)) : [];
      let I = P.indexOf(s.value);
      const M = 7, V = n.dir.value === "rtl" ? -1 : 1;
      switch (h.code) {
        case e.ARROW_RIGHT:
          I += V;
          break;
        case e.ARROW_LEFT:
          I -= V;
          break;
        case e.ARROW_UP:
          I -= M;
          break;
        case e.ARROW_DOWN:
          I += M;
          break;
        case e.ENTER:
        case e.SPACE_CODE:
          _(t.day);
          return;
        default:
          return;
      }
      if (I >= 0 && I < P.length) {
        P[I].focus();
        return;
      }
      if (I < 0) {
        if (n.isPrevButtonDisabled("month"))
          return;
        n.prevPage(), oe(() => {
          const A = E ? Array.from(E.querySelectorAll(m)) : [];
          if (!n.pagedNavigation.value) {
            const F = Ze(n.placeholder.value);
            A[F - Math.abs(I)].focus();
            return;
          }
          A[A.length - Math.abs(I)].focus();
        });
        return;
      }
      if (I >= P.length) {
        if (n.isNextButtonDisabled("month"))
          return;
        n.nextPage(), oe(() => {
          const A = E ? Array.from(E.querySelectorAll(m)) : [];
          if (!n.pagedNavigation.value) {
            const F = Ze(n.placeholder.value.add({ months: n.numberOfMonths.value - 1 }));
            A[A.length - F + I - P.length].focus();
            return;
          }
          A[I - P.length].focus();
        });
      }
    }
    return (h, E) => (b(), S(o(O), k({
      ref_key: "primitiveElement",
      ref: l
    }, t, {
      role: "button",
      "aria-label": i.value,
      "data-radix-vue-calendar-cell-trigger": "",
      "aria-disabled": u.value || d.value ? !0 : void 0,
      "data-selected": g.value ? !0 : void 0,
      "data-value": h.day.toString(),
      "data-disabled": u.value ? "" : void 0,
      "data-unavailable": d.value ? "" : void 0,
      "data-today": c.value ? "" : void 0,
      "data-outside-view": f.value ? "" : void 0,
      "data-outside-visible-view": v.value ? "" : void 0,
      "data-focused": p.value ? "" : void 0,
      tabindex: p.value ? 0 : f.value || u.value ? void 0 : -1,
      onClick: C,
      onKeydown: [
        ie($, ["up", "down", "left", "right", "space", "enter"]),
        E[0] || (E[0] = ie(ue(() => {
        }, ["prevent"]), ["enter"]))
      ]
    }), {
      default: y(() => [
        w(h.$slots, "default", { dayValue: r.value }, () => [
          ye(De(r.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["aria-label", "aria-disabled", "data-selected", "data-value", "data-disabled", "data-unavailable", "data-today", "data-outside-view", "data-outside-visible-view", "data-focused", "tabindex"]));
  }
});
function za(a) {
  return a === "indeterminate";
}
function Ql(a) {
  return za(a) ? "indeterminate" : a ? "checked" : "unchecked";
}
const td = ["value", "checked", "name", "disabled", "required"], [ad, nd] = te("CheckboxRoot"), Wv = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "CheckboxRoot",
  props: {
    defaultChecked: { type: Boolean },
    checked: { type: [Boolean, String], default: void 0 },
    disabled: { type: Boolean },
    required: { type: Boolean },
    name: {},
    value: { default: "on" },
    id: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  emits: ["update:checked"],
  setup(a, { emit: t }) {
    const e = a, n = t, { disabled: l } = ae(e), s = ne(e, "checked", n, {
      defaultValue: e.defaultChecked,
      passive: e.checked === void 0
    }), { forwardRef: r, currentElement: i } = R(), u = at(i), d = B(() => {
      var c;
      return e.id && i.value ? (c = document.querySelector(`[for="${e.id}"]`)) == null ? void 0 : c.innerText : void 0;
    });
    return nd({
      disabled: l,
      state: s
    }), (c, f) => (b(), ve(_e, null, [
      q(o(O), k(c.$attrs, {
        id: c.id,
        ref: o(r),
        role: "checkbox",
        "as-child": e.asChild,
        as: c.as,
        type: c.as === "button" ? "button" : void 0,
        "aria-checked": o(za)(o(s)) ? "mixed" : o(s),
        "aria-required": e.required,
        "aria-label": c.$attrs["aria-label"] || d.value,
        "data-state": o(Ql)(o(s)),
        "data-disabled": o(l) ? "" : void 0,
        disabled: o(l),
        onKeydown: ie(ue(() => {
        }, ["prevent"]), ["enter"]),
        onClick: f[0] || (f[0] = (v) => s.value = o(za)(o(s)) ? !0 : !o(s))
      }), {
        default: y(() => [
          w(c.$slots, "default", { checked: o(s) })
        ]),
        _: 3
      }, 16, ["id", "as-child", "as", "type", "aria-checked", "aria-required", "aria-label", "data-state", "data-disabled", "disabled", "onKeydown"]),
      o(u) ? (b(), ve("input", {
        key: 0,
        type: "checkbox",
        tabindex: "-1",
        "aria-hidden": "true",
        value: c.value,
        checked: !!o(s),
        name: e.name,
        disabled: e.disabled,
        required: e.required,
        style: {
          transform: "translateX(-100%)",
          position: "absolute",
          pointerEvents: "none",
          opacity: 0,
          margin: 0
        }
      }, null, 8, td)) : ce("", !0)
    ], 64));
  }
}), jv = /* @__PURE__ */ x({
  __name: "CheckboxIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const { forwardRef: t } = R(), e = ad();
    return (n, l) => (b(), S(o(Pe), {
      present: n.forceMount || o(za)(o(e).state.value) || o(e).state.value === !0
    }, {
      default: y(() => [
        q(o(O), k({
          ref: o(t),
          "data-state": o(Ql)(o(e).state.value),
          "data-disabled": o(e).disabled.value ? "" : void 0,
          style: { pointerEvents: "none" },
          "as-child": n.asChild,
          as: n.as
        }, n.$attrs), {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 16, ["data-state", "data-disabled", "as-child", "as"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), [es, od] = te("PopperRoot"), kt = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "PopperRoot",
  setup(a) {
    const t = T();
    return od({
      anchor: t,
      onAnchorChange: (e) => t.value = e
    }), (e, n) => w(e.$slots, "default");
  }
}), Mt = /* @__PURE__ */ x({
  __name: "PopperAnchor",
  props: {
    element: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e, currentElement: n } = R(), l = es();
    return Ce(() => {
      l.onAnchorChange(t.element ?? n.value);
    }), (s, r) => (b(), S(o(O), {
      ref: o(e),
      as: s.as,
      "as-child": s.asChild
    }, {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child"]));
  }
});
function ld(a) {
  return a !== null;
}
function sd(a) {
  return {
    name: "transformOrigin",
    options: a,
    fn(t) {
      var _, C, $;
      const { placement: e, rects: n, middlewareData: l } = t, r = ((_ = l.arrow) == null ? void 0 : _.centerOffset) !== 0, i = r ? 0 : a.arrowWidth, u = r ? 0 : a.arrowHeight, [d, c] = Tn(e), f = { start: "0%", center: "50%", end: "100%" }[c], v = (((C = l.arrow) == null ? void 0 : C.x) ?? 0) + i / 2, p = ((($ = l.arrow) == null ? void 0 : $.y) ?? 0) + u / 2;
      let g = "", m = "";
      return d === "bottom" ? (g = r ? f : `${v}px`, m = `${-u}px`) : d === "top" ? (g = r ? f : `${v}px`, m = `${n.floating.height + u}px`) : d === "right" ? (g = `${-u}px`, m = r ? f : `${p}px`) : d === "left" && (g = `${n.floating.width + u}px`, m = r ? f : `${p}px`), { data: { x: g, y: m } };
    }
  };
}
function Tn(a) {
  const [t, e = "center"] = a.split("-");
  return [t, e];
}
const ts = {
  side: "bottom",
  sideOffset: 0,
  align: "center",
  alignOffset: 0,
  arrowPadding: 0,
  avoidCollisions: !0,
  collisionBoundary: () => [],
  collisionPadding: 0,
  sticky: "partial",
  hideWhenDetached: !1,
  updatePositionStrategy: "optimized",
  prioritizePosition: !1
}, [rd, id] = te("PopperContent"), It = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "PopperContent",
  props: /* @__PURE__ */ yl({
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  }, {
    ...ts
  }),
  emits: ["placed"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = es(), { forwardRef: s, currentElement: r } = R(), i = T(), u = T(), { width: d, height: c } = Ll(u), f = B(
      () => e.side + (e.align !== "center" ? `-${e.align}` : "")
    ), v = B(() => typeof e.collisionPadding == "number" ? e.collisionPadding : { top: 0, right: 0, bottom: 0, left: 0, ...e.collisionPadding }), p = B(() => Array.isArray(e.collisionBoundary) ? e.collisionBoundary : [e.collisionBoundary]), g = B(() => ({
      padding: v.value,
      boundary: p.value.filter(ld),
      // with `strategy: 'fixed'`, this is the only way to get it to respect boundaries
      altBoundary: p.value.length > 0
    })), m = ni(() => [
      Mr({
        mainAxis: e.sideOffset + c.value,
        alignmentAxis: e.alignOffset
      }),
      e.prioritizePosition && e.avoidCollisions && Ho({
        ...g.value
      }),
      e.avoidCollisions && Vr({
        mainAxis: !0,
        crossAxis: !!e.prioritizePosition,
        limiter: e.sticky === "partial" ? Fr() : void 0,
        ...g.value
      }),
      !e.prioritizePosition && e.avoidCollisions && Ho({
        ...g.value
      }),
      Nr({
        ...g.value,
        apply: ({ elements: A, rects: F, availableWidth: j, availableHeight: H }) => {
          const { width: Q, height: G } = F.reference, J = A.floating.style;
          J.setProperty(
            "--radix-popper-available-width",
            `${j}px`
          ), J.setProperty(
            "--radix-popper-available-height",
            `${H}px`
          ), J.setProperty(
            "--radix-popper-anchor-width",
            `${Q}px`
          ), J.setProperty(
            "--radix-popper-anchor-height",
            `${G}px`
          );
        }
      }),
      u.value && Lr({ element: u.value, padding: e.arrowPadding }),
      sd({
        arrowWidth: d.value,
        arrowHeight: c.value
      }),
      e.hideWhenDetached && zr({ strategy: "referenceHidden", ...g.value })
    ]), { floatingStyles: _, placement: C, isPositioned: $, middlewareData: h } = Or(
      l.anchor,
      i,
      {
        strategy: "fixed",
        placement: f,
        whileElementsMounted: (...A) => kr(...A, {
          animationFrame: e.updatePositionStrategy === "always"
        }),
        middleware: m
      }
    ), E = B(
      () => Tn(C.value)[0]
    ), P = B(
      () => Tn(C.value)[1]
    );
    _r(() => {
      $.value && n("placed");
    });
    const D = B(
      () => {
        var A;
        return ((A = h.value.arrow) == null ? void 0 : A.centerOffset) !== 0;
      }
    ), I = T("");
    Ce(() => {
      r.value && (I.value = window.getComputedStyle(r.value).zIndex);
    });
    const M = B(() => {
      var A;
      return ((A = h.value.arrow) == null ? void 0 : A.x) ?? 0;
    }), V = B(() => {
      var A;
      return ((A = h.value.arrow) == null ? void 0 : A.y) ?? 0;
    });
    return id({
      placedSide: E,
      onArrowChange: (A) => u.value = A,
      arrowX: M,
      arrowY: V,
      shouldHideArrow: D
    }), (A, F) => {
      var j, H, Q;
      return b(), ve("div", {
        ref_key: "floatingRef",
        ref: i,
        "data-radix-popper-content-wrapper": "",
        style: Me({
          ...o(_),
          transform: o($) ? o(_).transform : "translate(0, -200%)",
          // keep off the page when measuring
          minWidth: "max-content",
          zIndex: I.value,
          "--radix-popper-transform-origin": [
            (j = o(h).transformOrigin) == null ? void 0 : j.x,
            (H = o(h).transformOrigin) == null ? void 0 : H.y
          ].join(" "),
          // hide the content if using the hide middleware and should be hidden
          // set visibility to hidden and disable pointer events so the UI behaves
          // as if the PopperContent isn't there at all
          ...((Q = o(h).hide) == null ? void 0 : Q.referenceHidden) && {
            visibility: "hidden",
            pointerEvents: "none"
          }
        })
      }, [
        q(o(O), k({ ref: o(s) }, A.$attrs, {
          "as-child": e.asChild,
          as: A.as,
          "data-side": E.value,
          "data-align": P.value,
          style: {
            // if the PopperContent hasn't been placed yet (not all measurements done)
            // we prevent animations so that users's animation don't kick in too early referring wrong sides
            animation: o($) ? void 0 : "none"
          }
        }), {
          default: y(() => [
            w(A.$slots, "default")
          ]),
          _: 3
        }, 16, ["as-child", "as", "data-side", "data-align", "style"])
      ], 4);
    };
  }
}), ud = /* @__PURE__ */ Ye("polygon", { points: "0,0 30,0 15,10" }, null, -1), dd = /* @__PURE__ */ x({
  __name: "Arrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(O), k(t, {
      width: e.width,
      height: e.height,
      viewBox: e.asChild ? void 0 : "0 0 30 10",
      preserveAspectRatio: e.asChild ? void 0 : "none"
    }), {
      default: y(() => [
        w(e.$slots, "default", {}, () => [
          ud
        ])
      ]),
      _: 3
    }, 16, ["width", "height", "viewBox", "preserveAspectRatio"]));
  }
}), cd = {
  top: "bottom",
  right: "left",
  bottom: "top",
  left: "right"
}, Zt = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "PopperArrow",
  props: {
    width: {},
    height: {},
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const { forwardRef: t } = R(), e = rd(), n = B(() => cd[e.placedSide.value]);
    return (l, s) => {
      var r, i, u, d;
      return b(), ve("span", {
        ref: (c) => {
          o(e).onArrowChange(c);
        },
        style: Me({
          position: "absolute",
          left: (r = o(e).arrowX) != null && r.value ? `${(i = o(e).arrowX) == null ? void 0 : i.value}px` : void 0,
          top: (u = o(e).arrowY) != null && u.value ? `${(d = o(e).arrowY) == null ? void 0 : d.value}px` : void 0,
          [n.value]: 0,
          transformOrigin: {
            top: "",
            right: "0 0",
            bottom: "center 0",
            left: "100% 0"
          }[o(e).placedSide.value],
          transform: {
            top: "translateY(100%)",
            right: "translateY(50%) rotate(90deg) translateX(-50%)",
            bottom: "rotate(180deg)",
            left: "translateY(50%) rotate(-90deg) translateX(50%)"
          }[o(e).placedSide.value],
          visibility: o(e).shouldHideArrow.value ? "hidden" : void 0
        })
      }, [
        q(dd, k(l.$attrs, {
          ref: o(t),
          style: {
            display: "block"
          },
          as: l.as,
          "as-child": l.asChild,
          width: l.width,
          height: l.height
        }), {
          default: y(() => [
            w(l.$slots, "default")
          ]),
          _: 3
        }, 16, ["as", "as-child", "width", "height"])
      ], 4);
    };
  }
}), Jt = /* @__PURE__ */ x({
  __name: "VisuallyHidden",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    return R(), (t, e) => (b(), S(o(O), {
      as: t.as,
      "as-child": t.asChild,
      style: {
        // See: https://github.com/twbs/bootstrap/blob/master/scss/mixins/_screen-reader.scss
        position: "absolute",
        border: 0,
        width: "1px",
        display: "inline-block",
        height: "1px",
        padding: 0,
        margin: "-1px",
        overflow: "hidden",
        clip: "rect(0, 0, 0, 0)",
        whiteSpace: "nowrap",
        wordWrap: "normal"
      }
    }, {
      default: y(() => [
        w(t.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child"]));
  }
}), no = /* @__PURE__ */ x({
  __name: "VisuallyHiddenInput",
  props: {
    name: {},
    value: {},
    required: { type: Boolean },
    disabled: { type: Boolean }
  },
  setup(a) {
    const t = a, e = B(() => typeof t.value == "string" || typeof t.value == "number" || typeof t.value == "boolean" ? [{ name: t.name, value: t.value }] : typeof t.value == "object" && Array.isArray(t.value) ? t.value.flatMap((n, l) => typeof n == "object" ? Object.entries(n).map(([s, r]) => ({ name: `[${l}][${t.name}][${s}]`, value: r })) : { name: `[${t.name}][${l}]`, value: n }) : t.value !== null && typeof t.value == "object" && !Array.isArray(t.value) ? Object.entries(t.value).map(([n, l]) => ({ name: `[${t.name}][${n}]`, value: l })) : []);
    return (n, l) => (b(!0), ve(_e, null, ma(e.value, (s) => (b(), S(Jt, {
      key: s.name,
      as: "input",
      type: "hidden",
      hidden: "",
      readonly: "",
      name: s.name,
      value: s.value,
      required: n.required,
      disabled: n.disabled
    }, null, 8, ["name", "value", "required", "disabled"]))), 128));
  }
}), fd = "data-radix-vue-collection-item", [oo, pd] = te("CollectionProvider");
function Ca(a = fd) {
  const t = T(/* @__PURE__ */ new Map()), e = T(), n = pd({
    collectionRef: e,
    itemMap: t,
    attrName: a
  }), { getItems: l } = ea(n), s = B(() => Array.from(n.itemMap.value.values())), r = B(() => n.itemMap.value.size);
  return { getItems: l, reactiveItems: s, itemMapSize: r };
}
const wa = x({
  name: "CollectionSlot",
  setup(a, { slots: t }) {
    const e = oo(), { primitiveElement: n, currentElement: l } = Re();
    return ee(l, () => {
      e.collectionRef.value = l.value;
    }), () => mt(Jn, { ref: n }, t);
  }
}), Qt = x({
  name: "CollectionItem",
  inheritAttrs: !1,
  props: {
    value: {
      // It accepts any value
      validator: () => !0
    }
  },
  setup(a, { slots: t, attrs: e }) {
    const n = oo(), { primitiveElement: l, currentElement: s } = Re();
    return Ce((r) => {
      if (s.value) {
        const i = xr(s.value);
        n.itemMap.value.set(i, { ref: s.value, value: a.value }), r(() => n.itemMap.value.delete(i));
      }
    }), () => mt(Jn, { ...e, [n.attrName]: "", ref: l }, t);
  }
});
function ea(a) {
  const t = a ?? oo();
  return { getItems: () => {
    const n = t.collectionRef.value;
    if (!n)
      return [];
    const l = Array.from(n.querySelectorAll(`[${t.attrName}]`));
    return Array.from(t.itemMap.value.values()).sort(
      (i, u) => l.indexOf(i.ref) - l.indexOf(u.ref)
    );
  } };
}
const [it, vd] = te("ComboboxRoot"), Uv = /* @__PURE__ */ x({
  __name: "ComboboxRoot",
  props: {
    modelValue: {},
    defaultValue: {},
    open: { type: Boolean, default: void 0 },
    defaultOpen: { type: Boolean },
    searchTerm: {},
    selectedValue: {},
    multiple: { type: Boolean },
    disabled: { type: Boolean },
    name: {},
    dir: {},
    filterFunction: {},
    displayValue: {},
    resetSearchTermOnBlur: { type: Boolean, default: !0 },
    resetSearchTermOnSelect: { type: Boolean, default: !0 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "update:open", "update:searchTerm", "update:selectedValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { multiple: l, disabled: s, dir: r } = ae(e), i = we(r), u = ne(e, "searchTerm", n, {
      // @ts-expect-error ignore the type error here
      defaultValue: "",
      passive: e.searchTerm === void 0
    }), d = ne(e, "modelValue", n, {
      // @ts-expect-error ignore the type error here
      defaultValue: e.defaultValue ?? l.value ? [] : void 0,
      passive: e.modelValue === void 0,
      deep: !0
    }), c = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    }), f = ne(e, "selectedValue", n, {
      defaultValue: void 0,
      passive: e.selectedValue === void 0
    });
    async function v(L) {
      var N, Z;
      c.value = L, await oe(), L ? (d.value && (Array.isArray(d.value) && l.value ? f.value = (N = h().find((Y) => {
        var re, X;
        return ((X = (re = Y.ref) == null ? void 0 : re.dataset) == null ? void 0 : X.state) === "checked";
      })) == null ? void 0 : N.value : f.value = d.value), await oe(), (Z = m.value) == null || Z.focus(), H()) : (g.value = !1, e.resetSearchTermOnBlur && M("blur"));
    }
    function p(L) {
      if (Array.isArray(d.value) && l.value) {
        const N = d.value.findIndex((Y) => Qe(Y, L)), Z = [...d.value];
        N === -1 ? Z.push(L) : Z.splice(N, 1), d.value = Z;
      } else
        d.value = L, v(!1);
    }
    const g = T(!1), m = T(), _ = T(), { forwardRef: C, currentElement: $ } = R(), { getItems: h, reactiveItems: E, itemMapSize: P } = Ca("data-radix-vue-combobox-item"), D = T([]);
    ee(() => P.value, () => {
      D.value = h().map((L) => L.value);
    }, {
      immediate: !0,
      flush: "post"
    });
    const I = B(() => {
      if (g.value) {
        if (e.filterFunction)
          return e.filterFunction(D.value, u.value);
        const L = D.value.filter((N) => typeof N == "string");
        if (L.length)
          return L.filter((N) => {
            var Z;
            return N.toLowerCase().includes((Z = u.value) == null ? void 0 : Z.toLowerCase());
          });
      }
      return D.value;
    });
    function M(L) {
      const N = L === "blur" || L === "select" && e.resetSearchTermOnSelect;
      !l.value && d.value && !Array.isArray(d.value) ? e.displayValue ? u.value = e.displayValue(d.value) : typeof d.value != "object" ? u.value = d.value.toString() : N && (u.value = "") : N && (u.value = "");
    }
    const V = B(() => I.value.findIndex((L) => Qe(L, f.value))), A = B(() => {
      var L;
      return (L = E.value.find((N) => Qe(N.value, f.value))) == null ? void 0 : L.ref;
    }), F = B(() => JSON.stringify(d.value));
    ee(F, async () => {
      await oe(), await oe(), M("select");
    }, {
      // If searchTerm is provided with value during initialization, we don't reset it immediately
      immediate: !e.searchTerm
    }), ee(() => [I.value.length, u.value.length], async ([L, N], [Z, Y]) => {
      await oe(), await oe(), L && (Y > N || V.value === -1) && (f.value = I.value[0]);
    });
    const j = at($);
    function H() {
      var L;
      A.value instanceof Element && ((L = A.value) == null || L.scrollIntoView({ block: "nearest" }));
    }
    function Q() {
      A.value instanceof Element && A.value.focus && A.value.focus();
    }
    const G = T(!1);
    function J() {
      G.value = !0;
    }
    function z() {
      requestAnimationFrame(() => {
        G.value = !1;
      });
    }
    async function K(L) {
      var N;
      I.value.length && f.value && A.value instanceof Element && (L.preventDefault(), L.stopPropagation(), G.value || (N = A.value) == null || N.click());
    }
    return vd({
      searchTerm: u,
      modelValue: d,
      // @ts-expect-error ignoring
      onValueChange: p,
      isUserInputted: g,
      multiple: l,
      disabled: s,
      open: c,
      onOpenChange: v,
      filteredOptions: I,
      contentId: "",
      inputElement: m,
      selectedElement: A,
      onInputElementChange: (L) => m.value = L,
      onInputNavigation: async (L) => {
        const N = V.value;
        N === 0 && L === "up" || N === I.value.length - 1 && L === "down" || (N === -1 && I.value.length || L === "home" ? f.value = I.value[0] : L === "end" ? f.value = I.value[I.value.length - 1] : f.value = I.value[L === "up" ? N - 1 : N + 1], await oe(), H(), Q(), oe(() => {
          var Z;
          return (Z = m.value) == null ? void 0 : Z.focus({ preventScroll: !0 });
        }));
      },
      onInputEnter: K,
      onCompositionEnd: z,
      onCompositionStart: J,
      selectedValue: f,
      onSelectedValueChange: (L) => f.value = L,
      parentElement: $,
      contentElement: _,
      onContentElementChange: (L) => _.value = L
    }), (L, N) => (b(), S(o(kt), null, {
      default: y(() => [
        q(o(O), k({
          ref: o(C),
          style: {
            pointerEvents: o(c) ? "auto" : void 0
          },
          as: L.as,
          "as-child": L.asChild,
          dir: o(i)
        }, L.$attrs), {
          default: y(() => [
            w(L.$slots, "default", {
              open: o(c),
              modelValue: o(d)
            }),
            o(j) && e.name ? (b(), S(o(no), {
              key: 0,
              name: e.name,
              value: o(d)
            }, null, 8, ["name", "value"])) : ce("", !0)
          ]),
          _: 3
        }, 16, ["style", "as", "as-child", "dir"])
      ]),
      _: 3
    }));
  }
}), Gv = /* @__PURE__ */ x({
  __name: "ComboboxInput",
  props: {
    type: { default: "text" },
    disabled: { type: Boolean },
    autoFocus: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "input" }
  },
  setup(a) {
    const t = a, e = it(), { forwardRef: n, currentElement: l } = R();
    le(() => {
      const c = l.value.nodeName === "INPUT" ? l.value : l.value.querySelector("input");
      c && (e.onInputElementChange(c), setTimeout(() => {
        t.autoFocus && (c == null || c.focus());
      }, 1));
    });
    const s = B(() => t.disabled || e.disabled.value || !1), r = T();
    Sr(() => {
      var c;
      return r.value = (c = e.selectedElement.value) == null ? void 0 : c.id;
    });
    function i(c) {
      e.open.value ? e.onInputNavigation(c.key === "ArrowUp" ? "up" : "down") : e.onOpenChange(!0);
    }
    function u(c) {
      e.open.value && e.onInputNavigation(c.key === "Home" ? "home" : "end");
    }
    function d(c) {
      var f;
      e.searchTerm.value = (f = c.target) == null ? void 0 : f.value, e.open.value || e.onOpenChange(!0), e.isUserInputted.value = !0;
    }
    return (c, f) => (b(), S(o(O), {
      ref: o(n),
      as: c.as,
      "as-child": c.asChild,
      type: c.type,
      disabled: s.value,
      value: o(e).searchTerm.value,
      "aria-expanded": o(e).open.value,
      "aria-controls": o(e).contentId,
      "aria-disabled": s.value ?? void 0,
      "aria-activedescendant": r.value,
      "aria-autocomplete": "list",
      role: "combobox",
      autocomplete: "false",
      onInput: d,
      onKeydown: [
        ie(ue(i, ["prevent"]), ["down", "up"]),
        ie(o(e).onInputEnter, ["enter"]),
        ie(ue(u, ["prevent"]), ["home", "end"])
      ],
      onCompositionstart: o(e).onCompositionStart,
      onCompositionend: o(e).onCompositionEnd
    }, {
      default: y(() => [
        w(c.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child", "type", "disabled", "value", "aria-expanded", "aria-controls", "aria-disabled", "aria-activedescendant", "onKeydown", "onCompositionstart", "onCompositionend"]));
  }
}), qv = /* @__PURE__ */ x({
  __name: "ComboboxAnchor",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const { forwardRef: t } = R();
    return (e, n) => (b(), S(o(Mt), { "as-child": "" }, {
      default: y(() => [
        q(o(O), k({
          ref: o(t),
          "as-child": e.asChild,
          as: e.as
        }, e.$attrs), {
          default: y(() => [
            w(e.$slots, "default")
          ]),
          _: 3
        }, 16, ["as-child", "as"])
      ]),
      _: 3
    }));
  }
}), Yv = /* @__PURE__ */ x({
  __name: "ComboboxTrigger",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = it(), n = B(() => t.disabled || e.disabled.value || !1);
    return (l, s) => (b(), S(o(O), k(t, {
      type: l.as === "button" ? "button" : void 0,
      tabindex: "-1",
      "aria-label": "Show popup",
      "aria-haspopup": "listbox",
      "aria-expanded": o(e).open.value,
      "aria-controls": o(e).contentId,
      "data-state": o(e).open.value ? "open" : "closed",
      disabled: n.value,
      "data-disabled": n.value ? "" : void 0,
      "aria-disabled": n.value ?? void 0,
      onClick: s[0] || (s[0] = (r) => o(e).onOpenChange(!o(e).open.value))
    }), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16, ["type", "aria-expanded", "aria-controls", "data-state", "disabled", "data-disabled", "aria-disabled"]));
  }
}), Xv = /* @__PURE__ */ x({
  __name: "ComboboxCancel",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = it();
    function n() {
      var l;
      e.searchTerm.value = "", (l = e.inputElement.value) == null || l.focus();
    }
    return (l, s) => (b(), S(o(O), k({
      type: l.as === "button" ? "button" : void 0
    }, t, {
      tabindex: "-1",
      onClick: n
    }), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16, ["type"]));
  }
}), [as, md] = te("ComboboxGroup"), Zv = /* @__PURE__ */ x({
  __name: "ComboboxGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { currentRef: e, currentElement: n } = R(), l = ge(void 0, "radix-vue-combobox-group"), s = it(), r = T(!1);
    function i() {
      if (!n.value)
        return;
      const u = n.value.querySelectorAll("[data-radix-vue-combobox-item]:not([data-hidden])");
      r.value = !!u.length;
    }
    return Al(n, () => {
      oe(() => {
        i();
      });
    }, { childList: !0 }), ee(() => s.searchTerm.value, () => {
      oe(() => {
        i();
      });
    }, { immediate: !0 }), md({
      id: l
    }), (u, d) => ja((b(), S(o(O), k(t, {
      ref_key: "currentRef",
      ref: e,
      role: "group",
      "aria-labelledby": o(l)
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-labelledby"])), [
      [zn, r.value]
    ]);
  }
}), Jv = /* @__PURE__ */ x({
  __name: "ComboboxLabel",
  props: {
    for: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a;
    R();
    const e = as({ id: "" });
    return (n, l) => (b(), S(o(O), k(t, {
      id: o(e).id
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), [hd, yd] = te("ComboboxContent"), gd = /* @__PURE__ */ x({
  __name: "ComboboxContentImpl",
  props: {
    position: { default: "inline" },
    bodyLock: { type: Boolean },
    dismissable: { type: Boolean, default: !0 },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, { position: l } = ae(e), s = it();
    ya(e.bodyLock);
    const { forwardRef: r, currentElement: i } = R();
    ga(s.parentElement);
    const u = B(() => e.position === "popper" ? e : {}), d = Ot(u.value);
    function c(v) {
      s.onSelectedValueChange("");
    }
    le(() => {
      s.onContentElementChange(i.value);
    });
    const f = {
      // Ensure border-box for floating-ui calculations
      boxSizing: "border-box",
      "--radix-combobox-content-transform-origin": "var(--radix-popper-transform-origin)",
      "--radix-combobox-content-available-width": "var(--radix-popper-available-width)",
      "--radix-combobox-content-available-height": "var(--radix-popper-available-height)",
      "--radix-combobox-trigger-width": "var(--radix-popper-anchor-width)",
      "--radix-combobox-trigger-height": "var(--radix-popper-anchor-height)"
    };
    return yd({ position: l }), (v, p) => (b(), S(o(wa), null, {
      default: y(() => [
        v.dismissable ? (b(), S(o(Ct), {
          key: 0,
          "as-child": "",
          "disable-outside-pointer-events": v.disableOutsidePointerEvents,
          onDismiss: p[0] || (p[0] = (g) => o(s).onOpenChange(!1)),
          onFocusOutside: p[1] || (p[1] = (g) => {
            var m;
            (m = o(s).parentElement.value) != null && m.contains(g.target) && g.preventDefault(), n("focusOutside", g);
          }),
          onInteractOutside: p[2] || (p[2] = (g) => n("interactOutside", g)),
          onEscapeKeyDown: p[3] || (p[3] = (g) => n("escapeKeyDown", g)),
          onPointerDownOutside: p[4] || (p[4] = (g) => {
            var m;
            (m = o(s).parentElement.value) != null && m.contains(g.target) && g.preventDefault(), n("pointerDownOutside", g);
          })
        }, {
          default: y(() => [
            (b(), S(Xe(o(l) === "popper" ? o(It) : o(O)), k({ ...v.$attrs, ...o(d) }, {
              id: o(s).contentId,
              ref: o(r),
              role: "listbox",
              "data-state": o(s).open.value ? "open" : "closed",
              style: {
                // flex layout so we can place the scroll buttons properly
                display: "flex",
                flexDirection: "column",
                // reset the outline by default as the content MAY get focused
                outline: "none",
                ...o(l) === "popper" ? f : {}
              },
              onPointerleave: c
            }), {
              default: y(() => [
                w(v.$slots, "default")
              ]),
              _: 3
            }, 16, ["id", "data-state", "style"]))
          ]),
          _: 3
        }, 8, ["disable-outside-pointer-events"])) : (b(), S(Xe(o(l) === "popper" ? o(It) : o(O)), k({ key: 1 }, { ...v.$attrs, ...u.value }, {
          id: o(s).contentId,
          ref: o(r),
          role: "listbox",
          "data-state": o(s).open.value ? "open" : "closed",
          style: {
            // flex layout so we can place the scroll buttons properly
            display: "flex",
            flexDirection: "column",
            // reset the outline by default as the content MAY get focused
            outline: "none",
            ...o(l) === "popper" ? f : {}
          },
          onPointerleave: c
        }), {
          default: y(() => [
            w(v.$slots, "default")
          ]),
          _: 3
        }, 16, ["id", "data-state", "style"]))
      ]),
      _: 3
    }));
  }
}), Qv = /* @__PURE__ */ x({
  __name: "ComboboxContent",
  props: {
    forceMount: { type: Boolean },
    position: {},
    bodyLock: { type: Boolean },
    dismissable: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside"],
  setup(a, { emit: t }) {
    const l = Se(a, t), { forwardRef: s } = R(), r = it();
    return r.contentId || (r.contentId = ge(void 0, "radix-vue-combobox-content")), (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(r).open.value
    }, {
      default: y(() => [
        q(gd, k({ ...o(l), ...i.$attrs }, { ref: o(s) }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), em = /* @__PURE__ */ x({
  __name: "ComboboxEmpty",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    R();
    const e = it(), n = B(() => e.filteredOptions.value.length === 0);
    return (l, s) => n.value ? (b(), S(o(O), W(k({ key: 0 }, t)), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("No options")
        ])
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
});
function Ja(a) {
  const t = Ya({
    nonce: T()
  });
  return B(() => {
    var e;
    return (a == null ? void 0 : a.value) || ((e = t.nonce) == null ? void 0 : e.value);
  });
}
const tm = /* @__PURE__ */ x({
  __name: "ComboboxViewport",
  props: {
    nonce: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), { nonce: n } = ae(t), l = Ja(n);
    return (s, r) => (b(), ve(_e, null, [
      q(o(O), k({ ...s.$attrs, ...t }, {
        ref: o(e),
        "data-radix-combobox-viewport": "",
        role: "presentation",
        style: {
          // we use position: 'relative' here on the `viewport` so that when we call
          // `selectedItem.offsetTop` in calculations, the offset is relative to the viewport
          // (independent of the scrollUpButton).
          position: "relative",
          flex: 1,
          overflow: "auto"
        }
      }), {
        default: y(() => [
          w(s.$slots, "default")
        ]),
        _: 3
      }, 16),
      q(o(O), {
        as: "style",
        nonce: o(l)
      }, {
        default: y(() => [
          ye(" /* Hide scrollbars cross-browser and enable momentum scroll for touch devices */ [data-radix-combobox-viewport] { scrollbar-width:none; -ms-overflow-style: none; -webkit-overflow-scrolling: touch; } [data-radix-combobox-viewport]::-webkit-scrollbar { display: none; } ")
        ]),
        _: 1
      }, 8, ["nonce"])
    ], 64));
  }
}), [bd, Cd] = te("ComboboxItem"), wd = "combobox.select", am = /* @__PURE__ */ x({
  __name: "ComboboxItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, n = t, { disabled: l } = ae(e), s = it();
    as({ id: "", options: T([]) });
    const { forwardRef: r } = R(), i = B(
      () => {
        var m, _;
        return s.multiple.value && Array.isArray(s.modelValue.value) ? (m = s.modelValue.value) == null ? void 0 : m.some((C) => Qe(C, e.value)) : Qe((_ = s.modelValue) == null ? void 0 : _.value, e.value);
      }
    ), u = B(() => Qe(s.selectedValue.value, e.value)), d = ge(void 0, "radix-vue-combobox-item"), c = ge(void 0, "radix-vue-combobox-option"), f = B(() => s.isUserInputted.value ? s.searchTerm.value === "" || !!s.filteredOptions.value.find((m) => Qe(m, e.value)) : !0);
    async function v(m) {
      n("select", m), !(m != null && m.defaultPrevented) && !l.value && m && s.onValueChange(e.value);
    }
    function p(m) {
      if (!m)
        return;
      const _ = { originalEvent: m, value: e.value };
      jt(wd, v, _);
    }
    async function g(m) {
      await oe(), !m.defaultPrevented && s.onSelectedValueChange(e.value);
    }
    if (e.value === "")
      throw new Error(
        "A <ComboboxItem /> must have a value prop that is not an empty string. This is because the Combobox value can be set to an empty string to clear the selection and show the placeholder."
      );
    return Cd({
      isSelected: i
    }), (m, _) => (b(), S(o(Qt), { value: m.value }, {
      default: y(() => [
        ja(q(o(O), {
          id: o(c),
          ref: o(r),
          role: "option",
          tabindex: "-1",
          "aria-labelledby": o(d),
          "data-highlighted": u.value ? "" : void 0,
          "aria-selected": i.value,
          "data-state": i.value ? "checked" : "unchecked",
          "aria-disabled": o(l) || void 0,
          "data-disabled": o(l) ? "" : void 0,
          as: m.as,
          "as-child": m.asChild,
          "data-hidden": f.value ? void 0 : !0,
          onClick: p,
          onPointermove: g
        }, {
          default: y(() => [
            w(m.$slots, "default", {}, () => [
              ye(De(m.value), 1)
            ])
          ]),
          _: 3
        }, 8, ["id", "aria-labelledby", "data-highlighted", "aria-selected", "data-state", "aria-disabled", "data-disabled", "as", "as-child", "data-hidden"]), [
          [zn, f.value]
        ])
      ]),
      _: 3
    }, 8, ["value"]));
  }
}), nm = /* @__PURE__ */ x({
  __name: "ComboboxItemIndicator",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a;
    R();
    const e = bd();
    return (n, l) => o(e).isSelected.value ? (b(), S(o(O), k({
      key: 0,
      "aria-hidden": "true"
    }, t), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
}), om = /* @__PURE__ */ x({
  __name: "ComboboxSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(O), k(t, { "aria-hidden": "true" }), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), lm = /* @__PURE__ */ x({
  __name: "ComboboxArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a, e = it(), n = hd();
    return R(), (l, s) => o(e).open.value && o(n).position.value === "popper" ? (b(), S(o(Zt), W(k({ key: 0 }, t)), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
}), sm = /* @__PURE__ */ x({
  __name: "ComboboxPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Qa = /* @__PURE__ */ x({
  __name: "MenuAnchor",
  props: {
    element: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Mt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), lo = /* @__PURE__ */ x({
  __name: "MenuArrow",
  props: {
    width: {},
    height: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Zt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
});
function _d() {
  const a = T(!1);
  return le(() => {
    He("keydown", () => {
      a.value = !0;
    }, { capture: !0, passive: !0 }), He(["pointerdown", "pointermove"], () => {
      a.value = !1;
    }, { capture: !0, passive: !0 });
  }), a;
}
const xd = Dl(_d), [Vt, ns] = te(["MenuRoot", "MenuSub"], "MenuContext"), [_a, Sd] = te("MenuRoot"), so = /* @__PURE__ */ x({
  __name: "MenuRoot",
  props: {
    open: { type: Boolean, default: !1 },
    dir: {},
    modal: { type: Boolean, default: !0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, { modal: l, dir: s } = ae(e), r = we(s), i = ne(e, "open", n), u = T(), d = xd();
    return ns({
      open: i,
      onOpenChange: (c) => {
        i.value = c;
      },
      content: u,
      onContentChange: (c) => {
        u.value = c;
      }
    }), Sd({
      onClose: () => {
        i.value = !1;
      },
      isUsingKeyboardRef: d,
      dir: r,
      modal: l
    }), (c, f) => (b(), S(o(kt), null, {
      default: y(() => [
        w(c.$slots, "default")
      ]),
      _: 3
    }));
  }
}), Ed = "rovingFocusGroup.onEntryFocus", Pd = { bubbles: !1, cancelable: !0 }, en = {
  ArrowLeft: "prev",
  ArrowUp: "prev",
  ArrowRight: "next",
  ArrowDown: "next",
  PageUp: "first",
  Home: "first",
  PageDown: "last",
  End: "last"
};
function Dd(a, t) {
  return t !== "rtl" ? a : a === "ArrowLeft" ? "ArrowRight" : a === "ArrowRight" ? "ArrowLeft" : a;
}
function os(a, t, e) {
  const n = Dd(a.key, e);
  if (!(t === "vertical" && ["ArrowLeft", "ArrowRight"].includes(n)) && !(t === "horizontal" && ["ArrowUp", "ArrowDown"].includes(n)))
    return en[n];
}
function ls(a, t = !1) {
  const e = me();
  for (const n of a)
    if (n === e || (n.focus({ preventScroll: t }), me() !== e))
      return;
}
function $d(a, t) {
  return a.map((e, n) => a[(t + n) % a.length]);
}
const [Bd, Id] = te("RovingFocusGroup"), Ft = /* @__PURE__ */ x({
  __name: "RovingFocusGroup",
  props: {
    orientation: { default: void 0 },
    dir: {},
    loop: { type: Boolean, default: !1 },
    currentTabStopId: {},
    defaultCurrentTabStopId: {},
    preventScrollOnEntryFocus: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["entryFocus", "update:currentTabStopId"],
  setup(a, { expose: t, emit: e }) {
    const n = a, l = e, { loop: s, orientation: r, dir: i } = ae(n), u = we(i), d = ne(n, "currentTabStopId", l, {
      defaultValue: n.defaultCurrentTabStopId,
      passive: n.currentTabStopId === void 0
    }), c = T(!1), f = T(!1), v = T(0), { getItems: p } = Ca();
    function g(_) {
      const C = !f.value;
      if (_.currentTarget && _.target === _.currentTarget && C && !c.value) {
        const $ = new CustomEvent(Ed, Pd);
        if (_.currentTarget.dispatchEvent($), l("entryFocus", $), !$.defaultPrevented) {
          const h = p().map((I) => I.ref).filter((I) => I.dataset.disabled !== ""), E = h.find((I) => I.getAttribute("data-active") === "true"), P = h.find(
            (I) => I.id === d.value
          ), D = [E, P, ...h].filter(
            Boolean
          );
          ls(D, n.preventScrollOnEntryFocus);
        }
      }
      f.value = !1;
    }
    function m() {
      setTimeout(() => {
        f.value = !1;
      }, 1);
    }
    return t({
      getItems: p
    }), Id({
      loop: s,
      dir: u,
      orientation: r,
      currentTabStopId: d,
      onItemFocus: (_) => {
        d.value = _;
      },
      onItemShiftTab: () => {
        c.value = !0;
      },
      onFocusableItemAdd: () => {
        v.value++;
      },
      onFocusableItemRemove: () => {
        v.value--;
      }
    }), (_, C) => (b(), S(o(wa), null, {
      default: y(() => [
        q(o(O), {
          tabindex: c.value || v.value === 0 ? -1 : 0,
          "data-orientation": o(r),
          as: _.as,
          "as-child": _.asChild,
          dir: o(u),
          style: { outline: "none" },
          onMousedown: C[0] || (C[0] = ($) => f.value = !0),
          onMouseup: m,
          onFocus: g,
          onBlur: C[1] || (C[1] = ($) => c.value = !1)
        }, {
          default: y(() => [
            w(_.$slots, "default")
          ]),
          _: 3
        }, 8, ["tabindex", "data-orientation", "as", "as-child", "dir"])
      ]),
      _: 3
    }));
  }
}), Nt = /* @__PURE__ */ x({
  __name: "RovingFocusItem",
  props: {
    tabStopId: {},
    focusable: { type: Boolean, default: !0 },
    active: { type: Boolean, default: !0 },
    allowShiftKey: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, e = Bd(), n = B(() => t.tabStopId || ge()), l = B(
      () => e.currentTabStopId.value === n.value
    ), { getItems: s } = ea();
    le(() => {
      t.focusable && e.onFocusableItemAdd();
    }), Be(() => {
      t.focusable && e.onFocusableItemRemove();
    });
    function r(i) {
      if (i.key === "Tab" && i.shiftKey) {
        e.onItemShiftTab();
        return;
      }
      if (i.target !== i.currentTarget)
        return;
      const u = os(
        i,
        e.orientation.value,
        e.dir.value
      );
      if (u !== void 0) {
        if (i.metaKey || i.ctrlKey || i.altKey || !t.allowShiftKey && i.shiftKey)
          return;
        i.preventDefault();
        let d = [...s().map((c) => c.ref).filter((c) => c.dataset.disabled !== "")];
        if (u === "last")
          d.reverse();
        else if (u === "prev" || u === "next") {
          u === "prev" && d.reverse();
          const c = d.indexOf(
            i.currentTarget
          );
          d = e.loop.value ? $d(d, c + 1) : d.slice(c + 1);
        }
        oe(() => ls(d));
      }
    }
    return (i, u) => (b(), S(o(Qt), null, {
      default: y(() => [
        q(o(O), {
          tabindex: l.value ? 0 : -1,
          "data-orientation": o(e).orientation.value,
          "data-active": i.active,
          "data-disabled": i.focusable ? void 0 : "",
          as: i.as,
          "as-child": i.asChild,
          onMousedown: u[0] || (u[0] = (d) => {
            i.focusable ? o(e).onItemFocus(n.value) : d.preventDefault();
          }),
          onFocus: u[1] || (u[1] = (d) => o(e).onItemFocus(n.value)),
          onKeydown: r
        }, {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 8, ["tabindex", "data-orientation", "data-active", "data-disabled", "as", "as-child"])
      ]),
      _: 3
    }));
  }
}), [ro, Td] = te("MenuContent"), io = /* @__PURE__ */ x({
  __name: "MenuContentImpl",
  props: /* @__PURE__ */ yl({
    loop: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    disableOutsideScroll: { type: Boolean },
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  }, {
    ...ts
  }),
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus", "dismiss"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Vt(), s = _a(), { trapFocus: r, disableOutsidePointerEvents: i, loop: u } = ae(e);
    Yn(), ya(i.value);
    const d = T(""), c = T(0), f = T(0), v = T(null), p = T("right"), g = T(0), m = T(null), { createCollection: _ } = Fe(), { forwardRef: C, currentElement: $ } = R(), h = _($);
    ee($, (A) => {
      l.onContentChange(A);
    });
    const { handleTypeaheadSearch: E } = ba(h);
    Be(() => {
      window.clearTimeout(c.value);
    });
    function P(A) {
      var j, H;
      return p.value === ((j = v.value) == null ? void 0 : j.side) && Cu(A, (H = v.value) == null ? void 0 : H.area);
    }
    async function D(A) {
      var F;
      n("openAutoFocus", A), !A.defaultPrevented && (A.preventDefault(), (F = $.value) == null || F.focus({
        preventScroll: !0
      }));
    }
    function I(A) {
      if (A.defaultPrevented)
        return;
      const j = A.target.closest("[data-radix-menu-content]") === A.currentTarget, H = A.ctrlKey || A.altKey || A.metaKey, Q = A.key.length === 1, G = At(
        A,
        me(),
        $.value,
        {
          loop: u.value,
          arrowKeyOptions: "vertical",
          dir: s == null ? void 0 : s.dir.value,
          focus: !0,
          attributeName: "[data-radix-vue-collection-item]:not([data-disabled])"
        }
      );
      if (G)
        return G == null ? void 0 : G.focus();
      if (A.code === "Space" || (j && (A.key === "Tab" && A.preventDefault(), !H && Q && E(A.key)), A.target !== $.value) || !hu.includes(A.key))
        return;
      A.preventDefault();
      const J = h.value;
      ql.includes(A.key) && J.reverse(), In(J);
    }
    function M(A) {
      var F, j;
      (j = (F = A == null ? void 0 : A.currentTarget) == null ? void 0 : F.contains) != null && j.call(F, A.target) || (window.clearTimeout(c.value), d.value = "");
    }
    function V(A) {
      var H;
      if (!da(A))
        return;
      const F = A.target, j = g.value !== A.clientX;
      if ((H = A == null ? void 0 : A.currentTarget) != null && H.contains(F) && j) {
        const Q = A.clientX > g.value ? "right" : "left";
        p.value = Q, g.value = A.clientX;
      }
    }
    return Td({
      onItemEnter: (A) => !!P(A),
      onItemLeave: (A) => {
        var F;
        P(A) || ((F = $.value) == null || F.focus(), m.value = null);
      },
      onTriggerLeave: (A) => !!P(A),
      searchRef: d,
      pointerGraceTimerRef: f,
      onPointerGraceIntentChange: (A) => {
        v.value = A;
      }
    }), (A, F) => (b(), S(o(Za), {
      "as-child": "",
      trapped: o(r),
      onMountAutoFocus: D,
      onUnmountAutoFocus: F[7] || (F[7] = (j) => n("closeAutoFocus", j))
    }, {
      default: y(() => [
        q(o(Ct), {
          "as-child": "",
          "disable-outside-pointer-events": o(i),
          onEscapeKeyDown: F[2] || (F[2] = (j) => n("escapeKeyDown", j)),
          onPointerDownOutside: F[3] || (F[3] = (j) => n("pointerDownOutside", j)),
          onFocusOutside: F[4] || (F[4] = (j) => n("focusOutside", j)),
          onInteractOutside: F[5] || (F[5] = (j) => n("interactOutside", j)),
          onDismiss: F[6] || (F[6] = (j) => n("dismiss"))
        }, {
          default: y(() => [
            q(o(Ft), {
              "current-tab-stop-id": m.value,
              "onUpdate:currentTabStopId": F[0] || (F[0] = (j) => m.value = j),
              "as-child": "",
              orientation: "vertical",
              dir: o(s).dir.value,
              loop: o(u),
              onEntryFocus: F[1] || (F[1] = (j) => {
                n("entryFocus", j), o(s).isUsingKeyboardRef.value || j.preventDefault();
              })
            }, {
              default: y(() => [
                q(o(It), {
                  ref: o(C),
                  role: "menu",
                  as: A.as,
                  "as-child": A.asChild,
                  "aria-orientation": "vertical",
                  "data-radix-menu-content": "",
                  "data-state": o(to)(o(l).open.value),
                  dir: o(s).dir.value,
                  side: A.side,
                  "side-offset": A.sideOffset,
                  align: A.align,
                  "align-offset": A.alignOffset,
                  "avoid-collisions": A.avoidCollisions,
                  "collision-boundary": A.collisionBoundary,
                  "collision-padding": A.collisionPadding,
                  "arrow-padding": A.arrowPadding,
                  "prioritize-position": A.prioritizePosition,
                  sticky: A.sticky,
                  "hide-when-detached": A.hideWhenDetached,
                  onKeydown: I,
                  onBlur: M,
                  onPointermove: V
                }, {
                  default: y(() => [
                    w(A.$slots, "default")
                  ]),
                  _: 3
                }, 8, ["as", "as-child", "data-state", "dir", "side", "side-offset", "align", "align-offset", "avoid-collisions", "collision-boundary", "collision-padding", "arrow-padding", "prioritize-position", "sticky", "hide-when-detached"])
              ]),
              _: 3
            }, 8, ["current-tab-stop-id", "dir", "loop"])
          ]),
          _: 3
        }, 8, ["disable-outside-pointer-events"])
      ]),
      _: 3
    }, 8, ["trapped"]));
  }
}), ss = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "MenuItemImpl",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = ro(), { forwardRef: n } = R(), l = T(!1);
    async function s(i) {
      if (!i.defaultPrevented && da(i)) {
        if (t.disabled)
          e.onItemLeave(i);
        else if (!e.onItemEnter(i)) {
          const d = i.currentTarget;
          d == null || d.focus({ preventScroll: !0 });
        }
      }
    }
    async function r(i) {
      await oe(), !i.defaultPrevented && da(i) && e.onItemLeave(i);
    }
    return (i, u) => (b(), S(o(Qt), {
      value: { textValue: i.textValue }
    }, {
      default: y(() => [
        q(o(O), k({
          ref: o(n),
          role: "menuitem",
          tabindex: "-1"
        }, i.$attrs, {
          as: i.as,
          "as-child": i.asChild,
          "data-radix-vue-collection-item": "",
          "aria-disabled": i.disabled || void 0,
          "data-disabled": i.disabled ? "" : void 0,
          "data-highlighted": l.value ? "" : void 0,
          onPointermove: s,
          onPointerleave: r,
          onFocus: u[0] || (u[0] = async (d) => {
            await oe(), !(d.defaultPrevented || i.disabled) && (l.value = !0);
          }),
          onBlur: u[1] || (u[1] = async (d) => {
            await oe(), !d.defaultPrevented && (l.value = !1);
          })
        }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16, ["as", "as-child", "aria-disabled", "data-disabled", "data-highlighted"])
      ]),
      _: 3
    }, 8, ["value"]));
  }
}), xa = /* @__PURE__ */ x({
  __name: "MenuItem",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l, currentElement: s } = R(), r = _a(), i = ro(), u = T(!1);
    async function d() {
      const c = s.value;
      if (!e.disabled && c) {
        const f = new CustomEvent(vu, {
          bubbles: !0,
          cancelable: !0
        });
        n("select", f), await oe(), f.defaultPrevented ? u.value = !1 : r.onClose();
      }
    }
    return (c, f) => (b(), S(ss, k(e, {
      ref: o(l),
      onClick: d,
      onPointerdown: f[0] || (f[0] = () => {
        u.value = !0;
      }),
      onPointerup: f[1] || (f[1] = async (v) => {
        var p;
        await oe(), !v.defaultPrevented && (u.value || (p = v.currentTarget) == null || p.click());
      }),
      onKeydown: f[2] || (f[2] = async (v) => {
        const p = o(i).searchRef.value !== "";
        c.disabled || p && v.key === " " || o(Bn).includes(v.key) && (v.currentTarget.click(), v.preventDefault());
      })
    }), {
      default: y(() => [
        w(c.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [Rd, rs] = te(
  ["MenuCheckboxItem", "MenuRadioItem"],
  "MenuItemIndicatorContext"
), uo = /* @__PURE__ */ x({
  __name: "MenuItemIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = Rd({
      checked: T(!1)
    });
    return (e, n) => (b(), S(o(Pe), {
      present: e.forceMount || o(La)(o(t).checked.value) || o(t).checked.value === !0
    }, {
      default: y(() => [
        q(o(O), {
          as: e.as,
          "as-child": e.asChild,
          "data-state": o(ao)(o(t).checked.value)
        }, {
          default: y(() => [
            w(e.$slots, "default")
          ]),
          _: 3
        }, 8, ["as", "as-child", "data-state"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), co = /* @__PURE__ */ x({
  __name: "MenuCheckboxItem",
  props: {
    checked: { type: [Boolean, String], default: !1 },
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select", "update:checked"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = ne(e, "checked", n);
    return rs({ checked: l }), (s, r) => (b(), S(xa, k({ role: "menuitemcheckbox" }, e, {
      "aria-checked": o(La)(o(l)) ? "mixed" : o(l),
      "data-state": o(ao)(o(l)),
      onSelect: r[0] || (r[0] = async (i) => {
        n("select", i), o(La)(o(l)) ? l.value = !0 : l.value = !o(l);
      })
    }), {
      default: y(() => [
        w(s.$slots, "default", { checked: o(l) })
      ]),
      _: 3
    }, 16, ["aria-checked", "data-state"]));
  }
}), Ad = /* @__PURE__ */ x({
  __name: "MenuRootContentModal",
  props: {
    loop: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Se(e, n), s = Vt(), { forwardRef: r, currentElement: i } = R();
    return ga(i), (u, d) => (b(), S(io, k(o(l), {
      ref: o(r),
      "trap-focus": o(s).open.value,
      "disable-outside-pointer-events": o(s).open.value,
      "disable-outside-scroll": !0,
      onDismiss: d[0] || (d[0] = (c) => o(s).onOpenChange(!1)),
      onFocusOutside: d[1] || (d[1] = ue((c) => n("focusOutside", c), ["prevent"]))
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16, ["trap-focus", "disable-outside-pointer-events"]));
  }
}), Od = /* @__PURE__ */ x({
  __name: "MenuRootContentNonModal",
  props: {
    loop: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t), s = Vt();
    return (r, i) => (b(), S(io, k(o(l), {
      "trap-focus": !1,
      "disable-outside-pointer-events": !1,
      "disable-outside-scroll": !1,
      onDismiss: i[0] || (i[0] = (u) => o(s).onOpenChange(!1))
    }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), fo = /* @__PURE__ */ x({
  __name: "MenuContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t), s = Vt(), r = _a();
    return (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(s).open.value
    }, {
      default: y(() => [
        o(r).modal.value ? (b(), S(Ad, W(k({ key: 0 }, { ...i.$attrs, ...o(l) })), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16)) : (b(), S(Od, W(k({ key: 1 }, { ...i.$attrs, ...o(l) })), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16))
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), tn = /* @__PURE__ */ x({
  __name: "MenuGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), k({ role: "group" }, t), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), po = /* @__PURE__ */ x({
  __name: "MenuLabel",
  props: {
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), vo = /* @__PURE__ */ x({
  __name: "MenuPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [kd, Md] = te("MenuRadioGroup"), mo = /* @__PURE__ */ x({
  __name: "MenuRadioGroup",
  props: {
    modelValue: { default: "" },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "modelValue", t);
    return Md({
      modelValue: l,
      onValueChange: (s) => {
        l.value = s;
      }
    }), (s, r) => (b(), S(tn, W(U(e)), {
      default: y(() => [
        w(s.$slots, "default", { modelValue: o(l) })
      ]),
      _: 3
    }, 16));
  }
}), ho = /* @__PURE__ */ x({
  __name: "MenuRadioItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, n = t, { value: l } = ae(e), s = kd(), r = B(
      () => s.modelValue.value === (l == null ? void 0 : l.value)
    );
    return rs({ checked: r }), (i, u) => (b(), S(xa, k({ role: "menuitemradio" }, e, {
      "aria-checked": r.value,
      "data-state": o(ao)(r.value),
      onSelect: u[0] || (u[0] = async (d) => {
        n("select", d), o(s).onValueChange(o(l));
      })
    }), {
      default: y(() => [
        w(i.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-checked", "data-state"]));
  }
}), yo = /* @__PURE__ */ x({
  __name: "MenuSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), k(t, {
      role: "separator",
      "aria-orientation": "horizontal"
    }), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [is, Vd] = te("MenuSub"), go = /* @__PURE__ */ x({
  __name: "MenuSub",
  props: {
    open: { type: Boolean, default: void 0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "open", t, {
      defaultValue: !1,
      passive: e.open === void 0
    }), s = Vt(), r = T(), i = T();
    return Ce((u) => {
      (s == null ? void 0 : s.open.value) === !1 && (l.value = !1), u(() => l.value = !1);
    }), ns({
      open: l,
      onOpenChange: (u) => {
        l.value = u;
      },
      content: i,
      onContentChange: (u) => {
        i.value = u;
      }
    }), Vd({
      triggerId: "",
      contentId: "",
      trigger: r,
      onTriggerChange: (u) => {
        r.value = u;
      }
    }), (u, d) => (b(), S(o(kt), null, {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }));
  }
}), bo = /* @__PURE__ */ x({
  __name: "MenuSubContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    sideOffset: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean, default: !0 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t), s = Vt(), r = _a(), i = is(), { forwardRef: u, currentElement: d } = R();
    return i.contentId || (i.contentId = ge(void 0, "radix-vue-menu-sub-content")), (c, f) => (b(), S(o(Pe), {
      present: c.forceMount || o(s).open.value
    }, {
      default: y(() => [
        q(io, k(o(l), {
          id: o(i).contentId,
          ref: o(u),
          "aria-labelledby": o(i).triggerId,
          align: "start",
          side: o(r).dir.value === "rtl" ? "left" : "right",
          "disable-outside-pointer-events": !1,
          "disable-outside-scroll": !1,
          "trap-focus": !1,
          onOpenAutoFocus: f[0] || (f[0] = ue((v) => {
            var p;
            o(r).isUsingKeyboardRef.value && ((p = o(d)) == null || p.focus());
          }, ["prevent"])),
          onCloseAutoFocus: f[1] || (f[1] = ue(() => {
          }, ["prevent"])),
          onFocusOutside: f[2] || (f[2] = (v) => {
            v.defaultPrevented || v.target !== o(i).trigger.value && o(s).onOpenChange(!1);
          }),
          onEscapeKeyDown: f[3] || (f[3] = (v) => {
            o(r).onClose(), v.preventDefault();
          }),
          onKeydown: f[4] || (f[4] = (v) => {
            var m, _;
            const p = (m = v.currentTarget) == null ? void 0 : m.contains(v.target), g = o(gu)[o(r).dir.value].includes(v.key);
            p && g && (o(s).onOpenChange(!1), (_ = o(i).trigger.value) == null || _.focus(), v.preventDefault());
          })
        }), {
          default: y(() => [
            w(c.$slots, "default")
          ]),
          _: 3
        }, 16, ["id", "aria-labelledby", "side"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Co = /* @__PURE__ */ x({
  __name: "MenuSubTrigger",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Vt(), n = _a(), l = is(), s = ro(), r = T(null);
    l.triggerId || (l.triggerId = ge(void 0, "radix-vue-menu-sub-trigger"));
    function i() {
      r.value && window.clearTimeout(r.value), r.value = null;
    }
    Be(() => {
      i();
    });
    function u(f) {
      !da(f) || s.onItemEnter(f) || !t.disabled && !e.open.value && !r.value && (s.onPointerGraceIntentChange(null), r.value = window.setTimeout(() => {
        e.onOpenChange(!0), i();
      }, 100));
    }
    async function d(f) {
      var p, g;
      if (!da(f))
        return;
      i();
      const v = (p = e.content.value) == null ? void 0 : p.getBoundingClientRect();
      if (v != null && v.width) {
        const m = (g = e.content.value) == null ? void 0 : g.dataset.side, _ = m === "right", C = _ ? -5 : 5, $ = v[_ ? "left" : "right"], h = v[_ ? "right" : "left"];
        s.onPointerGraceIntentChange({
          area: [
            // Apply a bleed on clientX to ensure that our exit point is
            // consistently within polygon bounds
            { x: f.clientX + C, y: f.clientY },
            { x: $, y: v.top },
            { x: h, y: v.top },
            { x: h, y: v.bottom },
            { x: $, y: v.bottom }
          ],
          side: m
        }), window.clearTimeout(s.pointerGraceTimerRef.value), s.pointerGraceTimerRef.value = window.setTimeout(
          () => s.onPointerGraceIntentChange(null),
          300
        );
      } else {
        if (s.onTriggerLeave(f))
          return;
        s.onPointerGraceIntentChange(null);
      }
    }
    async function c(f) {
      var p;
      const v = s.searchRef.value !== "";
      t.disabled || v && f.key === " " || yu[n.dir.value].includes(f.key) && (e.onOpenChange(!0), await oe(), (p = e.content.value) == null || p.focus(), f.preventDefault());
    }
    return (f, v) => (b(), S(Qa, { "as-child": "" }, {
      default: y(() => [
        q(ss, k(t, {
          id: o(l).triggerId,
          ref: (p) => {
            var g;
            (g = o(l)) == null || g.onTriggerChange(p == null ? void 0 : p.$el);
          },
          "aria-haspopup": "menu",
          "aria-expanded": o(e).open.value,
          "aria-controls": o(l).contentId,
          "data-state": o(to)(o(e).open.value),
          onClick: v[0] || (v[0] = async (p) => {
            t.disabled || p.defaultPrevented || (p.currentTarget.focus(), o(e).open.value || o(e).onOpenChange(!0));
          }),
          onPointermove: u,
          onPointerleave: d,
          onKeydown: c
        }), {
          default: y(() => [
            w(f.$slots, "default")
          ]),
          _: 3
        }, 16, ["id", "aria-expanded", "aria-controls", "data-state"])
      ]),
      _: 3
    }));
  }
}), [us, Fd] = te("ContextMenuRoot"), rm = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ContextMenuRoot",
  props: {
    dir: {},
    modal: { type: Boolean, default: !0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, { dir: l, modal: s } = ae(e);
    R();
    const r = we(l), i = T(!1);
    return Fd({
      open: i,
      onOpenChange: (u) => {
        i.value = u;
      },
      dir: r,
      modal: s
    }), ee(i, (u) => {
      n("update:open", u);
    }), (u, d) => (b(), S(o(so), {
      open: i.value,
      "onUpdate:open": d[0] || (d[0] = (c) => i.value = c),
      dir: o(r),
      modal: o(s)
    }, {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 8, ["open", "dir", "modal"]));
  }
});
function Zo(a) {
  return a.pointerType !== "mouse";
}
const im = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ContextMenuTrigger",
  props: {
    disabled: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, { disabled: e } = ae(t), { forwardRef: n } = R(), l = us(), s = T({ x: 0, y: 0 }), r = B(() => ({
      getBoundingClientRect: () => ({
        width: 0,
        height: 0,
        left: s.value.x,
        right: s.value.x,
        top: s.value.y,
        bottom: s.value.y,
        ...s.value
      })
    })), i = T(0);
    function u() {
      window.clearTimeout(i.value);
    }
    function d(p) {
      s.value = { x: p.clientX, y: p.clientY }, l.onOpenChange(!0);
    }
    async function c(p) {
      e.value || (await oe(), p.defaultPrevented || (u(), d(p), p.preventDefault()));
    }
    async function f(p) {
      e.value || (await oe(), Zo(p) && !p.defaultPrevented && (u(), i.value = window.setTimeout(() => d(p), 700)));
    }
    async function v(p) {
      e.value || (await oe(), Zo(p) && !p.defaultPrevented && u());
    }
    return (p, g) => (b(), ve(_e, null, [
      q(o(Qa), {
        as: "template",
        element: r.value
      }, null, 8, ["element"]),
      q(o(O), k({
        ref: o(n),
        as: p.as,
        "as-child": p.asChild,
        "data-state": o(l).open.value ? "open" : "closed",
        "data-disabled": o(e) ? "" : void 0,
        style: {
          WebkitTouchCallout: "none"
        }
      }, p.$attrs, {
        onContextmenu: c,
        onPointerdown: f,
        onPointermove: v,
        onPointercancel: v,
        onPointerup: v
      }), {
        default: y(() => [
          w(p.$slots, "default")
        ]),
        _: 3
      }, 16, ["as", "as-child", "data-state", "data-disabled"])
    ], 64));
  }
}), um = /* @__PURE__ */ x({
  __name: "ContextMenuPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(vo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), dm = /* @__PURE__ */ x({
  __name: "ContextMenuContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    alignOffset: { default: 0 },
    avoidCollisions: { type: Boolean, default: !0 },
    collisionBoundary: { default: () => [] },
    collisionPadding: { default: 0 },
    sticky: { default: "partial" },
    hideWhenDetached: { type: Boolean, default: !1 },
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    R();
    const s = us(), r = T(!1);
    return (i, u) => (b(), S(o(fo), k(o(l), {
      side: "right",
      "side-offset": 2,
      align: "start",
      style: {
        "--radix-context-menu-content-transform-origin": "var(--radix-popper-transform-origin)",
        "--radix-context-menu-content-available-width": "var(--radix-popper-available-width)",
        "--radix-context-menu-content-available-height": "var(--radix-popper-available-height)",
        "--radix-context-menu-trigger-width": "var(--radix-popper-anchor-width)",
        "--radix-context-menu-trigger-height": "var(--radix-popper-anchor-height)"
      },
      onCloseAutoFocus: u[0] || (u[0] = (d) => {
        !d.defaultPrevented && r.value && d.preventDefault(), r.value = !1;
      }),
      onInteractOutside: u[1] || (u[1] = (d) => {
        !d.defaultPrevented && !o(s).modal.value && (r.value = !0);
      })
    }), {
      default: y(() => [
        w(i.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), cm = /* @__PURE__ */ x({
  __name: "ContextMenuArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(lo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), fm = /* @__PURE__ */ x({
  __name: "ContextMenuItem",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(xa), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), pm = /* @__PURE__ */ x({
  __name: "ContextMenuGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(tn), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), vm = /* @__PURE__ */ x({
  __name: "ContextMenuSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(yo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), mm = /* @__PURE__ */ x({
  __name: "ContextMenuCheckboxItem",
  props: {
    checked: { type: [Boolean, String] },
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select", "update:checked"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(co), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), hm = /* @__PURE__ */ x({
  __name: "ContextMenuItemIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(uo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ym = /* @__PURE__ */ x({
  __name: "ContextMenuLabel",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(po), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), gm = /* @__PURE__ */ x({
  __name: "ContextMenuRadioGroup",
  props: {
    modelValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(mo), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), bm = /* @__PURE__ */ x({
  __name: "ContextMenuRadioItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(ho), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Cm = /* @__PURE__ */ x({
  __name: "ContextMenuSub",
  props: {
    defaultOpen: { type: Boolean },
    open: { type: Boolean, default: void 0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    const l = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    });
    return (s, r) => (b(), S(o(go), {
      open: o(l),
      "onUpdate:open": r[0] || (r[0] = (i) => et(l) ? l.value = i : null)
    }, {
      default: y(() => [
        w(s.$slots, "default", { open: o(l) })
      ]),
      _: 3
    }, 8, ["open"]));
  }
}), wm = /* @__PURE__ */ x({
  __name: "ContextMenuSubContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    sideOffset: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return R(), (s, r) => (b(), S(o(bo), k(o(l), { style: {
      "--radix-context-menu-content-transform-origin": "var(--radix-popper-transform-origin)",
      "--radix-context-menu-content-available-width": "var(--radix-popper-available-width)",
      "--radix-context-menu-content-available-height": "var(--radix-popper-available-height)",
      "--radix-context-menu-trigger-width": "var(--radix-popper-anchor-width)",
      "--radix-context-menu-trigger-height": "var(--radix-popper-anchor-height)"
    } }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), _m = /* @__PURE__ */ x({
  __name: "ContextMenuSubTrigger",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Co), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Nd = ["hour", "minute", "second"];
function Ht(a) {
  const { formatter: t } = a, e = Wn.map((n) => [n, a.value[n]]);
  if ("hour" in a.value) {
    const n = xl.map((s) => s === "dayPeriod" ? [s, t.dayPeriod(ze(a.value))] : [s, a.value[s]]), l = [...e, ...n];
    return Object.fromEntries(l);
  }
  return Object.fromEntries(e);
}
function ds(a) {
  const t = Sl.map((e) => e === "dayPeriod" ? [e, "AM"] : [e, null]).filter(([e]) => e === "literal" || e === null || a === "minute" && e === "second" || a === "hour" && (e === "second" || e === "minute") ? !1 : a === "day" ? !Nd.includes(e) && e !== "dayPeriod" : !0);
  return Object.fromEntries(t);
}
function Ld(a) {
  const { segmentValues: t, formatter: e, locale: n } = a;
  function l(r) {
    if ("hour" in t) {
      const i = t[r];
      return i !== null ? r === "day" && t.month !== null ? e.part(a.dateRef.set({ [r]: i, month: t.month }), r, {
        hourCycle: a.hourCycle === 24 ? "h24" : void 0
      }) : e.part(a.dateRef.set({ [r]: i }), r, {
        hourCycle: a.hourCycle === 24 ? "h24" : void 0
      }) : bn(r, "", n.value);
    } else {
      if (ti(r)) {
        const i = t[r];
        return i !== null ? r === "day" && t.month !== null ? e.part(a.dateRef.set({ [r]: i, month: t.month }), r) : e.part(a.dateRef.set({ [r]: i }), r) : bn(r, "", n.value);
      }
      return "";
    }
  }
  return Object.keys(t).reduce((r, i) => {
    if (!El(i))
      return r;
    if ("hour" in t && i === "dayPeriod") {
      const u = t[i];
      u !== null ? r[i] = u : r[i] = bn(i, "AM", n.value);
    } else
      r[i] = l(i);
    return r;
  }, {});
}
function zd(a) {
  const { granularity: t, formatter: e, contentObj: n, hideTimeZone: l, hourCycle: s } = a;
  return e.toParts(a.dateRef, ai(t, s)).map((u) => ["literal", "timeZoneName", null].includes(u.type) || !El(u.type) ? {
    part: u.type,
    value: u.value
  } : {
    part: u.type,
    value: n[u.type]
  }).filter((u) => !(u.part === null || u.value === null || u.part === "timeZoneName" && (!wl(a.dateRef) || l)));
}
function Rn(a) {
  const t = Ld(a), e = zd({
    contentObj: t,
    ...a
  });
  return {
    obj: t,
    arr: e
  };
}
function st(a) {
  const t = nt();
  return a === t.ARROW_RIGHT || a === t.ARROW_LEFT;
}
function Dt(a) {
  return !Number.isNaN(Number.parseInt(a));
}
function ut(a) {
  const t = nt();
  return !!([
    t.ENTER,
    t.ARROW_UP,
    t.ARROW_DOWN,
    t.ARROW_LEFT,
    t.ARROW_RIGHT,
    t.BACKSPACE,
    t.SPACE,
    "a",
    "A",
    "p",
    "P"
  ].includes(a) || Dt(a));
}
function Ka(a) {
  return Array.from(a.querySelectorAll("[data-radix-vue-date-field-segment]")).filter((t) => t.getAttribute("data-radix-vue-date-field-segment") !== "literal");
}
const Kd = ["id", "value", "name", "disabled", "required"], [Hd, Wd] = te("DateFieldRoot"), jd = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "DateFieldRoot",
  props: {
    defaultValue: { default: void 0 },
    defaultPlaceholder: {},
    placeholder: { default: void 0 },
    modelValue: {},
    hourCycle: {},
    granularity: {},
    hideTimeZone: { type: Boolean },
    maxValue: {},
    minValue: {},
    locale: { default: "en" },
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean, default: !1 },
    isDateUnavailable: { type: Function, default: void 0 },
    name: {},
    required: { type: Boolean },
    id: {},
    dir: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "update:placeholder"],
  setup(a, { expose: t, emit: e }) {
    const n = a, l = e, { locale: s, disabled: r, readonly: i, isDateUnavailable: u, granularity: d, defaultValue: c, dir: f } = ae(n), v = qn(n.locale), p = we(f), { primitiveElement: g, currentElement: m } = Re(), _ = T(/* @__PURE__ */ new Set());
    le(() => {
      Ka(m.value).forEach((K) => _.value.add(K));
    });
    const C = ne(n, "modelValue", l, {
      defaultValue: c.value,
      passive: n.modelValue === void 0
    }), $ = Yt({
      defaultPlaceholder: n.placeholder,
      granularity: d.value,
      defaultValue: C.value,
      locale: n.locale
    }), h = ne(n, "placeholder", l, {
      defaultValue: n.defaultPlaceholder ?? $.copy(),
      passive: n.placeholder === void 0
    }), E = B(() => n.granularity ? ia(h.value) ? n.granularity : "day" : ia(h.value) ? "minute" : "day"), P = B(() => {
      var K;
      return C.value ? !!((K = u.value) != null && K.call(u, C.value) || n.minValue && Ke(C.value, n.minValue) || n.maxValue && Ke(n.maxValue, C.value)) : !1;
    }), D = ds(E.value), I = T(C.value ? { ...Ht({ value: C.value, formatter: v }) } : { ...D }), M = B(() => Rn({
      granularity: E.value,
      dateRef: h.value,
      formatter: v,
      hideTimeZone: n.hideTimeZone,
      hourCycle: n.hourCycle,
      segmentValues: I.value,
      locale: s
    })), V = B(() => M.value.arr), A = B(() => V.value.filter(({ part: K }) => K !== "literal"));
    ee(s, (K) => {
      v.getLocale() !== K && (v.setLocale(K), oe(() => {
        _.value.clear(), Ka(m.value).forEach((L) => _.value.add(L));
      }));
    }), ee(C, (K) => {
      !ht(K) && h.value.compare(K) !== 0 && (h.value = K.copy());
    }), ee([C, s], ([K]) => {
      ht(K) ? Object.values(I.value).every((L) => L !== null) && K === void 0 && (I.value = { ...D }) : I.value = { ...Ht({ value: K, formatter: v }) };
    });
    const F = T(null), j = B(() => Array.from(_.value).findIndex((K) => {
      var L;
      return K.getAttribute("data-radix-vue-date-field-segment") === ((L = F.value) == null ? void 0 : L.getAttribute("data-radix-vue-date-field-segment"));
    })), H = B(() => {
      const K = p.value === "rtl" ? -1 : 1;
      return (K < 0 ? j.value < 0 : j.value > _.value.size - 1) ? null : Array.from(_.value)[j.value + K];
    }), Q = B(() => {
      const K = p.value === "rtl" ? -1 : 1;
      return (K > 0 ? j.value < 0 : j.value > _.value.size - 1) ? null : Array.from(_.value)[j.value - K];
    }), G = nt();
    function J(K) {
      var L, N;
      st(K.key) && (K.key === G.ARROW_LEFT && ((L = Q.value) == null || L.focus()), K.key === G.ARROW_RIGHT && ((N = H.value) == null || N.focus()));
    }
    function z(K) {
      F.value = K;
    }
    return Wd({
      isDateUnavailable: u.value,
      locale: s,
      modelValue: C,
      placeholder: h,
      disabled: r,
      formatter: v,
      hourCycle: n.hourCycle,
      readonly: i,
      segmentValues: I,
      isInvalid: P,
      segmentContents: A,
      elements: _,
      setFocusedElement: z,
      focusNext() {
        var K;
        (K = H.value) == null || K.focus();
      }
    }), t({
      /** Helper to set the focused element inside the DateField */
      setFocusedElement: z
    }), (K, L) => (b(), ve(_e, null, [
      q(o(O), k(K.$attrs, {
        ref_key: "primitiveElement",
        ref: g,
        role: "group",
        "aria-disabled": o(r) ? !0 : void 0,
        "data-disabled": o(r) ? "" : void 0,
        "data-readonly": o(i) ? "" : void 0,
        "data-invalid": P.value ? "" : void 0,
        dir: o(p),
        onKeydown: ie(J, ["left", "right"])
      }), {
        default: y(() => [
          w(K.$slots, "default", {
            modelValue: o(C),
            segments: V.value,
            isInvalid: P.value
          })
        ]),
        _: 3
      }, 16, ["aria-disabled", "data-disabled", "data-readonly", "data-invalid", "dir"]),
      Ye("input", {
        id: K.id,
        type: "text",
        tabindex: "-1",
        "aria-hidden": "true",
        value: o(C) ? o(C).toString() : "",
        name: K.name,
        disabled: o(r),
        required: K.required,
        style: {
          transform: "translateX(-100%)",
          position: "absolute",
          pointerEvents: "none",
          opacity: 0,
          margin: 0
        },
        onFocus: L[0] || (L[0] = (N) => {
          var Z, Y;
          return (Y = (Z = Array.from(_.value)) == null ? void 0 : Z[0]) == null ? void 0 : Y.focus();
        })
      }, null, 40, Kd)
    ], 64));
  }
});
function wt(a) {
  return {
    role: "spinbutton",
    contenteditable: !0,
    tabindex: a.disabled ? void 0 : 0,
    spellcheck: !1,
    inputmode: "numeric",
    autocorrect: "off",
    enterkeyhint: "next",
    style: "caret-color: transparent;"
  };
}
function Ud(a) {
  const { segmentValues: t, placeholder: e } = a, n = t.day === null, l = t.day ? e.set({ day: t.day }) : e, s = l.day, r = 1, i = Ze(l), u = n ? "Empty" : `${s}`;
  return {
    ...wt(a),
    "aria-label": "day,",
    "aria-valuemin": r,
    "aria-valuemax": i,
    "aria-valuenow": s,
    "aria-valuetext": u,
    "data-placeholder": n ? "" : void 0
  };
}
function Gd(a) {
  const { segmentValues: t, placeholder: e, formatter: n } = a, l = t.month === null, s = t.month ? e.set({ month: t.month }) : e, r = s.month, i = 1, u = 12, d = l ? "Empty" : `${r} - ${n.fullMonth(ze(s))}`;
  return {
    ...wt(a),
    "aria-label": "month, ",
    contenteditable: !0,
    "aria-valuemin": i,
    "aria-valuemax": u,
    "aria-valuenow": r,
    "aria-valuetext": d,
    "data-placeholder": l ? "" : void 0
  };
}
function qd(a) {
  const { segmentValues: t, placeholder: e } = a, n = t.year === null, l = t.year ? e.set({ year: t.year }) : e, s = 1, r = 9999, i = l.year, u = n ? "Empty" : `${i}`;
  return {
    ...wt(a),
    "aria-label": "year, ",
    "aria-valuemin": s,
    "aria-valuemax": r,
    "aria-valuenow": i,
    "aria-valuetext": u,
    "data-placeholder": n ? "" : void 0
  };
}
function Yd(a) {
  const { segmentValues: t, hourCycle: e, placeholder: n } = a;
  if (!("hour" in t) || !("hour" in n))
    return {};
  const l = t.hour === null, s = t.hour ? n.set({ hour: t.hour }) : n, r = e === 12 ? 1 : 0, i = e === 12 ? 12 : 23, u = s.hour, d = l ? "Empty" : `${u} ${t.dayPeriod ?? ""}`;
  return {
    ...wt(a),
    "aria-label": "hour, ",
    "aria-valuemin": r,
    "aria-valuemax": i,
    "aria-valuenow": u,
    "aria-valuetext": d,
    "data-placeholder": l ? "" : void 0
  };
}
function Xd(a) {
  const { segmentValues: t, placeholder: e } = a;
  if (!("minute" in t) || !("minute" in e))
    return {};
  const n = t.minute === null, s = (t.minute ? e.set({ minute: t.minute }) : e).minute, r = 0, i = 59, u = n ? "Empty" : `${s}`;
  return {
    ...wt(a),
    "aria-label": "minute, ",
    "aria-valuemin": r,
    "aria-valuemax": i,
    "aria-valuenow": s,
    "aria-valuetext": u,
    "data-placeholder": n ? "" : void 0
  };
}
function Zd(a) {
  const { segmentValues: t, placeholder: e } = a;
  if (!("second" in t) || !("second" in e))
    return {};
  const n = t.second === null, s = (t.second ? e.set({ second: t.second }) : e).second, r = 0, i = 59, u = n ? "Empty" : `${s}`;
  return {
    ...wt(a),
    "aria-label": "second, ",
    "aria-valuemin": r,
    "aria-valuemax": i,
    "aria-valuenow": s,
    "aria-valuetext": u,
    "data-placeholder": n ? "" : void 0
  };
}
function Jd(a) {
  const { segmentValues: t } = a;
  if (!("dayPeriod" in t))
    return {};
  const e = 0, n = 12, l = t.hour ? t.hour > 12 ? t.hour - 12 : t.hour : 0, s = t.dayPeriod ?? "AM";
  return {
    ...wt(a),
    inputmode: "text",
    "aria-label": "AM/PM",
    "aria-valuemin": e,
    "aria-valuemax": n,
    "aria-valuenow": l,
    "aria-valuetext": s
  };
}
function Qd(a) {
  return {
    "aria-hidden": !0,
    "data-segment": "literal"
  };
}
function ec(a) {
  return {
    role: "textbox",
    "aria-label": "timezone, ",
    "data-readonly": !0,
    "data-segment": "timeZoneName",
    tabindex: a.disabled ? void 0 : 0,
    style: "caret-color: transparent;"
  };
}
function tc(a) {
  const { segmentValues: t, placeholder: e } = a, n = 0, l = 0, s = 0, r = "era" in t ? t.era : e.era;
  return {
    ...wt(a),
    "aria-label": "era",
    "aria-valuemin": n,
    "aria-valuemax": l,
    "aria-valuenow": s,
    "aria-valuetext": r
  };
}
const ac = {
  day: {
    attrs: Ud
  },
  month: {
    attrs: Gd
  },
  year: {
    attrs: qd
  },
  hour: {
    attrs: Yd
  },
  minute: {
    attrs: Xd
  },
  second: {
    attrs: Zd
  },
  dayPeriod: {
    attrs: Jd
  },
  literal: {
    attrs: Qd
  },
  timeZoneName: {
    attrs: ec
  },
  era: {
    attrs: tc
  }
};
function cs(a) {
  const t = nt();
  function e({ e: h, part: E, dateRef: P, prevValue: D }) {
    const I = h.key === t.ARROW_UP ? 1 : -1, M = 0, V = 59;
    if (D === null)
      return I > 0 ? M : V;
    const A = [E, I];
    return P.set({ [E]: D }).cycle(...A)[E];
  }
  function n(h) {
    if (a.hasLeftFocus.value = !1, h === null)
      return h;
    const E = h.toString();
    return E.length === 1 ? (a.modelValue.value = void 0, null) : Number.parseInt(E.slice(0, -1));
  }
  function l({ e: h, part: E, dateRef: P, prevValue: D, hourCycle: I }) {
    const M = h.key === t.ARROW_UP ? 1 : -1;
    if (D === null)
      return P[E];
    if (E === "hour" && "hour" in P) {
      const A = [E, M, { hourCycle: I }];
      return P.set({ [E]: D }).cycle(...A)[E];
    }
    const V = [E, M];
    return E === "day" && a.segmentValues.value.month !== null ? P.set({ [E]: D, month: a.segmentValues.value.month }).cycle(...V)[E] : P.set({ [E]: D }).cycle(...V)[E];
  }
  function s(h, E, P) {
    let D = !1;
    const I = Math.floor(h / 10);
    if (a.hasLeftFocus.value && (a.hasLeftFocus.value = !1, P = null), P === null)
      return E === 0 ? (a.lastKeyZero.value = !0, { value: null, moveToNext: D }) : ((a.lastKeyZero.value || E > I) && (D = !0), a.lastKeyZero.value = !1, { value: E, moveToNext: D });
    const M = P.toString().length, V = Number.parseInt(P.toString() + E.toString());
    return M === 2 || V > h ? ((E > I || V > h) && (D = !0), { value: E, moveToNext: D }) : (D = !0, { value: V, moveToNext: D });
  }
  function r(h, E) {
    let D = !1;
    const I = Math.floor(59 / 10);
    if (a.hasLeftFocus.value && (a.hasLeftFocus.value = !1, E = null), E === null)
      return h === 0 ? (a.lastKeyZero.value = !0, { value: 0, moveToNext: D }) : ((a.lastKeyZero.value || h > I) && (D = !0), a.lastKeyZero.value = !1, { value: h, moveToNext: D });
    const M = E.toString().length, V = Number.parseInt(E.toString() + h.toString());
    return M === 2 || V > 59 ? (h > I && (D = !0), { value: h, moveToNext: D }) : (D = !0, { value: V, moveToNext: D });
  }
  function i(h, E) {
    let D = !1;
    const I = Math.floor(24 / 10);
    if (a.hasLeftFocus.value && (a.hasLeftFocus.value = !1, E = null), E === null)
      return h === 0 ? (a.lastKeyZero.value = !0, { value: 0, moveToNext: D }) : ((a.lastKeyZero.value || h > I) && (D = !0), a.lastKeyZero.value = !1, { value: h, moveToNext: D });
    const M = E.toString().length, V = Number.parseInt(E.toString() + h.toString());
    return M === 2 || V > 24 ? (h > I && (D = !0), { value: h, moveToNext: D }) : (D = !0, { value: V, moveToNext: D });
  }
  function u(h, E) {
    let P = !1;
    if (a.hasLeftFocus.value && (a.hasLeftFocus.value = !1, E = null), E === null)
      return { value: h === 0 ? 1 : h, moveToNext: P };
    const D = E.toString() + h.toString();
    return D.length > 4 ? { value: h === 0 ? 1 : h, moveToNext: P } : (D.length === 4 && (P = !0), { value: Number.parseInt(D), moveToNext: P });
  }
  const d = B(() => {
    var h;
    return ((h = ac[a.part]) == null ? void 0 : h.attrs({
      disabled: a.disabled.value,
      placeholder: a.placeholder.value,
      hourCycle: a.hourCycle,
      segmentValues: a.segmentValues.value,
      formatter: a.formatter
    })) ?? {};
  });
  function c(h) {
    if (!ut(h.key) || st(h.key))
      return;
    const E = a.segmentValues.value.day;
    if (h.key === t.ARROW_DOWN || h.key === t.ARROW_UP) {
      a.segmentValues.value.day = l({ e: h, part: "day", dateRef: a.placeholder.value, prevValue: E });
      return;
    }
    if (Dt(h.key)) {
      const P = Number.parseInt(h.key), D = a.segmentValues.value.month, I = D ? Ze(a.placeholder.value.set({ month: D })) : Ze(a.placeholder.value), { value: M, moveToNext: V } = s(I, P, E);
      a.segmentValues.value.day = M, V && a.focusNext();
    }
    h.key === t.BACKSPACE && (a.hasLeftFocus.value = !1, a.segmentValues.value.day = n(E));
  }
  function f(h) {
    if (!ut(h.key) || st(h.key))
      return;
    const E = a.segmentValues.value.month;
    if (h.key === t.ARROW_DOWN || h.key === t.ARROW_UP) {
      a.segmentValues.value.month = l({ e: h, part: "month", dateRef: a.placeholder.value, prevValue: E });
      return;
    }
    if (Dt(h.key)) {
      const P = Number.parseInt(h.key), { value: D, moveToNext: I } = s(12, P, E);
      a.segmentValues.value.month = D, I && a.focusNext();
    }
    h.key === t.BACKSPACE && (a.hasLeftFocus.value = !1, a.segmentValues.value.month = n(E));
  }
  function v(h) {
    if (!ut(h.key) || st(h.key))
      return;
    const E = a.segmentValues.value.year;
    if (h.key === t.ARROW_DOWN || h.key === t.ARROW_UP) {
      a.segmentValues.value.year = l({ e: h, part: "year", dateRef: a.placeholder.value, prevValue: E });
      return;
    }
    if (Dt(h.key)) {
      const P = Number.parseInt(h.key), { value: D, moveToNext: I } = u(P, E);
      a.segmentValues.value.year = D, I && a.focusNext();
    }
    h.key === t.BACKSPACE && (a.hasLeftFocus.value = !1, a.segmentValues.value.year = n(E));
  }
  function p(h) {
    const E = a.placeholder.value;
    if (!ut(h.key) || st(h.key) || !("hour" in E) || !("hour" in a.segmentValues.value))
      return;
    const P = a.segmentValues.value.hour, D = a.hourCycle;
    if (h.key === t.ARROW_UP || h.key === t.ARROW_DOWN) {
      a.segmentValues.value.hour = l({ e: h, part: "hour", dateRef: a.placeholder.value, prevValue: P, hourCycle: D }), "dayPeriod" in a.segmentValues.value && (a.segmentValues.value.hour < 12 ? a.segmentValues.value.dayPeriod = "AM" : a.segmentValues.value.hour && (a.segmentValues.value.dayPeriod = "PM"));
      return;
    }
    if (Dt(h.key)) {
      const I = Number.parseInt(h.key), { value: M, moveToNext: V } = i(I, P);
      "dayPeriod" in a.segmentValues.value && M && M > 12 ? a.segmentValues.value.dayPeriod = "PM" : "dayPeriod" in a.segmentValues.value && M && (a.segmentValues.value.dayPeriod = "AM"), a.segmentValues.value.hour = M, V && a.focusNext();
    }
    h.key === t.BACKSPACE && (a.hasLeftFocus.value = !1, a.segmentValues.value.hour = n(P));
  }
  function g(h) {
    const E = a.placeholder.value;
    if (!ut(h.key) || st(h.key) || !("minute" in E) || !("minute" in a.segmentValues.value))
      return;
    const P = a.segmentValues.value.minute;
    if (a.segmentValues.value.minute = e({ e: h, part: "minute", dateRef: a.placeholder.value, prevValue: P }), Dt(h.key)) {
      const D = Number.parseInt(h.key), { value: I, moveToNext: M } = r(D, P);
      a.segmentValues.value.minute = I, M && a.focusNext();
    }
    h.key === t.BACKSPACE && (a.hasLeftFocus.value = !1, a.segmentValues.value.minute = n(P));
  }
  function m(h) {
    const E = a.placeholder.value;
    if (!ut(h.key) || st(h.key) || !("second" in E) || !("second" in a.segmentValues.value))
      return;
    const P = a.segmentValues.value.second;
    if (a.segmentValues.value.second = e({ e: h, part: "second", dateRef: a.placeholder.value, prevValue: P }), Dt(h.key)) {
      const D = Number.parseInt(h.key), { value: I, moveToNext: M } = r(D, P);
      a.segmentValues.value.second = I, M && a.focusNext();
    }
    h.key === t.BACKSPACE && (a.hasLeftFocus.value = !1, a.segmentValues.value.second = n(P));
  }
  function _(h) {
    if (!((!ut(h.key) || st(h.key)) && h.key !== "a" && h.key !== "p" || !("hour" in a.placeholder.value) || !("dayPeriod" in a.segmentValues.value))) {
      if (h.key === t.ARROW_UP || h.key === t.ARROW_DOWN) {
        if (a.segmentValues.value.dayPeriod === "AM") {
          a.segmentValues.value.dayPeriod = "PM", a.segmentValues.value.hour = a.segmentValues.value.hour + 12;
          return;
        }
        a.segmentValues.value.dayPeriod = "AM", a.segmentValues.value.hour = a.segmentValues.value.hour - 12;
        return;
      }
      if (["a", "A"].includes(h.key) && a.segmentValues.value.dayPeriod !== "AM") {
        a.segmentValues.value.dayPeriod = "AM", a.segmentValues.value.hour = a.segmentValues.value.hour - 12;
        return;
      }
      ["p", "P"].includes(h.key) && a.segmentValues.value.dayPeriod !== "PM" && (a.segmentValues.value.dayPeriod = "PM", a.segmentValues.value.hour = a.segmentValues.value.hour + 12);
    }
  }
  function C(h) {
    a.disabled.value && h.preventDefault();
  }
  function $(h) {
    const E = a.disabled.value, P = a.readonly.value;
    if (h.key !== t.TAB && h.preventDefault(), E || P)
      return;
    if ({
      day: c,
      month: f,
      year: v,
      hour: p,
      minute: g,
      second: m,
      dayPeriod: _,
      timeZoneName: () => {
      }
    }[a.part](h), ![t.ARROW_LEFT, t.ARROW_RIGHT].includes(h.key) && h.key !== t.TAB && h.key !== t.SHIFT && ut(h.key) && Object.values(a.segmentValues.value).every((I) => I !== null)) {
      const I = { ...a.segmentValues.value };
      let M = a.placeholder.value.copy();
      Object.keys(I).forEach((V) => {
        const A = I[V];
        M = M.set({ [V]: A });
      }), a.modelValue.value = M.copy();
    }
  }
  return {
    handleSegmentClick: C,
    handleSegmentKeydown: $,
    attributes: d
  };
}
const nc = /* @__PURE__ */ x({
  __name: "DateFieldInput",
  props: {
    part: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Hd(), n = T(!0), l = T(!1), {
      handleSegmentClick: s,
      handleSegmentKeydown: r,
      attributes: i
    } = cs({
      hasLeftFocus: n,
      lastKeyZero: l,
      placeholder: e.placeholder,
      hourCycle: e.hourCycle,
      segmentValues: e.segmentValues,
      formatter: e.formatter,
      part: t.part,
      disabled: e.disabled,
      readonly: e.readonly,
      focusNext: e.focusNext,
      modelValue: e.modelValue
    }), u = B(() => e.disabled.value), d = B(() => e.readonly.value), c = B(() => e.isInvalid.value);
    return (f, v) => (b(), S(o(O), k({
      as: f.as,
      "as-child": f.asChild
    }, o(i), {
      contenteditable: u.value || d.value ? !1 : f.part !== "literal",
      "data-radix-vue-date-field-segment": f.part,
      "aria-disabled": u.value ? !0 : void 0,
      "aria-readonly": d.value ? !0 : void 0,
      "data-disabled": u.value ? "" : void 0,
      "data-invalid": c.value ? "" : void 0,
      "aria-invalid": c.value ? !0 : void 0
    }, Kn(f.part !== "literal" ? {
      mousedown: o(s),
      keydown: o(r),
      focusout: () => {
        n.value = !0;
      },
      focusin: (p) => {
        o(e).setFocusedElement(p.target);
      }
    } : {})), {
      default: y(() => [
        w(f.$slots, "default")
      ]),
      _: 3
    }, 16, ["as", "as-child", "contenteditable", "data-radix-vue-date-field-segment", "aria-disabled", "aria-readonly", "data-disabled", "data-invalid", "aria-invalid"]));
  }
}), xm = /* @__PURE__ */ x({
  __name: "DatePickerHeader",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Wu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Sm = /* @__PURE__ */ x({
  __name: "DatePickerHeading",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(ju), W(U(t)), {
      default: y(({ headingValue: l }) => [
        w(e.$slots, "default", { headingValue: l }, () => [
          ye(De(l), 1)
        ])
      ]),
      _: 3
    }, 16));
  }
}), Em = /* @__PURE__ */ x({
  __name: "DatePickerGrid",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Uu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Pm = /* @__PURE__ */ x({
  __name: "DatePickerCell",
  props: {
    date: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Gu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Dm = /* @__PURE__ */ x({
  __name: "DatePickerHeadCell",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(qu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), $m = /* @__PURE__ */ x({
  __name: "DatePickerNext",
  props: {
    step: {},
    nextPage: { type: Function },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Yu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Bm = /* @__PURE__ */ x({
  __name: "DatePickerPrev",
  props: {
    step: {},
    prevPage: { type: Function },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Xu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Im = /* @__PURE__ */ x({
  __name: "DatePickerGridHead",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Zu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Tm = /* @__PURE__ */ x({
  __name: "DatePickerGridBody",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Ju), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Rm = /* @__PURE__ */ x({
  __name: "DatePickerGridRow",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Qu), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Am = /* @__PURE__ */ x({
  __name: "DatePickerCellTrigger",
  props: {
    day: {},
    month: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(ed), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Om = /* @__PURE__ */ x({
  __name: "DatePickerInput",
  props: {
    part: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(nc), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [wo, oc] = te("DatePickerRoot"), km = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "DatePickerRoot",
  props: {
    defaultValue: { default: void 0 },
    defaultPlaceholder: {},
    placeholder: { default: void 0 },
    modelValue: {},
    hourCycle: {},
    granularity: {},
    hideTimeZone: { type: Boolean },
    maxValue: {},
    minValue: {},
    locale: { default: "en" },
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean, default: !1 },
    isDateUnavailable: { type: Function, default: void 0 },
    name: {},
    required: { type: Boolean },
    id: {},
    dir: {},
    asChild: { type: Boolean },
    as: {},
    defaultOpen: { type: Boolean, default: !1 },
    open: { type: Boolean, default: void 0 },
    modal: { type: Boolean, default: !1 },
    isDateDisabled: { type: Function, default: void 0 },
    pagedNavigation: { type: Boolean, default: !1 },
    weekStartsOn: { default: 0 },
    weekdayFormat: { default: "narrow" },
    fixedWeeks: { type: Boolean, default: !1 },
    numberOfMonths: { default: 1 },
    preventDeselect: { type: Boolean, default: !1 }
  },
  emits: ["update:modelValue", "update:placeholder", "update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, {
      locale: l,
      disabled: s,
      readonly: r,
      pagedNavigation: i,
      weekStartsOn: u,
      weekdayFormat: d,
      fixedWeeks: c,
      numberOfMonths: f,
      preventDeselect: v,
      isDateDisabled: p,
      isDateUnavailable: g,
      defaultOpen: m,
      modal: _,
      id: C,
      name: $,
      required: h,
      minValue: E,
      maxValue: P,
      granularity: D,
      hideTimeZone: I,
      hourCycle: M,
      defaultValue: V,
      dir: A
    } = ae(e), F = we(A), j = ne(e, "modelValue", n, {
      defaultValue: V.value,
      passive: e.modelValue === void 0
    }), H = B(() => Yt({
      defaultPlaceholder: e.placeholder,
      granularity: e.granularity,
      defaultValue: j.value,
      locale: e.locale
    })), Q = ne(e, "placeholder", n, {
      defaultValue: e.defaultPlaceholder ?? H.value.copy(),
      passive: e.placeholder === void 0
    }), G = ne(e, "open", n, {
      defaultValue: m.value,
      passive: e.open === void 0
    }), J = T();
    return ee(j, (z) => {
      z && z.compare(Q.value) !== 0 && (Q.value = z.copy());
    }), oc({
      isDateUnavailable: g.value,
      isDateDisabled: p.value,
      locale: l,
      disabled: s,
      pagedNavigation: i,
      weekStartsOn: u,
      weekdayFormat: d,
      fixedWeeks: c,
      numberOfMonths: f,
      readonly: r,
      preventDeselect: v,
      modelValue: j,
      placeholder: Q,
      defaultOpen: m,
      modal: _,
      open: G,
      id: C,
      name: $,
      required: h,
      minValue: E,
      maxValue: P,
      granularity: D,
      hideTimeZone: I,
      hourCycle: M,
      dateFieldRef: J,
      dir: F,
      onDateChange(z) {
        !z || !j.value ? j.value = (z == null ? void 0 : z.copy()) ?? void 0 : !v.value && z && j.value.compare(z) === 0 ? j.value = void 0 : j.value = z.copy();
      },
      onPlaceholderChange(z) {
        Q.value = z.copy();
      }
    }), (z, K) => (b(), S(o(Cs), {
      open: o(G),
      "onUpdate:open": K[0] || (K[0] = (L) => et(G) ? G.value = L : null),
      "default-open": o(m),
      modal: o(_)
    }, {
      default: y(() => [
        w(z.$slots, "default")
      ]),
      _: 3
    }, 8, ["open", "default-open", "modal"]));
  }
}), Mm = /* @__PURE__ */ x({
  __name: "DatePickerCalendar",
  setup(a) {
    const t = wo();
    return (e, n) => (b(), S(o(Hu), k({
      isDateDisabled: o(t).isDateDisabled,
      isDateUnavailable: o(t).isDateUnavailable,
      minValue: o(t).minValue.value,
      maxValue: o(t).maxValue.value,
      locale: o(t).locale.value,
      disabled: o(t).disabled.value,
      pagedNavigation: o(t).pagedNavigation.value,
      weekStartsOn: o(t).weekStartsOn.value,
      weekdayFormat: o(t).weekdayFormat.value,
      fixedWeeks: o(t).fixedWeeks.value,
      numberOfMonths: o(t).numberOfMonths.value,
      readonly: o(t).readonly.value,
      preventDeselect: o(t).preventDeselect.value,
      dir: o(t).dir.value
    }, {
      "model-value": o(t).modelValue.value,
      placeholder: o(t).placeholder.value,
      "initial-focus": "",
      multiple: !1,
      "onUpdate:modelValue": n[0] || (n[0] = (l) => {
        l && o(t).modelValue.value && o(ke)(l, o(t).modelValue.value) || o(t).onDateChange(l);
      }),
      "onUpdate:placeholder": n[1] || (n[1] = (l) => {
        o(ke)(l, o(t).placeholder.value) || o(t).onPlaceholderChange(l);
      })
    }), {
      default: y(({ weekDays: l, grid: s, date: r, weekStartsOn: i, locale: u, fixedWeeks: d }) => [
        w(e.$slots, "default", {
          date: r,
          grid: s,
          weekDays: l,
          weekStartsOn: i,
          locale: u,
          fixedWeeks: d
        })
      ]),
      _: 3
    }, 16, ["model-value", "placeholder"]));
  }
}), Vm = /* @__PURE__ */ x({
  __name: "DatePickerField",
  setup(a) {
    const t = wo();
    return (e, n) => (b(), S(o(jd), k({
      ref: o(t).dateFieldRef,
      "model-value": o(t).modelValue.value,
      placeholder: o(t).placeholder.value
    }, {
      id: o(t).id.value,
      name: o(t).name.value,
      disabled: o(t).disabled.value,
      minValue: o(t).minValue.value,
      maxValue: o(t).maxValue.value,
      readonly: o(t).readonly.value,
      hourCycle: o(t).hourCycle.value,
      granularity: o(t).granularity.value,
      hideTimeZone: o(t).hideTimeZone.value,
      locale: o(t).locale.value,
      isDateUnavailable: o(t).isDateUnavailable,
      required: o(t).required.value,
      dir: o(t).dir.value
    }, {
      "onUpdate:modelValue": n[0] || (n[0] = (l) => {
        l && o(t).modelValue.value && l.compare(o(t).modelValue.value) === 0 || o(t).onDateChange(l);
      }),
      "onUpdate:placeholder": n[1] || (n[1] = (l) => {
        l.compare(o(t).placeholder.value) !== 0 && o(t).onPlaceholderChange(l);
      })
    }), {
      default: y(({ segments: l, modelValue: s }) => [
        w(e.$slots, "default", {
          segments: l,
          modelValue: s
        })
      ]),
      _: 3
    }, 16, ["model-value", "placeholder"]));
  }
}), Fm = /* @__PURE__ */ x({
  __name: "DatePickerAnchor",
  props: {
    element: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Ds), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Nm = /* @__PURE__ */ x({
  __name: "DatePickerArrow",
  props: {
    width: {},
    height: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Es), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Lm = /* @__PURE__ */ x({
  __name: "DatePickerClose",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Ps), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), zm = /* @__PURE__ */ x({
  __name: "DatePickerTrigger",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = wo();
    return (n, l) => (b(), S(o(ws), k({ "data-radix-vue-date-field-segment": "trigger" }, t, {
      disabled: o(e).disabled.value,
      onFocusin: l[0] || (l[0] = (s) => {
        var r;
        (r = o(e).dateFieldRef.value) == null || r.setFocusedElement(s.target);
      })
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["disabled"]));
  }
}), Km = /* @__PURE__ */ x({
  __name: "DatePickerContent",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return (s, r) => (b(), S(o(_s), null, {
      default: y(() => [
        q(o(Ss), W(U({ ...o(l), ...s.$attrs })), {
          default: y(() => [
            w(s.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }));
  }
}), Hm = /* @__PURE__ */ x({
  __name: "DateRangePickerHeader",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(gf), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Wm = /* @__PURE__ */ x({
  __name: "DateRangePickerHeading",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(bf), W(U(t)), {
      default: y(({ headingValue: l }) => [
        w(e.$slots, "default", { headingValue: l }, () => [
          ye(De(l), 1)
        ])
      ]),
      _: 3
    }, 16));
  }
}), jm = /* @__PURE__ */ x({
  __name: "DateRangePickerGrid",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Cf), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Um = /* @__PURE__ */ x({
  __name: "DateRangePickerCell",
  props: {
    date: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(wf), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Gm = /* @__PURE__ */ x({
  __name: "DateRangePickerHeadCell",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(_f), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), qm = /* @__PURE__ */ x({
  __name: "DateRangePickerNext",
  props: {
    step: {},
    nextPage: { type: Function },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(xf), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ym = /* @__PURE__ */ x({
  __name: "DateRangePickerPrev",
  props: {
    step: {},
    prevPage: { type: Function },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Sf), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Xm = /* @__PURE__ */ x({
  __name: "DateRangePickerGridHead",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Ef), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Zm = /* @__PURE__ */ x({
  __name: "DateRangePickerGridBody",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Pf), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Jm = /* @__PURE__ */ x({
  __name: "DateRangePickerGridRow",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Df), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Qm = /* @__PURE__ */ x({
  __name: "DateRangePickerCellTrigger",
  props: {
    day: {},
    month: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o($f), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), eh = /* @__PURE__ */ x({
  __name: "DateRangePickerInput",
  props: {
    part: {},
    type: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(dc), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [_o, lc] = te("DateRangePickerRoot"), th = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "DateRangePickerRoot",
  props: {
    defaultValue: { default: () => ({ start: void 0, end: void 0 }) },
    defaultPlaceholder: {},
    placeholder: { default: void 0 },
    modelValue: {},
    hourCycle: {},
    granularity: {},
    hideTimeZone: { type: Boolean },
    maxValue: {},
    minValue: {},
    locale: { default: "en" },
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean, default: !1 },
    isDateUnavailable: { type: Function, default: void 0 },
    name: {},
    required: { type: Boolean },
    id: {},
    dir: {},
    asChild: { type: Boolean },
    as: {},
    defaultOpen: { type: Boolean, default: !1 },
    open: { type: Boolean, default: void 0 },
    modal: { type: Boolean, default: !1 },
    isDateDisabled: { type: Function, default: void 0 },
    pagedNavigation: { type: Boolean, default: !1 },
    weekStartsOn: { default: 0 },
    weekdayFormat: { default: "narrow" },
    fixedWeeks: { type: Boolean, default: !1 },
    numberOfMonths: { default: 1 },
    preventDeselect: { type: Boolean, default: !1 }
  },
  emits: ["update:modelValue", "update:placeholder", "update:startValue", "update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, {
      locale: l,
      disabled: s,
      readonly: r,
      pagedNavigation: i,
      weekStartsOn: u,
      weekdayFormat: d,
      fixedWeeks: c,
      numberOfMonths: f,
      preventDeselect: v,
      isDateDisabled: p,
      isDateUnavailable: g,
      defaultOpen: m,
      modal: _,
      id: C,
      name: $,
      required: h,
      minValue: E,
      maxValue: P,
      granularity: D,
      hideTimeZone: I,
      hourCycle: M,
      dir: V
    } = ae(e), A = we(V), F = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue ?? { start: void 0, end: void 0 },
      passive: e.modelValue === void 0
    }), j = Yt({
      defaultPlaceholder: e.placeholder,
      granularity: e.granularity,
      defaultValue: F.value.start,
      locale: e.locale
    }), H = ne(e, "placeholder", n, {
      defaultValue: e.defaultPlaceholder ?? j.copy(),
      passive: e.placeholder === void 0
    }), Q = ne(e, "open", n, {
      defaultValue: m.value,
      passive: e.open === void 0
    }), G = T();
    return ee(F, (J) => {
      J.start && J.start.compare(H.value) !== 0 && (H.value = J.start.copy());
    }), lc({
      isDateUnavailable: g.value,
      isDateDisabled: p.value,
      locale: l,
      disabled: s,
      pagedNavigation: i,
      weekStartsOn: u,
      weekdayFormat: d,
      fixedWeeks: c,
      numberOfMonths: f,
      readonly: r,
      preventDeselect: v,
      modelValue: F,
      placeholder: H,
      defaultOpen: m,
      modal: _,
      open: Q,
      id: C,
      name: $,
      required: h,
      minValue: E,
      maxValue: P,
      granularity: D,
      hideTimeZone: I,
      hourCycle: M,
      dateFieldRef: G,
      dir: A,
      onStartValueChange(J) {
        n("update:startValue", J);
      },
      onDateChange(J) {
        var z, K;
        F.value = { start: (z = J.start) == null ? void 0 : z.copy(), end: (K = J.end) == null ? void 0 : K.copy() };
      },
      onPlaceholderChange(J) {
        H.value = J.copy();
      }
    }), (J, z) => (b(), S(o(Cs), {
      open: o(Q),
      "onUpdate:open": z[0] || (z[0] = (K) => et(Q) ? Q.value = K : null),
      "default-open": o(m),
      modal: o(_)
    }, {
      default: y(() => [
        w(J.$slots, "default")
      ]),
      _: 3
    }, 8, ["open", "default-open", "modal"]));
  }
}), ah = /* @__PURE__ */ x({
  __name: "DateRangePickerCalendar",
  setup(a) {
    const t = _o();
    return (e, n) => (b(), S(o(yf), k({
      isDateDisabled: o(t).isDateDisabled,
      isDateUnavailable: o(t).isDateUnavailable,
      locale: o(t).locale.value,
      disabled: o(t).disabled.value,
      pagedNavigation: o(t).pagedNavigation.value,
      weekStartsOn: o(t).weekStartsOn.value,
      weekdayFormat: o(t).weekdayFormat.value,
      fixedWeeks: o(t).fixedWeeks.value,
      numberOfMonths: o(t).numberOfMonths.value,
      readonly: o(t).readonly.value,
      preventDeselect: o(t).preventDeselect.value,
      minValue: o(t).minValue.value,
      maxValue: o(t).maxValue.value,
      dir: o(t).dir.value
    }, {
      "initial-focus": "",
      "model-value": o(t).modelValue.value,
      placeholder: o(t).placeholder.value,
      "onUpdate:startValue": n[0] || (n[0] = (l) => {
        o(t).onStartValueChange(l);
      }),
      "onUpdate:modelValue": n[1] || (n[1] = (l) => {
        l.start && o(t).modelValue.value.start && l.end && o(t).modelValue.value.end && o(ke)(l.start, o(t).modelValue.value.start) && o(ke)(l.end, o(t).modelValue.value.end) || o(t).onDateChange(l);
      }),
      "onUpdate:placeholder": n[2] || (n[2] = (l) => {
        o(ke)(l, o(t).placeholder.value) || o(t).onPlaceholderChange(l);
      })
    }), {
      default: y(({ weekDays: l, grid: s, date: r, weekStartsOn: i, locale: u, fixedWeeks: d }) => [
        w(e.$slots, "default", {
          date: r,
          grid: s,
          weekDays: l,
          weekStartsOn: i,
          locale: u,
          fixedWeeks: d
        })
      ]),
      _: 3
    }, 16, ["model-value", "placeholder"]));
  }
}), nh = /* @__PURE__ */ x({
  __name: "DateRangePickerField",
  setup(a) {
    const t = _o();
    return (e, n) => (b(), S(o(uc), k({
      ref: o(t).dateFieldRef,
      "model-value": o(t).modelValue.value,
      placeholder: o(t).placeholder.value
    }, {
      id: o(t).id.value,
      name: o(t).name.value,
      disabled: o(t).disabled.value,
      minValue: o(t).minValue.value,
      maxValue: o(t).maxValue.value,
      readonly: o(t).readonly.value,
      hourCycle: o(t).hourCycle.value,
      granularity: o(t).granularity.value,
      hideTimeZone: o(t).hideTimeZone.value,
      locale: o(t).locale.value,
      isDateUnavailable: o(t).isDateUnavailable,
      required: o(t).required.value,
      dir: o(t).dir.value
    }, {
      "onUpdate:modelValue": n[0] || (n[0] = (l) => {
        l.start && o(t).modelValue.value.start && l.end && o(t).modelValue.value.end && l.start.compare(o(t).modelValue.value.start) === 0 && l.end.compare(o(t).modelValue.value.end) === 0 || o(t).onDateChange(l);
      }),
      "onUpdate:placeholder": n[1] || (n[1] = (l) => {
        o(ke)(l, o(t).placeholder.value) && l.compare(o(t).placeholder.value) === 0 || o(t).onPlaceholderChange(l);
      })
    }), {
      default: y(({ segments: l, modelValue: s }) => [
        w(e.$slots, "default", {
          segments: l,
          modelValue: s
        })
      ]),
      _: 3
    }, 16, ["model-value", "placeholder"]));
  }
}), oh = /* @__PURE__ */ x({
  __name: "DateRangePickerAnchor",
  props: {
    element: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Ds), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), lh = /* @__PURE__ */ x({
  __name: "DateRangePickerArrow",
  props: {
    width: {},
    height: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Es), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), sh = /* @__PURE__ */ x({
  __name: "DateRangePickerClose",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(Ps), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), rh = /* @__PURE__ */ x({
  __name: "DateRangePickerTrigger",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = _o();
    return (n, l) => (b(), S(o(ws), k({ "data-radix-vue-date-field-segment": "trigger" }, t, {
      disabled: o(e).disabled.value,
      onFocusin: l[0] || (l[0] = (s) => {
        var r;
        (r = o(e).dateFieldRef.value) == null || r.setFocusedElement(s.target);
      })
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["disabled"]));
  }
}), ih = /* @__PURE__ */ x({
  __name: "DateRangePickerContent",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return (s, r) => (b(), S(o(_s), null, {
      default: y(() => [
        q(o(Ss), W(U({ ...o(l), ...s.$attrs })), {
          default: y(() => [
            w(s.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }));
  }
}), sc = ["id", "value", "name", "disabled", "required"], [rc, ic] = te("DateRangeFieldRoot"), uc = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "DateRangeFieldRoot",
  props: {
    defaultValue: { default: void 0 },
    defaultPlaceholder: {},
    placeholder: { default: void 0 },
    modelValue: {},
    hourCycle: {},
    granularity: {},
    hideTimeZone: { type: Boolean },
    maxValue: {},
    minValue: {},
    locale: { default: "en" },
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean, default: !1 },
    isDateUnavailable: { type: Function, default: void 0 },
    name: {},
    required: { type: Boolean },
    id: {},
    dir: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "update:placeholder"],
  setup(a, { expose: t, emit: e }) {
    var Y, re;
    const n = a, l = e, { locale: s, disabled: r, readonly: i, isDateUnavailable: u, dir: d } = ae(n), c = qn(n.locale), { primitiveElement: f, currentElement: v } = Re(), p = T(/* @__PURE__ */ new Set()), g = we(d);
    le(() => {
      Ka(v.value).forEach((X) => p.value.add(X));
    });
    const m = ne(n, "modelValue", l, {
      defaultValue: n.defaultValue ?? { start: void 0, end: void 0 },
      passive: n.modelValue === void 0
    }), _ = Yt({
      defaultPlaceholder: n.placeholder,
      granularity: n.granularity,
      defaultValue: m.value.start,
      locale: n.locale
    }), C = ne(n, "placeholder", l, {
      defaultValue: n.defaultPlaceholder ?? _.copy(),
      passive: n.placeholder === void 0
    }), $ = B(() => n.granularity ? ia(C.value) ? n.granularity : "day" : ia(C.value) ? "minute" : "day"), h = B(() => {
      var X;
      return m.value.start ? !!((X = u.value) != null && X.call(u, m.value.start) || n.minValue && Ke(m.value.start, n.minValue) || n.maxValue && Ke(n.maxValue, m.value.start)) : !1;
    }), E = B(() => {
      var X;
      return m.value.end ? !!((X = u.value) != null && X.call(u, m.value.end) || n.minValue && Ke(m.value.end, n.minValue) || n.maxValue && Ke(n.maxValue, m.value.end)) : !1;
    }), P = B(() => h.value || E.value ? !0 : !m.value.start || !m.value.end ? !1 : !Tr(m.value.start, m.value.end) || u.value !== void 0 && !_l(
      m.value.start,
      m.value.end,
      u.value,
      void 0
    )), D = ds($.value), I = T(m.value.start ? { ...Ht({ value: m.value.start, formatter: c }) } : { ...D }), M = T(m.value.end ? { ...Ht({ value: m.value.end, formatter: c }) } : { ...D }), V = B(() => Rn({
      granularity: $.value,
      dateRef: C.value,
      formatter: c,
      hideTimeZone: n.hideTimeZone,
      hourCycle: n.hourCycle,
      segmentValues: I.value,
      locale: s
    })), A = B(() => Rn({
      granularity: $.value,
      dateRef: C.value,
      formatter: c,
      hideTimeZone: n.hideTimeZone,
      hourCycle: n.hourCycle,
      segmentValues: M.value,
      locale: s
    })), F = B(() => ({
      start: V.value.arr,
      end: A.value.arr
    })), j = B(() => ({ start: F.value.start.filter(({ part: X }) => X !== "literal"), end: F.value.end.filter(({ part: X }) => X !== "literal") })), H = T((Y = m.value.start) == null ? void 0 : Y.copy()), Q = T((re = m.value.end) == null ? void 0 : re.copy());
    ee([H, Q], ([X, se]) => {
      m.value = { start: X == null ? void 0 : X.copy(), end: se == null ? void 0 : se.copy() };
    }), ee(m, (X) => {
      X.start && X.end && ((!H.value || X.start.compare(H.value) !== 0) && (H.value = X.start.copy()), (!Q.value || X.end.compare(Q.value) !== 0) && (Q.value = X.end.copy()));
    }), ee([H, s], ([X]) => {
      X !== void 0 ? I.value = { ...Ht({ value: X, formatter: c }) } : Object.values(I.value).every((se) => se !== null) && X === void 0 && (I.value = { ...D });
    }), ee(s, (X) => {
      c.getLocale() !== X && (c.setLocale(X), oe(() => {
        p.value.clear(), Ka(v.value).forEach((se) => p.value.add(se));
      }));
    }), ee(m, (X) => {
      X.start !== void 0 && C.value.compare(X.start) !== 0 && (C.value = X.start.copy());
    }), ee([Q, s], ([X]) => {
      X !== void 0 ? M.value = { ...Ht({ value: X, formatter: c }) } : Object.values(M.value).every((se) => se !== null) && X === void 0 && (M.value = { ...D });
    });
    const G = T(null), J = B(() => Array.from(p.value).findIndex((X) => {
      var se, fe;
      return X.getAttribute("data-radix-vue-date-field-segment") === ((se = G.value) == null ? void 0 : se.getAttribute("data-radix-vue-date-field-segment")) && X.getAttribute("data-radix-vue-date-range-field-segment-type") === ((fe = G.value) == null ? void 0 : fe.getAttribute("data-radix-vue-date-range-field-segment-type"));
    })), z = B(() => {
      const X = g.value === "rtl" ? -1 : 1;
      return (X < 0 ? J.value < 0 : J.value > p.value.size - 1) ? null : Array.from(p.value)[J.value + X];
    }), K = B(() => {
      const X = g.value === "rtl" ? -1 : 1;
      return (X > 0 ? J.value < 0 : J.value > p.value.size - 1) ? null : Array.from(p.value)[J.value - X];
    }), L = nt();
    function N(X) {
      var se, fe;
      st(X.key) && (X.key === L.ARROW_LEFT && ((se = K.value) == null || se.focus()), X.key === L.ARROW_RIGHT && ((fe = z.value) == null || fe.focus()));
    }
    function Z(X) {
      G.value = X;
    }
    return ic({
      isDateUnavailable: u.value,
      locale: s,
      startValue: H,
      endValue: Q,
      placeholder: C,
      disabled: r,
      formatter: c,
      hourCycle: n.hourCycle,
      readonly: i,
      segmentValues: { start: I, end: M },
      isInvalid: P,
      segmentContents: j,
      elements: p,
      setFocusedElement: Z,
      focusNext() {
        var X;
        (X = z.value) == null || X.focus();
      }
    }), t({
      setFocusedElement: Z
    }), (X, se) => {
      var fe, xe;
      return b(), ve(_e, null, [
        q(o(O), k(X.$attrs, {
          ref_key: "primitiveElement",
          ref: f,
          role: "group",
          "aria-disabled": o(r) ? !0 : void 0,
          "data-disabled": o(r) ? "" : void 0,
          "data-readonly": o(i) ? "" : void 0,
          "data-invalid": P.value ? "" : void 0,
          dir: o(g),
          onKeydown: ie(N, ["left", "right"])
        }), {
          default: y(() => [
            w(X.$slots, "default", {
              modelValue: o(m),
              segments: F.value
            })
          ]),
          _: 3
        }, 16, ["aria-disabled", "data-disabled", "data-readonly", "data-invalid", "dir"]),
        Ye("input", {
          id: X.id,
          type: "text",
          tabindex: "-1",
          "aria-hidden": "true",
          value: `${(fe = o(m).start) == null ? void 0 : fe.toString()} - ${(xe = o(m).end) == null ? void 0 : xe.toString()}`,
          name: X.name,
          disabled: o(r),
          required: X.required,
          style: {
            transform: "translateX(-100%)",
            position: "absolute",
            pointerEvents: "none",
            opacity: 0,
            margin: 0
          },
          onFocus: se[0] || (se[0] = (Ee) => {
            var be, de;
            return (de = (be = Array.from(p.value)) == null ? void 0 : be[0]) == null ? void 0 : de.focus();
          })
        }, null, 40, sc)
      ], 64);
    };
  }
}), dc = /* @__PURE__ */ x({
  __name: "DateRangeFieldInput",
  props: {
    part: {},
    type: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = rc(), n = T(!0), l = T(!1), {
      handleSegmentClick: s,
      handleSegmentKeydown: r,
      attributes: i
    } = cs({
      hasLeftFocus: n,
      lastKeyZero: l,
      placeholder: e.placeholder,
      hourCycle: e.hourCycle,
      segmentValues: e.segmentValues[t.type],
      formatter: e.formatter,
      part: t.part,
      disabled: e.disabled,
      readonly: e.readonly,
      focusNext: e.focusNext,
      modelValue: t.type === "start" ? e.startValue : e.endValue
    }), u = B(() => e.disabled.value), d = B(() => e.readonly.value), c = B(() => e.isInvalid.value);
    return (f, v) => (b(), S(o(O), k({
      as: f.as,
      "as-child": f.asChild
    }, o(i), {
      contenteditable: u.value || d.value ? !1 : f.part !== "literal",
      "data-radix-vue-date-field-segment": f.part,
      "aria-disabled": u.value ? !0 : void 0,
      "aria-readonly": d.value ? !0 : void 0,
      "data-disabled": u.value ? "" : void 0,
      "data-radix-vue-date-range-field-segment-type": f.type,
      "data-invalid": c.value ? "" : void 0,
      "aria-invalid": c.value ? !0 : void 0
    }, Kn(f.part !== "literal" ? {
      mousedown: o(s),
      keydown: o(r),
      focusout: () => {
        n.value = !0;
      },
      focusin: (p) => {
        o(e).setFocusedElement(p.target);
      }
    } : {})), {
      default: y(() => [
        w(f.$slots, "default")
      ]),
      _: 3
    }, 16, ["as", "as-child", "contenteditable", "data-radix-vue-date-field-segment", "aria-disabled", "aria-readonly", "data-disabled", "data-radix-vue-date-range-field-segment-type", "data-invalid", "aria-invalid"]));
  }
}), [fs, cc] = te("DropdownMenuRoot"), uh = /* @__PURE__ */ x({
  __name: "DropdownMenuRoot",
  props: {
    defaultOpen: { type: Boolean },
    open: { type: Boolean, default: void 0 },
    dir: {},
    modal: { type: Boolean, default: !0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    const l = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    }), s = T(), { modal: r, dir: i } = ae(e), u = we(i);
    return cc({
      open: l,
      onOpenChange: (d) => {
        l.value = d;
      },
      onOpenToggle: () => {
        l.value = !l.value;
      },
      triggerId: "",
      triggerElement: s,
      contentId: "",
      modal: r,
      dir: u
    }), (d, c) => (b(), S(o(so), {
      open: o(l),
      "onUpdate:open": c[0] || (c[0] = (f) => et(l) ? l.value = f : null),
      dir: o(u),
      modal: o(r)
    }, {
      default: y(() => [
        w(d.$slots, "default", { open: o(l) })
      ]),
      _: 3
    }, 8, ["open", "dir", "modal"]));
  }
}), dh = /* @__PURE__ */ x({
  __name: "DropdownMenuTrigger",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = fs(), { forwardRef: n, currentElement: l } = R();
    return le(() => {
      e.triggerElement = l;
    }), e.triggerId || (e.triggerId = ge(void 0, "radix-vue-dropdown-menu-trigger")), (s, r) => (b(), S(o(Qa), { "as-child": "" }, {
      default: y(() => [
        q(o(O), {
          id: o(e).triggerId,
          ref: o(n),
          type: s.as === "button" ? "button" : void 0,
          "as-child": t.asChild,
          as: s.as,
          "aria-haspopup": "menu",
          "aria-expanded": o(e).open.value,
          "aria-controls": o(e).open.value ? o(e).contentId : void 0,
          "data-disabled": s.disabled ? "" : void 0,
          disabled: s.disabled,
          "data-state": o(e).open.value ? "open" : "closed",
          onClick: r[0] || (r[0] = async (i) => {
            var u;
            !s.disabled && i.button === 0 && i.ctrlKey === !1 && ((u = o(e)) == null || u.onOpenToggle(), await oe(), o(e).open.value && i.preventDefault());
          }),
          onKeydown: r[1] || (r[1] = ie(
            (i) => {
              s.disabled || (["Enter", " "].includes(i.key) && o(e).onOpenToggle(), i.key === "ArrowDown" && o(e).onOpenChange(!0), ["Enter", " ", "ArrowDown"].includes(i.key) && i.preventDefault());
            },
            ["enter", "space", "arrow-down"]
          ))
        }, {
          default: y(() => [
            w(s.$slots, "default")
          ]),
          _: 3
        }, 8, ["id", "type", "as-child", "as", "aria-expanded", "aria-controls", "data-disabled", "disabled", "data-state"])
      ]),
      _: 3
    }));
  }
}), ch = /* @__PURE__ */ x({
  __name: "DropdownMenuPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(vo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), fh = /* @__PURE__ */ x({
  __name: "DropdownMenuContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    R();
    const s = fs(), r = T(!1);
    function i(u) {
      u.defaultPrevented || (r.value || setTimeout(() => {
        var d;
        (d = s.triggerElement.value) == null || d.focus();
      }, 0), r.value = !1, u.preventDefault());
    }
    return s.contentId || (s.contentId = ge(void 0, "radix-vue-dropdown-menu-content")), (u, d) => {
      var c;
      return b(), S(o(fo), k(o(l), {
        id: o(s).contentId,
        "aria-labelledby": (c = o(s)) == null ? void 0 : c.triggerId,
        style: {
          "--radix-dropdown-menu-content-transform-origin": "var(--radix-popper-transform-origin)",
          "--radix-dropdown-menu-content-available-width": "var(--radix-popper-available-width)",
          "--radix-dropdown-menu-content-available-height": "var(--radix-popper-available-height)",
          "--radix-dropdown-menu-trigger-width": "var(--radix-popper-anchor-width)",
          "--radix-dropdown-menu-trigger-height": "var(--radix-popper-anchor-height)"
        },
        onCloseAutoFocus: i,
        onInteractOutside: d[0] || (d[0] = (f) => {
          var m;
          if (f.defaultPrevented) return;
          const v = f.detail.originalEvent, p = v.button === 0 && v.ctrlKey === !0, g = v.button === 2 || p;
          (!o(s).modal.value || g) && (r.value = !0), (m = o(s).triggerElement.value) != null && m.contains(f.target) && f.preventDefault();
        })
      }), {
        default: y(() => [
          w(u.$slots, "default")
        ]),
        _: 3
      }, 16, ["id", "aria-labelledby"]);
    };
  }
}), ph = /* @__PURE__ */ x({
  __name: "DropdownMenuArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(lo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), vh = /* @__PURE__ */ x({
  __name: "DropdownMenuItem",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(xa), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), mh = /* @__PURE__ */ x({
  __name: "DropdownMenuGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(tn), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), hh = /* @__PURE__ */ x({
  __name: "DropdownMenuSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(yo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), yh = /* @__PURE__ */ x({
  __name: "DropdownMenuCheckboxItem",
  props: {
    checked: { type: [Boolean, String] },
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select", "update:checked"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(co), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), gh = /* @__PURE__ */ x({
  __name: "DropdownMenuItemIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(uo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), bh = /* @__PURE__ */ x({
  __name: "DropdownMenuLabel",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(po), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ch = /* @__PURE__ */ x({
  __name: "DropdownMenuRadioGroup",
  props: {
    modelValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(mo), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), wh = /* @__PURE__ */ x({
  __name: "DropdownMenuRadioItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return R(), (s, r) => (b(), S(o(ho), W(U(o(l))), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), _h = /* @__PURE__ */ x({
  __name: "DropdownMenuSub",
  props: {
    defaultOpen: { type: Boolean },
    open: { type: Boolean, default: void 0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "open", t, {
      passive: e.open === void 0,
      defaultValue: e.defaultOpen ?? !1
    });
    return R(), (s, r) => (b(), S(o(go), {
      open: o(l),
      "onUpdate:open": r[0] || (r[0] = (i) => et(l) ? l.value = i : null)
    }, {
      default: y(() => [
        w(s.$slots, "default", { open: o(l) })
      ]),
      _: 3
    }, 8, ["open"]));
  }
}), xh = /* @__PURE__ */ x({
  __name: "DropdownMenuSubContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    sideOffset: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return R(), (s, r) => (b(), S(o(bo), k(o(l), { style: {
      "--radix-dropdown-menu-content-transform-origin": "var(--radix-popper-transform-origin)",
      "--radix-dropdown-menu-content-available-width": "var(--radix-popper-available-width)",
      "--radix-dropdown-menu-content-available-height": "var(--radix-popper-available-height)",
      "--radix-dropdown-menu-trigger-width": "var(--radix-popper-anchor-width)",
      "--radix-dropdown-menu-trigger-height": "var(--radix-popper-anchor-height)"
    } }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Sh = /* @__PURE__ */ x({
  __name: "DropdownMenuSubTrigger",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Co), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), fc = ["value", "name", "disabled", "required"], [ta, pc] = te("EditableRoot"), Eh = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "EditableRoot",
  props: {
    defaultValue: {},
    modelValue: {},
    placeholder: { default: "Enter text..." },
    dir: {},
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean },
    activationMode: { default: "focus" },
    selectOnFocus: { type: Boolean, default: !1 },
    submitMode: { default: "blur" },
    startWithEditMode: { type: Boolean },
    maxLength: {},
    autoResize: { type: Boolean, default: !1 },
    id: {},
    name: {},
    required: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  emits: ["update:modelValue", "submit", "update:state"],
  setup(a, { expose: t, emit: e }) {
    const n = a, l = e, {
      id: s,
      name: r,
      defaultValue: i,
      startWithEditMode: u,
      placeholder: d,
      maxLength: c,
      disabled: f,
      dir: v,
      submitMode: p,
      activationMode: g,
      selectOnFocus: m,
      readonly: _,
      autoResize: C,
      required: $
    } = ae(n), h = T(), E = we(v), P = T(u.value ?? !1), D = ne(n, "modelValue", l, {
      defaultValue: i.value ?? "",
      passive: n.modelValue === void 0
    }), { primitiveElement: I, currentElement: M } = Re(), V = at(M), A = B(() => typeof d.value == "string" ? { edit: d.value, preview: d.value } : d.value), F = T(D.value);
    ee(() => D.value, () => {
      F.value = D.value;
    }, { immediate: !0, deep: !0 });
    function j() {
      P.value = !1, l("update:state", "cancel");
    }
    function H() {
      P.value = !0, F.value = D.value, l("update:state", "edit");
    }
    function Q() {
      D.value = F.value, P.value = !1, l("update:state", "submit"), l("submit", D.value);
    }
    function G() {
      P.value && (p.value === "blur" || p.value === "both" ? Q() : j());
    }
    const J = Ul(() => G(), M), z = Gl(() => G(), M), K = B(() => D.value === "");
    return t({
      /** Function to submit the value of the editable */
      submit: Q,
      /** Function to cancel the value of the editable */
      cancel: j,
      /** Function to set the editable in edit mode */
      edit: H
    }), pc({
      id: s,
      name: r,
      disabled: f,
      isEditing: P,
      maxLength: c,
      modelValue: D,
      inputValue: F,
      placeholder: A,
      edit: H,
      cancel: j,
      submit: Q,
      activationMode: g,
      submitMode: p,
      selectOnFocus: m,
      inputRef: h,
      startWithEditMode: u,
      isEmpty: K,
      readonly: _,
      autoResize: C
    }), (L, N) => (b(), ve(_e, null, [
      q(o(O), k(L.$attrs, {
        ref_key: "primitiveElement",
        ref: I,
        as: L.as,
        "as-child": L.asChild,
        dir: o(E),
        "data-dismissable-layer": "",
        onFocusCapture: o(z).onFocusCapture,
        onBlurCapture: o(z).onBlurCapture,
        onPointerdownCapture: o(J).onPointerDownCapture
      }), {
        default: y(() => [
          w(L.$slots, "default", {
            modelValue: o(D),
            isEditing: P.value,
            isEmpty: K.value,
            submit: Q,
            cancel: j,
            edit: H
          })
        ]),
        _: 3
      }, 16, ["as", "as-child", "dir", "onFocusCapture", "onBlurCapture", "onPointerdownCapture"]),
      o(V) ? (b(), ve("input", {
        key: 0,
        type: "text",
        tabindex: "-1",
        "aria-hidden": "true",
        value: o(D),
        name: o(r),
        disabled: o(f),
        required: o($),
        style: {
          transform: "translateX(-100%)",
          position: "absolute",
          pointerEvents: "none",
          opacity: 0,
          margin: 0
        }
      }, null, 8, fc)) : ce("", !0)
    ], 64));
  }
}), Ph = /* @__PURE__ */ x({
  __name: "EditableArea",
  props: {
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = ta();
    return (n, l) => (b(), S(o(O), k(t, {
      "data-placeholder-shown": o(e).isEditing.value ? void 0 : "",
      "data-focus": o(e).isEditing.value ? "" : void 0,
      "data-focused": o(e).isEditing.value ? "" : void 0,
      "data-empty": o(e).isEmpty.value ? "" : void 0,
      "data-readonly": o(e).readonly.value ? "" : void 0,
      "data-disabled": o(e).disabled.value ? "" : void 0,
      style: o(e).autoResize.value ? { display: "inline-grid" } : void 0
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["data-placeholder-shown", "data-focus", "data-focused", "data-empty", "data-readonly", "data-disabled", "style"]));
  }
}), Dh = /* @__PURE__ */ x({
  __name: "EditableInput",
  props: {
    asChild: { type: Boolean },
    as: { default: "input" }
  },
  setup(a) {
    const t = a, e = nt(), n = ta(), l = B(() => n.disabled.value), s = B(() => {
      var d;
      return (d = n.placeholder.value) == null ? void 0 : d.edit;
    }), { primitiveElement: r, currentElement: i } = Re();
    le(() => {
      var d, c;
      n.inputRef.value = i.value, n.startWithEditMode.value && ((d = n.inputRef.value) == null || d.focus({ preventScroll: !0 }), n.selectOnFocus.value && ((c = n.inputRef.value) == null || c.select()));
    }), ee(n.isEditing, (d) => {
      d && oe(() => {
        var c, f;
        (c = n.inputRef.value) == null || c.focus({ preventScroll: !0 }), n.selectOnFocus.value && ((f = n.inputRef.value) == null || f.select());
      });
    });
    function u(d) {
      (n.submitMode.value === "enter" || n.submitMode.value === "both") && d.key === e.ENTER && !d.shiftKey && !d.metaKey && n.submit();
    }
    return (d, c) => (b(), S(o(O), k({
      ref_key: "primitiveElement",
      ref: r
    }, t, {
      value: o(n).inputValue.value,
      placeholder: s.value,
      disabled: l.value,
      maxlength: o(n).maxLength.value,
      "data-disabled": l.value ? "" : void 0,
      "data-readonly": o(n).readonly.value ? "" : void 0,
      readonly: o(n).readonly.value,
      "aria-label": "editable input",
      hidden: o(n).autoResize.value ? void 0 : !o(n).isEditing.value,
      style: o(n).autoResize.value ? { all: "unset", gridArea: "1 / 1 / auto / auto", visibility: o(n).isEditing.value ? void 0 : "hidden" } : void 0,
      onInput: c[0] || (c[0] = (f) => o(n).inputValue.value = f.target.value),
      onKeydown: [
        ie(u, ["enter", "space"]),
        ie(o(n).cancel, ["esc"])
      ]
    }), {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 16, ["value", "placeholder", "disabled", "maxlength", "data-disabled", "data-readonly", "readonly", "hidden", "style", "onKeydown"]));
  }
}), $h = /* @__PURE__ */ x({
  __name: "EditablePreview",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, e = ta(), n = B(() => {
      var r;
      return (r = e.placeholder.value) == null ? void 0 : r.preview;
    });
    function l() {
      e.activationMode.value === "focus" && e.edit();
    }
    function s() {
      e.activationMode.value === "dblclick" && e.edit();
    }
    return (r, i) => (b(), S(o(O), k(t, {
      tabindex: "0",
      "data-placeholder-shown": o(e).isEditing.value ? void 0 : "",
      hidden: o(e).autoResize.value ? void 0 : o(e).isEditing.value,
      style: o(e).autoResize.value ? {
        whiteSpace: "pre",
        userSelect: "none",
        gridArea: "1 / 1 / auto / auto",
        visibility: o(e).isEditing.value ? "hidden" : void 0,
        overflow: "hidden",
        textOverflow: "ellipsis"
      } : void 0,
      onFocusin: l,
      onDblclick: s
    }), {
      default: y(() => [
        w(r.$slots, "default", {}, () => [
          ye(De(o(e).modelValue.value || n.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["data-placeholder-shown", "hidden", "style"]));
  }
}), Bh = /* @__PURE__ */ x({
  __name: "EditableSubmitTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = ta();
    return (n, l) => (b(), S(o(O), k(t, {
      "aria-label": "submit",
      "aria-disabled": o(e).disabled.value ? "" : void 0,
      "data-disabled": o(e).disabled.value ? "" : void 0,
      disabled: o(e).disabled.value,
      type: n.as === "button" ? "button" : void 0,
      hidden: o(e).isEditing.value ? void 0 : "",
      onClick: o(e).submit
    }), {
      default: y(() => [
        w(n.$slots, "default", {}, () => [
          ye("Submit")
        ])
      ]),
      _: 3
    }, 16, ["aria-disabled", "data-disabled", "disabled", "type", "hidden", "onClick"]));
  }
}), Ih = /* @__PURE__ */ x({
  __name: "EditableCancelTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = ta();
    return (n, l) => (b(), S(o(O), k(t, {
      "aria-label": "cancel",
      "aria-disabled": o(e).disabled.value ? "" : void 0,
      "data-disabled": o(e).disabled.value ? "" : void 0,
      disabled: o(e).disabled.value,
      type: n.as === "button" ? "button" : void 0,
      hidden: o(e).isEditing.value ? void 0 : "",
      onClick: o(e).cancel
    }), {
      default: y(() => [
        w(n.$slots, "default", {}, () => [
          ye("Cancel")
        ])
      ]),
      _: 3
    }, 16, ["aria-disabled", "data-disabled", "disabled", "type", "hidden", "onClick"]));
  }
}), Th = /* @__PURE__ */ x({
  __name: "EditableEditTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = ta();
    return (n, l) => (b(), S(o(O), k(t, {
      "aria-label": "edit",
      "aria-disabled": o(e).disabled.value ? "" : void 0,
      "data-disabled": o(e).disabled.value ? "" : void 0,
      disabled: o(e).disabled.value,
      type: n.as === "button" ? "button" : void 0,
      hidden: o(e).isEditing.value ? "" : void 0,
      onClick: o(e).edit
    }), {
      default: y(() => [
        w(n.$slots, "default", {}, () => [
          ye("Edit")
        ])
      ]),
      _: 3
    }, 16, ["aria-disabled", "data-disabled", "disabled", "type", "hidden", "onClick"]));
  }
}), [xo, vc] = te("HoverCardRoot"), Rh = /* @__PURE__ */ x({
  __name: "HoverCardRoot",
  props: {
    defaultOpen: { type: Boolean, default: !1 },
    open: { type: Boolean, default: void 0 },
    openDelay: { default: 700 },
    closeDelay: { default: 300 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, { openDelay: l, closeDelay: s } = ae(e);
    R();
    const r = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    }), i = T(0), u = T(0), d = T(!1), c = T(!1), f = T(!1), v = T();
    function p() {
      clearTimeout(u.value), i.value = window.setTimeout(() => r.value = !0, l.value);
    }
    function g() {
      clearTimeout(i.value), !d.value && !c.value && (u.value = window.setTimeout(() => r.value = !1, s.value));
    }
    function m() {
      r.value = !1;
    }
    return vc({
      open: r,
      onOpenChange(_) {
        r.value = _;
      },
      onOpen: p,
      onClose: g,
      onDismiss: m,
      hasSelectionRef: d,
      isPointerDownOnContentRef: c,
      isPointerInTransitRef: f,
      triggerElement: v
    }), (_, C) => (b(), S(o(kt), null, {
      default: y(() => [
        w(_.$slots, "default", { open: o(r) })
      ]),
      _: 3
    }));
  }
});
function An(a) {
  return (t) => t.pointerType === "touch" ? void 0 : a();
}
function mc(a) {
  const t = [], e = document.createTreeWalker(a, NodeFilter.SHOW_ELEMENT, {
    acceptNode: (n) => n.tabIndex >= 0 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP
  });
  for (; e.nextNode(); ) t.push(e.currentNode);
  return t;
}
const Ah = /* @__PURE__ */ x({
  __name: "HoverCardTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "a" }
  },
  setup(a) {
    const { forwardRef: t, currentElement: e } = R(), n = xo();
    n.triggerElement = e;
    function l() {
      setTimeout(() => {
        !n.isPointerInTransitRef.value && !n.open.value && n.onClose();
      }, 0);
    }
    return (s, r) => (b(), S(o(Mt), { "as-child": "" }, {
      default: y(() => [
        q(o(O), {
          ref: o(t),
          "as-child": s.asChild,
          as: s.as,
          "data-state": o(n).open.value ? "open" : "closed",
          "data-grace-area-trigger": "",
          onPointerenter: r[0] || (r[0] = (i) => o(An)(o(n).onOpen)(i)),
          onPointerleave: r[1] || (r[1] = (i) => o(An)(l)(i)),
          onFocus: r[2] || (r[2] = (i) => o(n).onOpen()),
          onBlur: r[3] || (r[3] = (i) => o(n).onClose())
        }, {
          default: y(() => [
            w(s.$slots, "default")
          ]),
          _: 3
        }, 8, ["as-child", "as", "data-state"])
      ]),
      _: 3
    }));
  }
}), Oh = /* @__PURE__ */ x({
  __name: "HoverCardPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), hc = /* @__PURE__ */ x({
  __name: "HoverCardContentImpl",
  props: {
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Ot(e), { forwardRef: s, currentElement: r } = R(), i = xo(), { isPointerInTransit: u, onPointerExit: d } = Fl(i.triggerElement, r);
    mi(i.isPointerInTransitRef, u, { direction: "rtl" }), d(() => {
      i.onClose();
    });
    const c = T(!1);
    let f;
    Ce((p) => {
      if (c.value) {
        const g = document.body;
        f = g.style.userSelect || g.style.webkitUserSelect, g.style.userSelect = "none", g.style.webkitUserSelect = "none", p(() => {
          g.style.userSelect = f, g.style.webkitUserSelect = f;
        });
      }
    });
    function v() {
      c.value = !1, i.isPointerDownOnContentRef.value = !1, oe(() => {
        var g;
        ((g = document.getSelection()) == null ? void 0 : g.toString()) !== "" && (i.hasSelectionRef.value = !0);
      });
    }
    return le(() => {
      r.value && (document.addEventListener("pointerup", v), mc(r.value).forEach((g) => g.setAttribute("tabindex", "-1")));
    }), Be(() => {
      document.removeEventListener("pointerup", v), i.hasSelectionRef.value = !1, i.isPointerDownOnContentRef.value = !1;
    }), (p, g) => (b(), S(o(Ct), {
      "as-child": "",
      "disable-outside-pointer-events": !1,
      onEscapeKeyDown: g[1] || (g[1] = (m) => n("escapeKeyDown", m)),
      onPointerDownOutside: g[2] || (g[2] = (m) => n("pointerDownOutside", m)),
      onFocusOutside: g[3] || (g[3] = ue((m) => n("focusOutside", m), ["prevent"])),
      onDismiss: o(i).onDismiss
    }, {
      default: y(() => [
        q(o(It), k({ ...o(l), ...p.$attrs }, {
          ref: o(s),
          "data-state": o(i).open.value ? "open" : "closed",
          style: {
            userSelect: c.value ? "text" : void 0,
            // Safari requires prefix
            WebkitUserSelect: c.value ? "text" : void 0,
            // re-namespace exposed content custom properties
            "--radix-hover-card-content-transform-origin": "var(--radix-popper-transform-origin)",
            "--radix-hover-card-content-available-width": "var(--radix-popper-available-width)",
            "--radix-hover-card-content-available-height": "var(--radix-popper-available-height)",
            "--radix-hover-card-trigger-width": "var(--radix-popper-anchor-width)",
            "--radix-hover-card-trigger-height": "var(--radix-popper-anchor-height)"
          },
          onPointerdown: g[0] || (g[0] = (m) => {
            m.currentTarget.contains(m.target) && (c.value = !0), o(i).hasSelectionRef.value = !1, o(i).isPointerDownOnContentRef.value = !0;
          })
        }), {
          default: y(() => [
            w(p.$slots, "default")
          ]),
          _: 3
        }, 16, ["data-state", "style"])
      ]),
      _: 3
    }, 8, ["onDismiss"]));
  }
}), kh = /* @__PURE__ */ x({
  __name: "HoverCardContent",
  props: {
    forceMount: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside"],
  setup(a, { emit: t }) {
    const l = Se(a, t), { forwardRef: s } = R(), r = xo();
    return (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(r).open.value
    }, {
      default: y(() => [
        q(hc, k(o(l), {
          ref: o(s),
          onPointerenter: u[0] || (u[0] = (d) => o(An)(o(r).onOpen)(d))
        }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Mh = /* @__PURE__ */ x({
  __name: "HoverCardArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Zt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Vh = /* @__PURE__ */ x({
  __name: "Label",
  props: {
    for: {},
    asChild: { type: Boolean },
    as: { default: "label" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(O), k(t, {
      onMousedown: n[0] || (n[0] = (l) => {
        !l.defaultPrevented && l.detail > 1 && l.preventDefault();
      })
    }), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
});
function yc(a) {
  return a == null ? void 0 : a.querySelector("[data-state=checked]");
}
function gc(a, t, e) {
  return a === void 0 ? !1 : Array.isArray(a) ? a.some((n) => Gt(n, t, e)) : Gt(a, t, e);
}
function Gt(a, t, e) {
  return a === void 0 || t === void 0 ? !1 : typeof a == "string" ? a === t : typeof e == "function" ? e(a, t) : typeof e == "string" ? (a == null ? void 0 : a[e]) === (t == null ? void 0 : t[e]) : Qe(a, t);
}
const [an, bc] = te("ListboxRoot"), Fh = /* @__PURE__ */ x({
  __name: "ListboxRoot",
  props: {
    modelValue: {},
    defaultValue: {},
    multiple: { type: Boolean },
    orientation: { default: "vertical" },
    dir: {},
    disabled: { type: Boolean },
    selectionBehavior: { default: "toggle" },
    highlightOnHover: { type: Boolean },
    by: {},
    name: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "highlight", "entryFocus", "leave"],
  setup(a, { emit: t }) {
    const e = a, n = t, { multiple: l, highlightOnHover: s, orientation: r, disabled: i, selectionBehavior: u, dir: d } = ae(e), { getItems: c } = Ca(), { handleTypeaheadSearch: f } = ba(), { primitiveElement: v, currentElement: p } = Re(), g = nt(), m = we(d), _ = at(p), C = T(), $ = T(!1), h = T(!0), E = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue ?? (l.value ? [] : void 0),
      passive: e.modelValue === void 0,
      deep: !0
    });
    function P(N) {
      if ($.value = !0, Array.isArray(E.value)) {
        const Z = E.value.findIndex((Y) => Gt(Y, N, e.by));
        if (e.selectionBehavior === "toggle") {
          const Y = [...E.value];
          Z === -1 ? Y.push(N) : Y.splice(Z, 1), E.value = Y;
        } else
          E.value = [N], C.value = N;
      } else
        e.selectionBehavior === "toggle" && Gt(E.value, N, e.by) ? E.value = void 0 : E.value = N;
      setTimeout(() => {
        $.value = !1;
      }, 1);
    }
    const D = T(null), I = T(null), M = T(!1), V = ua(), A = ua();
    function F() {
      return c().map((N) => N.ref).filter((N) => N.dataset.disabled !== "");
    }
    function j(N) {
      if (!N)
        return;
      D.value = N, D.value.focus(), D.value.scrollIntoView({ block: "nearest" });
      const Z = c().find((Y) => Y.ref === N);
      n("highlight", Z);
    }
    function H(N) {
      D.value && D.value.click();
    }
    function Q(N) {
      if ($.value = !0, M.value)
        A.trigger(N);
      else {
        const Z = N.altKey || N.ctrlKey || N.metaKey;
        if (Z && N.key === "a" && l.value) {
          const Y = c(), re = Y.map((X) => X.value);
          E.value = [...re], N.preventDefault(), j(Y[Y.length - 1].ref);
        } else if (!Z) {
          const Y = f(N.key, F());
          Y && j(Y);
        }
      }
      setTimeout(() => {
        $.value = !1;
      }, 1);
    }
    function G(N) {
      const Z = D.value;
      Z != null && Z.isConnected && (I.value = Z), D.value = null, n("leave", N);
    }
    function J(N) {
      var Y, re;
      const Z = new CustomEvent("listbox.entryFocus", { bubbles: !1, cancelable: !0 });
      if ((Y = N.currentTarget) == null || Y.dispatchEvent(Z), n("entryFocus", Z), !Z.defaultPrevented)
        if (I.value)
          j(I.value);
        else {
          const X = (re = F()) == null ? void 0 : re[0];
          j(X);
        }
    }
    function z(N) {
      const Z = os(N, r.value, m.value);
      if (!Z)
        return;
      let Y = F();
      if (D.value) {
        if (Z === "last")
          Y.reverse();
        else if (Z === "prev" || Z === "next") {
          Z === "prev" && Y.reverse();
          const re = Y.indexOf(D.value);
          Y = Y.slice(re + 1);
        }
        K(N, Y[0]);
      }
      if (Y.length) {
        const re = !D.value && Z === "prev" ? Y.length - 1 : 0;
        j(Y[re]);
      }
      if (M.value)
        return A.trigger(N);
    }
    function K(N, Z) {
      var re;
      if (!(M.value || e.selectionBehavior !== "replace" || !l.value || !Array.isArray(E.value) || (N.altKey || N.ctrlKey || N.metaKey) && !N.shiftKey) && N.shiftKey) {
        const X = c().filter((xe) => xe.ref.dataset.disabled !== "");
        let se = (re = X.find((xe) => xe.ref === Z)) == null ? void 0 : re.value;
        if (N.key === g.END ? se = X[X.length - 1].value : N.key === g.HOME && (se = X[0].value), !se || !C.value)
          return;
        const fe = Bt(X.map((xe) => xe.value), C.value, se);
        E.value = fe;
      }
    }
    async function L(N) {
      if (M.value)
        V.trigger(N);
      else {
        await oe();
        const Y = F().find((re) => re.dataset.state === "checked");
        Y && j(Y);
      }
    }
    return ee(E, () => {
      $.value || oe(() => {
        L();
      });
    }, { immediate: !0, deep: !0 }), bc({
      modelValue: E,
      // @ts-expect-error ignoring
      onValueChange: P,
      multiple: l,
      orientation: r,
      dir: m,
      disabled: i,
      highlightOnHover: s,
      highlightedElement: D,
      isVirtual: M,
      virtualFocusHook: V,
      virtualKeydownHook: A,
      by: e.by,
      firstValue: C,
      selectionBehavior: u,
      focusable: h,
      onLeave: G,
      onEnter: J,
      onChangeHighlight: j,
      onKeydownEnter: H,
      onKeydownNavigation: z,
      onKeydownTypeAhead: Q
    }), (N, Z) => (b(), S(o(O), {
      ref_key: "primitiveElement",
      ref: v,
      as: N.as,
      "as-child": N.asChild,
      dir: o(m),
      "data-disabled": o(i) ? "" : void 0,
      onPointerleave: G,
      onFocusout: Z[0] || (Z[0] = async (Y) => {
        const re = Y.relatedTarget || Y.target;
        await oe(), D.value && o(p) && !o(p).contains(re) && G(Y);
      })
    }, {
      default: y(() => [
        w(N.$slots, "default", { modelValue: o(E) }),
        o(_) && e.name ? (b(), S(o(no), {
          key: 0,
          name: e.name,
          value: o(E)
        }, null, 8, ["name", "value"])) : ce("", !0)
      ]),
      _: 3
    }, 8, ["as", "as-child", "dir", "data-disabled"]));
  }
}), Nh = /* @__PURE__ */ x({
  __name: "ListboxContent",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = an(), e = Tt(!1, 10);
    return (n, l) => (b(), S(o(wa), null, {
      default: y(() => [
        q(o(O), {
          role: "listbox",
          as: n.as,
          "as-child": n.asChild,
          tabindex: o(t).focusable.value ? o(t).highlightedElement.value ? "-1" : "0" : void 0,
          "aria-orientation": o(t).orientation.value,
          "aria-multiselectable": !!o(t).multiple.value,
          "data-orientation": o(t).orientation.value,
          onMousedown: l[0] || (l[0] = ue((s) => e.value = !0, ["left"])),
          onFocus: l[1] || (l[1] = (s) => {
            o(e) || o(t).onEnter(s);
          }),
          onKeydown: [
            l[2] || (l[2] = ie(ue((s) => {
              o(t).focusable.value && o(t).onKeydownNavigation(s);
            }, ["prevent"]), ["down", "up", "left", "right", "home", "end"])),
            ie(o(t).onKeydownEnter, ["enter"]),
            o(t).onKeydownTypeAhead
          ]
        }, {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 8, ["as", "as-child", "tabindex", "aria-orientation", "aria-multiselectable", "data-orientation", "onKeydown"])
      ]),
      _: 3
    }));
  }
}), Lh = /* @__PURE__ */ x({
  __name: "ListboxFilter",
  props: {
    modelValue: {},
    autoFocus: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "input" }
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "modelValue", t, {
      defaultValue: "",
      passive: e.modelValue === void 0
    }), s = an();
    s.focusable.value = !1;
    const { primitiveElement: r, currentElement: i } = Re();
    return le(() => {
      setTimeout(() => {
        var u;
        e.autoFocus && ((u = i.value) == null || u.focus());
      }, 1);
    }), (u, d) => (b(), S(o(O), {
      ref_key: "primitiveElement",
      ref: r,
      as: u.as,
      "as-child": u.asChild,
      value: o(l),
      disabled: o(s).disabled.value ? "" : void 0,
      "data-disabled": o(s).disabled.value ? "" : void 0,
      type: "text",
      onKeydown: [
        ie(ue(o(s).onKeydownNavigation, ["prevent"]), ["down", "up", "home", "end"]),
        ie(o(s).onKeydownEnter, ["enter"])
      ],
      onInput: d[0] || (d[0] = (c) => {
        l.value = c.target.value;
      })
    }, {
      default: y(() => [
        w(u.$slots, "default", { modelValue: o(l) })
      ]),
      _: 3
    }, 8, ["as", "as-child", "value", "disabled", "data-disabled", "onKeydown"]));
  }
}), Cc = "listbox.select", [wc, _c] = te("ListboxItem"), zh = /* @__PURE__ */ x({
  __name: "ListboxItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l, currentElement: s } = R(), r = ge(void 0, "radix-vue-listbox-item"), i = an(), u = B(() => s.value === i.highlightedElement.value), d = B(() => gc(i.modelValue.value, e.value, i.by)), c = B(() => i.disabled.value || e.disabled);
    async function f(p) {
      n("select", p), !(p != null && p.defaultPrevented) && !c.value && p && (i.onValueChange(e.value), i.onChangeHighlight(p.target));
    }
    function v(p) {
      const g = { originalEvent: p, value: e.value };
      jt(Cc, f, g);
    }
    return _c({
      isSelected: d
    }), (p, g) => (b(), S(o(Qt), { value: p.value }, {
      default: y(() => [
        q(o(O), {
          id: o(r),
          ref: o(l),
          role: "option",
          tabindex: o(i).focusable.value ? u.value ? "0" : "-1" : void 0,
          "aria-selected": d.value,
          as: p.as,
          "as-child": p.asChild,
          disabled: c.value ? "" : void 0,
          "data-disabled": c.value ? "" : void 0,
          "data-highlighted": u.value ? "" : void 0,
          "data-state": d.value ? "checked" : "unchecked",
          onClick: v,
          onKeydown: ie(ue(v, ["prevent"]), ["space"]),
          onPointermove: g[0] || (g[0] = (m) => {
            o(i).highlightOnHover.value ? o(i).onChangeHighlight(o(s)) : o(i).focusable.value || o(i).onChangeHighlight(o(s));
          })
        }, {
          default: y(() => [
            w(p.$slots, "default")
          ]),
          _: 3
        }, 8, ["id", "tabindex", "aria-selected", "as", "as-child", "disabled", "data-disabled", "data-highlighted", "data-state", "onKeydown"])
      ]),
      _: 3
    }, 8, ["value"]));
  }
}), Kh = /* @__PURE__ */ x({
  __name: "ListboxItemIndicator",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a;
    R();
    const e = wc();
    return (n, l) => o(e).isSelected.value ? (b(), S(o(O), k({
      key: 0,
      "aria-hidden": "true"
    }, t), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
});
function oa(a, t, e) {
  let n = e.initialDeps ?? [], l;
  return () => {
    var s, r, i, u;
    let d;
    e.key && ((s = e.debug) != null && s.call(e)) && (d = Date.now());
    const c = a();
    if (!(c.length !== n.length || c.some((p, g) => n[g] !== p)))
      return l;
    n = c;
    let v;
    if (e.key && ((r = e.debug) != null && r.call(e)) && (v = Date.now()), l = t(...c), e.key && ((i = e.debug) != null && i.call(e))) {
      const p = Math.round((Date.now() - d) * 100) / 100, g = Math.round((Date.now() - v) * 100) / 100, m = g / 16, _ = (C, $) => {
        for (C = String(C); C.length < $; )
          C = " " + C;
        return C;
      };
      console.info(
        `%c⏱ ${_(g, 5)} /${_(p, 5)} ms`,
        `
            font-size: .6rem;
            font-weight: bold;
            color: hsl(${Math.max(
          0,
          Math.min(120 - 120 * m, 120)
        )}deg 100% 31%);`,
        e == null ? void 0 : e.key
      );
    }
    return (u = e == null ? void 0 : e.onChange) == null || u.call(e, l), l;
  };
}
function En(a, t) {
  if (a === void 0)
    throw new Error("Unexpected undefined");
  return a;
}
const xc = (a, t) => Math.abs(a - t) < 1, Sc = (a, t, e) => {
  let n;
  return function(...l) {
    a.clearTimeout(n), n = a.setTimeout(() => t.apply(this, l), e);
  };
}, Ec = (a) => a, Pc = (a) => {
  const t = Math.max(a.startIndex - a.overscan, 0), e = Math.min(a.endIndex + a.overscan, a.count - 1), n = [];
  for (let l = t; l <= e; l++)
    n.push(l);
  return n;
}, Dc = (a, t) => {
  const e = a.scrollElement;
  if (!e)
    return;
  const n = a.targetWindow;
  if (!n)
    return;
  const l = (r) => {
    const { width: i, height: u } = r;
    t({ width: Math.round(i), height: Math.round(u) });
  };
  if (l(e.getBoundingClientRect()), !n.ResizeObserver)
    return () => {
    };
  const s = new n.ResizeObserver((r) => {
    const i = r[0];
    if (i != null && i.borderBoxSize) {
      const u = i.borderBoxSize[0];
      if (u) {
        l({ width: u.inlineSize, height: u.blockSize });
        return;
      }
    }
    l(e.getBoundingClientRect());
  });
  return s.observe(e, { box: "border-box" }), () => {
    s.unobserve(e);
  };
}, Jo = {
  passive: !0
}, $c = typeof window > "u" ? !0 : "onscrollend" in window, Bc = (a, t) => {
  const e = a.scrollElement;
  if (!e)
    return;
  const n = a.targetWindow;
  if (!n)
    return;
  let l = 0;
  const s = $c ? () => {
  } : Sc(
    n,
    () => {
      t(l, !1);
    },
    a.options.isScrollingResetDelay
  ), r = (d) => () => {
    l = e[a.options.horizontal ? "scrollLeft" : "scrollTop"], s(), t(l, d);
  }, i = r(!0), u = r(!1);
  return u(), e.addEventListener("scroll", i, Jo), e.addEventListener("scrollend", u, Jo), () => {
    e.removeEventListener("scroll", i), e.removeEventListener("scrollend", u);
  };
}, Ic = (a, t, e) => {
  if (t != null && t.borderBoxSize) {
    const n = t.borderBoxSize[0];
    if (n)
      return Math.round(
        n[e.options.horizontal ? "inlineSize" : "blockSize"]
      );
  }
  return Math.round(
    a.getBoundingClientRect()[e.options.horizontal ? "width" : "height"]
  );
}, Tc = (a, {
  adjustments: t = 0,
  behavior: e
}, n) => {
  var l, s;
  const r = a + t;
  (s = (l = n.scrollElement) == null ? void 0 : l.scrollTo) == null || s.call(l, {
    [n.options.horizontal ? "left" : "top"]: r,
    behavior: e
  });
};
class Rc {
  constructor(t) {
    this.unsubs = [], this.scrollElement = null, this.targetWindow = null, this.isScrolling = !1, this.scrollToIndexTimeoutId = null, this.measurementsCache = [], this.itemSizeCache = /* @__PURE__ */ new Map(), this.pendingMeasuredCacheIndexes = [], this.scrollRect = null, this.scrollOffset = null, this.scrollDirection = null, this.scrollAdjustments = 0, this.elementsCache = /* @__PURE__ */ new Map(), this.observer = /* @__PURE__ */ (() => {
      let e = null;
      const n = () => e || (!this.targetWindow || !this.targetWindow.ResizeObserver ? null : e = new this.targetWindow.ResizeObserver((l) => {
        l.forEach((s) => {
          this._measureElement(s.target, s);
        });
      }));
      return {
        disconnect: () => {
          var l;
          return (l = n()) == null ? void 0 : l.disconnect();
        },
        observe: (l) => {
          var s;
          return (s = n()) == null ? void 0 : s.observe(l, { box: "border-box" });
        },
        unobserve: (l) => {
          var s;
          return (s = n()) == null ? void 0 : s.unobserve(l);
        }
      };
    })(), this.range = null, this.setOptions = (e) => {
      Object.entries(e).forEach(([n, l]) => {
        typeof l > "u" && delete e[n];
      }), this.options = {
        debug: !1,
        initialOffset: 0,
        overscan: 1,
        paddingStart: 0,
        paddingEnd: 0,
        scrollPaddingStart: 0,
        scrollPaddingEnd: 0,
        horizontal: !1,
        getItemKey: Ec,
        rangeExtractor: Pc,
        onChange: () => {
        },
        measureElement: Ic,
        initialRect: { width: 0, height: 0 },
        scrollMargin: 0,
        gap: 0,
        indexAttribute: "data-index",
        initialMeasurementsCache: [],
        lanes: 1,
        isScrollingResetDelay: 150,
        enabled: !0,
        ...e
      };
    }, this.notify = (e, n) => {
      var l, s;
      const { startIndex: r, endIndex: i } = this.range ?? {
        startIndex: void 0,
        endIndex: void 0
      }, u = this.calculateRange();
      (e || r !== (u == null ? void 0 : u.startIndex) || i !== (u == null ? void 0 : u.endIndex)) && ((s = (l = this.options).onChange) == null || s.call(l, this, n));
    }, this.cleanup = () => {
      this.unsubs.filter(Boolean).forEach((e) => e()), this.unsubs = [], this.scrollElement = null, this.targetWindow = null, this.observer.disconnect(), this.elementsCache.clear();
    }, this._didMount = () => () => {
      this.cleanup();
    }, this._willUpdate = () => {
      var e;
      const n = this.options.enabled ? this.options.getScrollElement() : null;
      if (this.scrollElement !== n) {
        if (this.cleanup(), !n) {
          this.notify(!1, !1);
          return;
        }
        this.scrollElement = n, this.scrollElement && "ownerDocument" in this.scrollElement ? this.targetWindow = this.scrollElement.ownerDocument.defaultView : this.targetWindow = ((e = this.scrollElement) == null ? void 0 : e.window) ?? null, this._scrollToOffset(this.getScrollOffset(), {
          adjustments: void 0,
          behavior: void 0
        }), this.unsubs.push(
          this.options.observeElementRect(this, (l) => {
            this.scrollRect = l, this.notify(!1, !1);
          })
        ), this.unsubs.push(
          this.options.observeElementOffset(this, (l, s) => {
            this.scrollAdjustments = 0, this.scrollDirection = s ? this.getScrollOffset() < l ? "forward" : "backward" : null, this.scrollOffset = l;
            const r = this.isScrolling;
            this.isScrolling = s, this.notify(r !== s, s);
          })
        );
      }
    }, this.getSize = () => this.options.enabled ? (this.scrollRect = this.scrollRect ?? this.options.initialRect, this.scrollRect[this.options.horizontal ? "width" : "height"]) : (this.scrollRect = null, 0), this.getScrollOffset = () => this.options.enabled ? (this.scrollOffset = this.scrollOffset ?? (typeof this.options.initialOffset == "function" ? this.options.initialOffset() : this.options.initialOffset), this.scrollOffset) : (this.scrollOffset = null, 0), this.getFurthestMeasurement = (e, n) => {
      const l = /* @__PURE__ */ new Map(), s = /* @__PURE__ */ new Map();
      for (let r = n - 1; r >= 0; r--) {
        const i = e[r];
        if (l.has(i.lane))
          continue;
        const u = s.get(
          i.lane
        );
        if (u == null || i.end > u.end ? s.set(i.lane, i) : i.end < u.end && l.set(i.lane, !0), l.size === this.options.lanes)
          break;
      }
      return s.size === this.options.lanes ? Array.from(s.values()).sort((r, i) => r.end === i.end ? r.index - i.index : r.end - i.end)[0] : void 0;
    }, this.getMeasurementOptions = oa(
      () => [
        this.options.count,
        this.options.paddingStart,
        this.options.scrollMargin,
        this.options.getItemKey,
        this.options.enabled
      ],
      (e, n, l, s, r) => (this.pendingMeasuredCacheIndexes = [], {
        count: e,
        paddingStart: n,
        scrollMargin: l,
        getItemKey: s,
        enabled: r
      }),
      {
        key: !1
      }
    ), this.getMeasurements = oa(
      () => [this.getMeasurementOptions(), this.itemSizeCache],
      ({ count: e, paddingStart: n, scrollMargin: l, getItemKey: s, enabled: r }, i) => {
        var u;
        if (!r)
          return this.measurementsCache = [], this.itemSizeCache.clear(), [];
        this.measurementsCache.length === 0 && (this.measurementsCache = this.options.initialMeasurementsCache, this.measurementsCache.forEach((f) => {
          this.itemSizeCache.set(f.key, f.size);
        }));
        const d = this.pendingMeasuredCacheIndexes.length > 0 ? Math.min(...this.pendingMeasuredCacheIndexes) : 0;
        this.pendingMeasuredCacheIndexes = [];
        const c = this.measurementsCache.slice(0, d);
        for (let f = d; f < e; f++) {
          let v = (u = this.measurementsCache[f]) == null ? void 0 : u.measureElement;
          v || (v = (E) => {
            const P = s(f), D = this.elementsCache.get(P);
            if (!E) {
              D && (this.observer.unobserve(D), this.elementsCache.delete(P));
              return;
            }
            D !== E && (D && this.observer.unobserve(D), this.observer.observe(E), this.elementsCache.set(P, E)), E.isConnected && this.resizeItem(
              f,
              this.options.measureElement(E, void 0, this)
            );
          });
          const p = s(f), g = this.options.lanes === 1 ? c[f - 1] : this.getFurthestMeasurement(c, f), m = g ? g.end + this.options.gap : n + l, _ = i.get(p), C = typeof _ == "number" ? _ : this.options.estimateSize(f), $ = m + C, h = g ? g.lane : f % this.options.lanes;
          c[f] = {
            index: f,
            start: m,
            size: C,
            end: $,
            key: p,
            lane: h,
            measureElement: v
          };
        }
        return this.measurementsCache = c, c;
      },
      {
        key: process.env.NODE_ENV !== "production" && "getMeasurements",
        debug: () => this.options.debug
      }
    ), this.calculateRange = oa(
      () => [this.getMeasurements(), this.getSize(), this.getScrollOffset()],
      (e, n, l) => this.range = e.length > 0 && n > 0 ? Ac({
        measurements: e,
        outerSize: n,
        scrollOffset: l
      }) : null,
      {
        key: process.env.NODE_ENV !== "production" && "calculateRange",
        debug: () => this.options.debug
      }
    ), this.getIndexes = oa(
      () => [
        this.options.rangeExtractor,
        this.calculateRange(),
        this.options.overscan,
        this.options.count
      ],
      (e, n, l, s) => n === null ? [] : e({
        startIndex: n.startIndex,
        endIndex: n.endIndex,
        overscan: l,
        count: s
      }),
      {
        key: process.env.NODE_ENV !== "production" && "getIndexes",
        debug: () => this.options.debug
      }
    ), this.indexFromElement = (e) => {
      const n = this.options.indexAttribute, l = e.getAttribute(n);
      return l ? parseInt(l, 10) : (console.warn(
        `Missing attribute name '${n}={index}' on measured element.`
      ), -1);
    }, this._measureElement = (e, n) => {
      const l = this.indexFromElement(e), s = this.getMeasurements()[l];
      if (!s || !e.isConnected) {
        this.elementsCache.forEach((i, u) => {
          i === e && (this.observer.unobserve(e), this.elementsCache.delete(u));
        });
        return;
      }
      const r = this.elementsCache.get(s.key);
      r !== e && (r && this.observer.unobserve(r), this.observer.observe(e), this.elementsCache.set(s.key, e)), this.resizeItem(l, this.options.measureElement(e, n, this));
    }, this.resizeItem = (e, n) => {
      const l = this.getMeasurements()[e];
      if (!l)
        return;
      const s = this.itemSizeCache.get(l.key) ?? l.size, r = n - s;
      r !== 0 && ((this.shouldAdjustScrollPositionOnItemSizeChange !== void 0 ? this.shouldAdjustScrollPositionOnItemSizeChange(l, r, this) : l.start < this.getScrollOffset() + this.scrollAdjustments) && (process.env.NODE_ENV !== "production" && this.options.debug && console.info("correction", r), this._scrollToOffset(this.getScrollOffset(), {
        adjustments: this.scrollAdjustments += r,
        behavior: void 0
      })), this.pendingMeasuredCacheIndexes.push(l.index), this.itemSizeCache = new Map(this.itemSizeCache.set(l.key, n)), this.notify(!0, !1));
    }, this.measureElement = (e) => {
      e && this._measureElement(e, void 0);
    }, this.getVirtualItems = oa(
      () => [this.getIndexes(), this.getMeasurements()],
      (e, n) => {
        const l = [];
        for (let s = 0, r = e.length; s < r; s++) {
          const i = e[s], u = n[i];
          l.push(u);
        }
        return l;
      },
      {
        key: process.env.NODE_ENV !== "production" && "getIndexes",
        debug: () => this.options.debug
      }
    ), this.getVirtualItemForOffset = (e) => {
      const n = this.getMeasurements();
      if (n.length !== 0)
        return En(
          n[ps(
            0,
            n.length - 1,
            (l) => En(n[l]).start,
            e
          )]
        );
    }, this.getOffsetForAlignment = (e, n) => {
      const l = this.getSize(), s = this.getScrollOffset();
      n === "auto" && (e <= s ? n = "start" : e >= s + l ? n = "end" : n = "start"), n === "start" ? e = e : n === "end" ? e = e - l : n === "center" && (e = e - l / 2);
      const r = this.options.horizontal ? "scrollWidth" : "scrollHeight", u = (this.scrollElement ? "document" in this.scrollElement ? this.scrollElement.document.documentElement[r] : this.scrollElement[r] : 0) - l;
      return Math.max(Math.min(u, e), 0);
    }, this.getOffsetForIndex = (e, n = "auto") => {
      e = Math.max(0, Math.min(e, this.options.count - 1));
      const l = this.getMeasurements()[e];
      if (!l)
        return;
      const s = this.getSize(), r = this.getScrollOffset();
      if (n === "auto")
        if (l.end >= r + s - this.options.scrollPaddingEnd)
          n = "end";
        else if (l.start <= r + this.options.scrollPaddingStart)
          n = "start";
        else
          return [r, n];
      const i = n === "end" ? l.end + this.options.scrollPaddingEnd : l.start - this.options.scrollPaddingStart;
      return [this.getOffsetForAlignment(i, n), n];
    }, this.isDynamicMode = () => this.elementsCache.size > 0, this.cancelScrollToIndex = () => {
      this.scrollToIndexTimeoutId !== null && this.targetWindow && (this.targetWindow.clearTimeout(this.scrollToIndexTimeoutId), this.scrollToIndexTimeoutId = null);
    }, this.scrollToOffset = (e, { align: n = "start", behavior: l } = {}) => {
      this.cancelScrollToIndex(), l === "smooth" && this.isDynamicMode() && console.warn(
        "The `smooth` scroll behavior is not fully supported with dynamic size."
      ), this._scrollToOffset(this.getOffsetForAlignment(e, n), {
        adjustments: void 0,
        behavior: l
      });
    }, this.scrollToIndex = (e, { align: n = "auto", behavior: l } = {}) => {
      e = Math.max(0, Math.min(e, this.options.count - 1)), this.cancelScrollToIndex(), l === "smooth" && this.isDynamicMode() && console.warn(
        "The `smooth` scroll behavior is not fully supported with dynamic size."
      );
      const s = this.getOffsetForIndex(e, n);
      if (!s) return;
      const [r, i] = s;
      this._scrollToOffset(r, { adjustments: void 0, behavior: l }), l !== "smooth" && this.isDynamicMode() && this.targetWindow && (this.scrollToIndexTimeoutId = this.targetWindow.setTimeout(() => {
        if (this.scrollToIndexTimeoutId = null, this.elementsCache.has(
          this.options.getItemKey(e)
        )) {
          const [d] = En(
            this.getOffsetForIndex(e, i)
          );
          xc(d, this.getScrollOffset()) || this.scrollToIndex(e, { align: i, behavior: l });
        } else
          this.scrollToIndex(e, { align: i, behavior: l });
      }));
    }, this.scrollBy = (e, { behavior: n } = {}) => {
      this.cancelScrollToIndex(), n === "smooth" && this.isDynamicMode() && console.warn(
        "The `smooth` scroll behavior is not fully supported with dynamic size."
      ), this._scrollToOffset(this.getScrollOffset() + e, {
        adjustments: void 0,
        behavior: n
      });
    }, this.getTotalSize = () => {
      var e;
      const n = this.getMeasurements();
      let l;
      return n.length === 0 ? l = this.options.paddingStart : l = this.options.lanes === 1 ? ((e = n[n.length - 1]) == null ? void 0 : e.end) ?? 0 : Math.max(
        ...n.slice(-this.options.lanes).map((s) => s.end)
      ), l - this.options.scrollMargin + this.options.paddingEnd;
    }, this._scrollToOffset = (e, {
      adjustments: n,
      behavior: l
    }) => {
      this.options.scrollToFn(e, { behavior: l, adjustments: n }, this);
    }, this.measure = () => {
      var e, n;
      this.itemSizeCache = /* @__PURE__ */ new Map(), (n = (e = this.options).onChange) == null || n.call(e, this, !1);
    }, this.setOptions(t);
  }
}
const ps = (a, t, e, n) => {
  for (; a <= t; ) {
    const l = (a + t) / 2 | 0, s = e(l);
    if (s < n)
      a = l + 1;
    else if (s > n)
      t = l - 1;
    else
      return l;
  }
  return a > 0 ? a - 1 : 0;
};
function Ac({
  measurements: a,
  outerSize: t,
  scrollOffset: e
}) {
  const n = a.length - 1, s = ps(0, n, (i) => a[i].start, e);
  let r = s;
  for (; r < n && a[r].end < e + t; )
    r++;
  return { startIndex: s, endIndex: r };
}
function Oc(a) {
  const t = new Rc(o(a)), e = Fn(t), n = t._didMount();
  return ee(
    () => o(a).getScrollElement(),
    (l) => {
      l && t._willUpdate();
    },
    {
      immediate: !0
    }
  ), ee(
    () => o(a),
    (l) => {
      t.setOptions({
        ...l,
        onChange: (s, r) => {
          var i;
          Lo(e), (i = l.onChange) == null || i.call(l, s, r);
        }
      }), t._willUpdate(), Lo(e);
    },
    {
      immediate: !0
    }
  ), fl(n), e;
}
function vs(a) {
  return Oc(
    B(() => ({
      observeElementRect: Dc,
      observeElementOffset: Bc,
      scrollToFn: Tc,
      ...o(a)
    }))
  );
}
const Hh = /* @__PURE__ */ x({
  __name: "ListboxVirtualizer",
  props: {
    options: {},
    estimateSize: {},
    textContent: { type: Function }
  },
  setup(a) {
    const t = a, e = Ua(), n = an(), l = kl(), { getItems: s } = ea();
    n.isVirtual.value = !0;
    const r = B(() => {
      const v = l.value;
      if (v) {
        const p = window.getComputedStyle(v);
        return {
          start: Number.parseFloat(p.paddingBlockStart || p.paddingTop),
          end: Number.parseFloat(p.paddingBlockEnd || p.paddingBottom)
        };
      } else
        return { start: 0, end: 0 };
    }), i = vs(
      {
        get scrollPaddingStart() {
          return r.value.start;
        },
        get scrollPaddingEnd() {
          return r.value.end;
        },
        get count() {
          return t.options.length;
        },
        get horizontal() {
          return n.orientation.value === "horizontal";
        },
        estimateSize() {
          return t.estimateSize ?? 28;
        },
        getScrollElement() {
          return l.value;
        },
        overscan: 12
      }
    ), u = B(() => i.value.getVirtualItems().map((v) => ({
      item: v,
      is: Ln(e.default({
        option: t.options[v.index],
        virtualizer: i.value,
        virtualItem: v
      })[0], {
        key: `${v.key}`,
        "data-index": v.index,
        "aria-setsize": t.options.length,
        "aria-posinset": v.index + 1,
        style: {
          position: "absolute",
          top: 0,
          left: 0,
          transform: `translateY(${v.start}px)`,
          overflowAnchor: "none"
        }
      })
    })));
    n.virtualFocusHook.on((v) => {
      const p = t.options.findIndex((g) => Array.isArray(n.modelValue.value) ? Gt(g, n.modelValue.value[0], n.by) : Gt(g, n.modelValue.value, n.by));
      p !== -1 && (v == null || v.preventDefault(), i.value.scrollToIndex(p, { align: "start" }), requestAnimationFrame(() => {
        const g = yc(l.value);
        g && v && (g == null || g.focus());
      }));
    });
    const d = Tt("", 1e3), c = B(() => {
      const v = (p) => t.textContent ? t.textContent(p) : p.toString().toLowerCase();
      return t.options.map((p, g) => ({
        index: g,
        textContent: v(p)
      }));
    });
    function f(v, p) {
      var C, $, h, E;
      if (!((C = n.firstValue) != null && C.value) || !n.multiple.value || !Array.isArray(n.modelValue.value))
        return;
      const m = ($ = s().filter((P) => P.ref.dataset.disabled !== "").find((P) => P.ref === n.highlightedElement.value)) == null ? void 0 : $.value;
      if (!m)
        return;
      let _ = null;
      switch (p) {
        case "prev":
        case "next": {
          _ = Bt(t.options, n.firstValue.value, m);
          break;
        }
        case "first": {
          _ = Bt(t.options, n.firstValue.value, (h = t.options) == null ? void 0 : h[0]);
          break;
        }
        case "last": {
          _ = Bt(t.options, n.firstValue.value, (E = t.options) == null ? void 0 : E[t.options.length - 1]);
          break;
        }
      }
      n.modelValue.value = _;
    }
    return n.virtualKeydownHook.on((v) => {
      var _;
      const p = v.altKey || v.ctrlKey || v.metaKey;
      if (v.key === "Tab" && !p)
        return;
      let m = en[v.key];
      if (p && v.key === "a" && n.multiple.value ? (v.preventDefault(), n.modelValue.value = [...t.options], m = "last") : v.shiftKey && m && f(v, m), ["first", "last"].includes(m)) {
        v.preventDefault();
        const C = m === "first" ? 0 : t.options.length - 1;
        i.value.scrollToIndex(C), requestAnimationFrame(() => {
          const $ = s(), h = m === "first" ? $[0] : $[$.length - 1];
          n.onChangeHighlight(h.ref);
        });
      } else if (!m && !p) {
        d.value += v.key;
        const C = Number((_ = me()) == null ? void 0 : _.getAttribute("data-index")), $ = c.value[C].textContent, h = c.value.map((D) => D.textContent), E = Zn(h, d.value, $), P = c.value.find((D) => D.textContent === E);
        P && (i.value.scrollToIndex(P.index, { align: "start" }), requestAnimationFrame(() => {
          const D = l.value.querySelector(`[data-index="${P.index}"]`);
          D instanceof HTMLElement && n.onChangeHighlight(D);
        }));
      }
    }), (v, p) => (b(), ve("div", {
      "data-radix-vue-virtualizer": "",
      style: Me({
        position: "relative",
        width: "100%",
        height: `${o(i).getTotalSize()}px`
      })
    }, [
      (b(!0), ve(_e, null, ma(u.value, ({ is: g, item: m }) => (b(), S(Xe(g), {
        key: m.index
      }))), 128))
    ], 4));
  }
}), [kc, Mc] = te("ListboxGroup"), Wh = /* @__PURE__ */ x({
  __name: "ListboxGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = ge(void 0, "radix-vue-listbox-group");
    return Mc({ id: e }), (n, l) => (b(), S(o(O), k({ role: "group" }, t, { "aria-labelledby": o(e) }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-labelledby"]));
  }
}), jh = /* @__PURE__ */ x({
  __name: "ListboxGroupLabel",
  props: {
    for: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = kc({ id: "" });
    return (n, l) => (b(), S(o(O), k(t, {
      id: o(e).id
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), [nn, Vc] = te("MenubarRoot"), Uh = /* @__PURE__ */ x({
  __name: "MenubarRoot",
  props: {
    modelValue: {},
    defaultValue: {},
    dir: {},
    loop: { type: Boolean, default: !1 }
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l, currentElement: s } = R(), { createCollection: r } = Fe("menubar");
    r(s);
    const i = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue ?? "",
      passive: e.modelValue === void 0
    }), u = T(null), { dir: d, loop: c } = ae(e), f = we(d);
    return Vc({
      modelValue: i,
      dir: f,
      loop: c,
      onMenuOpen: (v) => {
        i.value = v, u.value = v;
      },
      onMenuClose: () => {
        i.value = "";
      },
      onMenuToggle: (v) => {
        i.value = i.value ? "" : v, u.value = v;
      }
    }), (v, p) => (b(), S(o(Ft), {
      "current-tab-stop-id": u.value,
      "onUpdate:currentTabStopId": p[0] || (p[0] = (g) => u.value = g),
      orientation: "horizontal",
      loop: o(c),
      dir: o(f),
      "as-child": ""
    }, {
      default: y(() => [
        q(o(O), {
          ref: o(l),
          role: "menubar"
        }, {
          default: y(() => [
            w(v.$slots, "default", { modelValue: o(i) })
          ]),
          _: 3
        }, 512)
      ]),
      _: 3
    }, 8, ["current-tab-stop-id", "loop", "dir"]));
  }
}), [So, Fc] = te("MenubarMenu"), Gh = /* @__PURE__ */ x({
  __name: "MenubarMenu",
  props: {
    value: {}
  },
  setup(a) {
    const e = ge(a.value), n = nn();
    R();
    const l = T(), s = T(!1), r = B(() => n.modelValue.value === e);
    return ee(r, () => {
      r.value || (s.value = !1);
    }), Fc({
      value: e,
      triggerElement: l,
      triggerId: e,
      contentId: "",
      wasKeyboardTriggerOpenRef: s
    }), (i, u) => (b(), S(o(so), {
      open: r.value,
      modal: !1,
      dir: o(n).dir.value,
      "onUpdate:open": u[0] || (u[0] = (d) => {
        d || o(n).onMenuClose();
      })
    }, {
      default: y(() => [
        w(i.$slots, "default")
      ]),
      _: 3
    }, 8, ["open", "dir"]));
  }
}), qh = /* @__PURE__ */ x({
  __name: "MenubarTrigger",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = nn(), e = So(), { forwardRef: n, currentElement: l } = R(), s = T(!1), r = B(() => t.modelValue.value === e.value);
    return le(() => {
      e.triggerElement = l;
    }), (i, u) => (b(), S(o(Nt), {
      "as-child": "",
      focusable: !i.disabled,
      "tab-stop-id": o(e).value
    }, {
      default: y(() => [
        q(o(Qa), { "as-child": "" }, {
          default: y(() => [
            q(o(O), {
              id: o(e).triggerId,
              ref: o(n),
              as: i.as,
              type: i.as === "button" ? "button" : void 0,
              role: "menuitem",
              "aria-haspopup": "menu",
              "aria-expanded": r.value,
              "aria-controls": r.value ? o(e).contentId : void 0,
              "data-highlighted": s.value ? "" : void 0,
              "data-state": r.value ? "open" : "closed",
              "data-disabled": i.disabled ? "" : void 0,
              disabled: i.disabled,
              "data-value": o(e).value,
              "data-radix-vue-collection-item": "",
              onPointerdown: u[0] || (u[0] = (d) => {
                !i.disabled && d.button === 0 && d.ctrlKey === !1 && (o(t).onMenuOpen(o(e).value), r.value || d.preventDefault());
              }),
              onPointerenter: u[1] || (u[1] = () => {
                var c;
                !!o(t).modelValue.value && !r.value && (o(t).onMenuOpen(o(e).value), (c = o(l)) == null || c.focus());
              }),
              onKeydown: u[2] || (u[2] = ie((d) => {
                i.disabled || (["Enter", " "].includes(d.key) && o(t).onMenuToggle(o(e).value), d.key === "ArrowDown" && o(t).onMenuOpen(o(e).value), ["Enter", " ", "ArrowDown"].includes(d.key) && (o(e).wasKeyboardTriggerOpenRef.value = !0, d.preventDefault()));
              }, ["enter", "space", "arrow-down"])),
              onFocus: u[3] || (u[3] = (d) => s.value = !0),
              onBlur: u[4] || (u[4] = (d) => s.value = !1)
            }, {
              default: y(() => [
                w(i.$slots, "default")
              ]),
              _: 3
            }, 8, ["id", "as", "type", "aria-expanded", "aria-controls", "data-highlighted", "data-state", "data-disabled", "disabled", "data-value"])
          ]),
          _: 3
        })
      ]),
      _: 3
    }, 8, ["focusable", "tab-stop-id"]));
  }
}), Yh = /* @__PURE__ */ x({
  __name: "MenubarPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(vo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Xh = /* @__PURE__ */ x({
  __name: "MenubarContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    side: {},
    sideOffset: {},
    align: { default: "start" },
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    R();
    const s = nn(), r = So();
    r.contentId || (r.contentId = ge(void 0, "radix-vue-menubar-content"));
    const { injectCollection: i } = Fe("menubar"), u = i(), d = T(!1);
    function c(f) {
      const p = f.target.hasAttribute(
        "data-radix-menubar-subtrigger"
      ), m = (s.dir.value === "rtl" ? "ArrowRight" : "ArrowLeft") === f.key;
      if (!m && p)
        return;
      let C = u.value.map((E) => E.dataset.value);
      m && C.reverse();
      const $ = C.indexOf(r.value);
      C = s.loop.value ? Xn(C, $ + 1) : C.slice($ + 1);
      const [h] = C;
      h && s.onMenuOpen(h);
    }
    return (f, v) => (b(), S(o(fo), k(o(l), {
      id: o(r).contentId,
      "data-radix-menubar-content": "",
      "aria-labelledby": o(r).triggerId,
      style: {
        "--radix-menubar-content-transform-origin": "var(--radix-popper-transform-origin)",
        "--radix-menubar-content-available-width": "var(--radix-popper-available-width)",
        "--radix-menubar-content-available-height": "var(--radix-popper-available-height)",
        "--radix-menubar-trigger-width": "var(--radix-popper-anchor-width)",
        "--radix-menubar-trigger-height": "var(--radix-popper-anchor-height)"
      },
      onCloseAutoFocus: v[0] || (v[0] = (p) => {
        var m;
        !!!o(s).modelValue.value && !d.value && ((m = o(r).triggerElement.value) == null || m.focus()), d.value = !1, p.preventDefault();
      }),
      onFocusOutside: v[1] || (v[1] = (p) => {
        const g = p.target;
        o(u).some((_) => _.contains(g)) && p.preventDefault();
      }),
      onInteractOutside: v[2] || (v[2] = (p) => {
        d.value = !0;
      }),
      onEntryFocus: v[3] || (v[3] = (p) => {
        o(r).wasKeyboardTriggerOpenRef.value || p.preventDefault();
      }),
      onKeydown: ie(c, ["arrow-right", "arrow-left"])
    }), {
      default: y(() => [
        w(f.$slots, "default")
      ]),
      _: 3
    }, 16, ["id", "aria-labelledby"]));
  }
}), Zh = /* @__PURE__ */ x({
  __name: "MenubarArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(lo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Jh = /* @__PURE__ */ x({
  __name: "MenubarItem",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(xa), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Qh = /* @__PURE__ */ x({
  __name: "MenubarGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(tn), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ey = /* @__PURE__ */ x({
  __name: "MenubarSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(yo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ty = /* @__PURE__ */ x({
  __name: "MenubarCheckboxItem",
  props: {
    checked: { type: [Boolean, String] },
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select", "update:checked"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(co), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ay = /* @__PURE__ */ x({
  __name: "MenubarItemIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(uo), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ny = /* @__PURE__ */ x({
  __name: "MenubarLabel",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(po), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), oy = /* @__PURE__ */ x({
  __name: "MenubarRadioGroup",
  props: {
    modelValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = Te(t);
    return R(), (s, r) => (b(), S(o(mo), W(U({ ...e, ...o(l) })), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ly = /* @__PURE__ */ x({
  __name: "MenubarRadioItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    return R(), (s, r) => (b(), S(o(ho), W(U(o(l))), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), sy = /* @__PURE__ */ x({
  __name: "MenubarSub",
  props: {
    defaultOpen: { type: Boolean },
    open: { type: Boolean, default: void 0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    const l = ne(e, "open", n, {
      defaultValue: e.defaultOpen ?? !1,
      passive: e.open === void 0
    });
    return (s, r) => (b(), S(o(go), {
      open: o(l),
      "onUpdate:open": r[0] || (r[0] = (i) => et(l) ? l.value = i : null)
    }, {
      default: y(() => [
        w(s.$slots, "default", { open: o(l) })
      ]),
      _: 3
    }, 8, ["open"]));
  }
}), ry = /* @__PURE__ */ x({
  __name: "MenubarSubContent",
  props: {
    forceMount: { type: Boolean },
    loop: { type: Boolean },
    sideOffset: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "entryFocus", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const l = Se(a, t);
    R();
    const { injectCollection: s } = Fe("menubar"), r = nn(), i = So(), u = s();
    function d(c) {
      if (c.target.hasAttribute(
        "data-radix-menubar-subtrigger"
      ))
        return;
      let p = u.value.map((_) => _.dataset.value);
      const g = p.indexOf(i.value);
      p = r.loop.value ? Xn(p, g + 1) : p.slice(g + 1);
      const [m] = p;
      m && r.onMenuOpen(m);
    }
    return (c, f) => (b(), S(o(bo), k(o(l), {
      "data-radix-menubar-content": "",
      style: {
        "--radix-menubar-content-transform-origin": "var(--radix-popper-transform-origin)",
        "--radix-menubar-content-available-width": "var(--radix-popper-available-width)",
        "--radix-menubar-content-available-height": "var(--radix-popper-available-height)",
        "--radix-menubar-trigger-width": "var(--radix-popper-anchor-width)",
        "--radix-menubar-trigger-height": "var(--radix-popper-anchor-height)"
      },
      onKeydown: ie(d, ["arrow-right"])
    }), {
      default: y(() => [
        w(c.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), iy = /* @__PURE__ */ x({
  __name: "MenubarSubTrigger",
  props: {
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Co), k(t, { "data-radix-menubar-subtrigger": "" }), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [_t, ms] = te(["NavigationMenuRoot", "NavigationMenuSub"], "NavigationMenuContext"), uy = /* @__PURE__ */ x({
  __name: "NavigationMenuRoot",
  props: {
    modelValue: { default: void 0 },
    defaultValue: {},
    dir: {},
    orientation: { default: "horizontal" },
    delayDuration: { default: 200 },
    skipDelayDuration: { default: 300 },
    disableClickTrigger: { type: Boolean, default: !1 },
    disableHoverTrigger: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: { default: "nav" }
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "modelValue", t, {
      defaultValue: e.defaultValue ?? "",
      passive: e.modelValue === void 0
    }), s = T(""), { forwardRef: r, currentElement: i } = R(), u = T(), d = T(), { createCollection: c } = Fe("nav");
    c(u);
    const { delayDuration: f, skipDelayDuration: v, dir: p, disableClickTrigger: g, disableHoverTrigger: m } = ae(e), _ = we(p), C = Tt(!1, v), $ = B(() => l.value !== "" || C.value ? 150 : f.value), h = jn((E) => {
      typeof E == "string" && (s.value = l.value, l.value = E);
    }, $);
    return ms({
      isRootMenu: !0,
      modelValue: l,
      previousValue: s,
      baseId: ge(void 0, "radix-navigation-menu"),
      disableClickTrigger: g,
      disableHoverTrigger: m,
      dir: _,
      orientation: e.orientation,
      rootNavigationMenu: i,
      indicatorTrack: u,
      onIndicatorTrackChange: (E) => {
        u.value = E;
      },
      viewport: d,
      onViewportChange: (E) => {
        d.value = E;
      },
      onTriggerEnter: (E) => {
        h(E);
      },
      onTriggerLeave: () => {
        C.value = !0, h("");
      },
      onContentEnter: () => {
        h();
      },
      onContentLeave: () => {
        h("");
      },
      onItemSelect: (E) => {
        s.value = l.value, l.value = E;
      },
      onItemDismiss: () => {
        s.value = l.value, l.value = "";
      }
    }), (E, P) => (b(), S(o(O), {
      ref: o(r),
      "aria-label": "Main",
      as: E.as,
      "as-child": E.asChild,
      "data-orientation": E.orientation,
      dir: o(_),
      "data-radix-navigation-menu": ""
    }, {
      default: y(() => [
        w(E.$slots, "default", { modelValue: o(l) })
      ]),
      _: 3
    }, 8, ["as", "as-child", "data-orientation", "dir"]));
  }
});
function on(a) {
  return a ? "open" : "closed";
}
function hs(a, t) {
  return `${a}-trigger-${t}`;
}
function Eo(a, t) {
  return `${a}-content-${t}`;
}
const Nc = "navigationMenu.linkSelect", Va = "navigationMenu.rootContentDismiss";
function On(a) {
  const t = [], e = document.createTreeWalker(a, NodeFilter.SHOW_ELEMENT, {
    acceptNode: (n) => {
      const l = n.tagName === "INPUT" && n.type === "hidden";
      return n.disabled || n.hidden || l ? NodeFilter.FILTER_SKIP : n.tabIndex >= 0 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
    }
  });
  for (; e.nextNode(); ) t.push(e.currentNode);
  return t;
}
function ys(a) {
  const t = me();
  return a.some((e) => e === t ? !0 : (e.focus(), me() !== t));
}
function Lc(a) {
  return a.forEach((t) => {
    t.dataset.tabindex = t.getAttribute("tabindex") || "", t.setAttribute("tabindex", "-1");
  }), () => {
    a.forEach((t) => {
      const e = t.dataset.tabindex;
      t.setAttribute("tabindex", e);
    });
  };
}
function gs(a) {
  return (t) => t.pointerType === "mouse" ? a(t) : void 0;
}
const [Po, zc] = te("NavigationMenuItem"), dy = /* @__PURE__ */ x({
  __name: "NavigationMenuItem",
  props: {
    value: {},
    asChild: { type: Boolean },
    as: { default: "li" }
  },
  setup(a) {
    const t = a;
    R();
    const { injectCollection: e } = Fe("nav"), n = e(), l = _t(), s = ge(t.value), r = T(), i = T(), u = Eo(l.baseId, s);
    let d = () => ({});
    const c = T(!1);
    async function f(m = "start") {
      const _ = document.getElementById(u);
      if (_) {
        d();
        const C = On(_);
        C.length && ys(m === "start" ? C : C.reverse());
      }
    }
    function v() {
      const m = document.getElementById(u);
      if (m) {
        const _ = On(m);
        _.length && (d = Lc(_));
      }
    }
    zc({
      value: s,
      contentId: u,
      triggerRef: r,
      focusProxyRef: i,
      wasEscapeCloseRef: c,
      onEntryKeyDown: f,
      onFocusProxyEnter: f,
      onContentFocusOutside: v,
      onRootContentClose: v
    });
    function p() {
      var m;
      l.onItemDismiss(), (m = r.value) == null || m.focus();
    }
    function g(m) {
      const _ = me();
      if (m.keyCode === 32 || m.key === "Enter")
        if (l.modelValue.value === s) {
          p(), m.preventDefault();
          return;
        } else {
          m.target.click(), m.preventDefault();
          return;
        }
      const C = n.value.filter(
        (h) => {
          var E;
          return (E = h.parentElement) == null ? void 0 : E.hasAttribute("data-menu-item");
        }
      );
      if (!C.includes(_))
        return;
      const $ = At(m, _, void 0, {
        itemsArray: C,
        loop: !1
      });
      $ && ($ == null || $.focus()), m.preventDefault(), m.stopPropagation();
    }
    return (m, _) => (b(), S(o(O), {
      "as-child": m.asChild,
      as: m.as,
      "data-menu-item": "",
      onKeydown: ie(g, ["up", "down", "left", "right", "home", "end", "space"])
    }, {
      default: y(() => [
        w(m.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as"]));
  }
}), Kc = /* @__PURE__ */ x({
  __name: "NavigationMenuContentImpl",
  props: {
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, { injectCollection: l } = Fe("nav"), s = l(), { forwardRef: r, currentElement: i } = R(), u = _t(), d = Po(), c = hs(u.baseId, d.value), f = Eo(u.baseId, d.value), v = T(null), p = B(() => {
      const E = s.value.map((A) => A.id.split("trigger-")[1]);
      u.dir.value === "rtl" && E.reverse();
      const P = E.indexOf(u.modelValue.value), D = E.indexOf(u.previousValue.value), I = d.value === u.modelValue.value, M = D === E.indexOf(d.value);
      if (!I && !M)
        return v.value;
      const V = (() => {
        if (P !== D) {
          if (I && D !== -1)
            return P > D ? "from-end" : "from-start";
          if (M && P !== -1)
            return P > D ? "to-start" : "to-end";
        }
        return null;
      })();
      return v.value = V, V;
    });
    function g(h) {
      var E, P;
      if (n("focusOutside", h), n("interactOutside", h), !h.defaultPrevented) {
        d.onContentFocusOutside();
        const D = h.target;
        (P = (E = u.rootNavigationMenu) == null ? void 0 : E.value) != null && P.contains(D) && h.preventDefault();
      }
    }
    function m(h) {
      var E;
      if (n("pointerDownOutside", h), !h.defaultPrevented) {
        const P = h.target, D = s.value.some(
          (M) => M.contains(P)
        ), I = u.isRootMenu && ((E = u.viewport.value) == null ? void 0 : E.contains(P));
        (D || I || !u.isRootMenu) && h.preventDefault();
      }
    }
    Ce((h) => {
      const E = i.value;
      if (u.isRootMenu && E) {
        const P = () => {
          var D;
          u.onItemDismiss(), d.onRootContentClose(), E.contains(me()) && ((D = d.triggerRef.value) == null || D.focus());
        };
        E.addEventListener(Va, P), h(
          () => E.removeEventListener(Va, P)
        );
      }
    });
    function _(h) {
      var E, P;
      n("escapeKeyDown", h), h.defaultPrevented || (u.onItemDismiss(), (P = (E = d.triggerRef) == null ? void 0 : E.value) == null || P.focus(), d.wasEscapeCloseRef.value = !0);
    }
    function C(h) {
      var M;
      if (h.target.closest("[data-radix-navigation-menu]") !== u.rootNavigationMenu.value)
        return;
      const E = h.altKey || h.ctrlKey || h.metaKey, P = h.key === "Tab" && !E, D = On(h.currentTarget);
      if (P) {
        const V = me(), A = D.findIndex(
          (H) => H === V
        ), j = h.shiftKey ? D.slice(0, A).reverse() : D.slice(A + 1, D.length);
        if (ys(j))
          h.preventDefault();
        else {
          (M = d.focusProxyRef.value) == null || M.focus();
          return;
        }
      }
      const I = At(
        h,
        me(),
        void 0,
        { itemsArray: D, loop: !1, enableIgnoredElement: !0 }
      );
      I == null || I.focus();
    }
    function $() {
      var E;
      const h = new Event(Va, {
        bubbles: !0,
        cancelable: !0
      });
      (E = i.value) == null || E.dispatchEvent(h);
    }
    return (h, E) => (b(), S(o(Ct), k({
      id: o(f),
      ref: o(r),
      "aria-labelledby": o(c),
      "data-motion": p.value,
      "data-state": o(on)(o(u).modelValue.value === o(d).value),
      "data-orientation": o(u).orientation
    }, e, {
      onKeydown: C,
      onEscapeKeyDown: _,
      onPointerDownOutside: m,
      onFocusOutside: g,
      onDismiss: $
    }), {
      default: y(() => [
        w(h.$slots, "default")
      ]),
      _: 3
    }, 16, ["id", "aria-labelledby", "data-motion", "data-state", "data-orientation"]));
  }
}), cy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "NavigationMenuContent",
  props: {
    forceMount: { type: Boolean },
    disableOutsidePointerEvents: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Te(n), { forwardRef: s } = R(), r = Ga(), i = _t(), u = Po(), d = B(() => u.value === i.modelValue.value), c = B(() => i.viewport.value && !i.modelValue.value && i.previousValue.value ? i.previousValue.value === u.value : !1);
    return (f, v) => o(r) ? (b(), S(qt, {
      key: 0,
      to: o(i).viewport.value,
      disabled: !o(i).viewport.value
    }, [
      q(o(Pe), {
        present: f.forceMount || d.value || c.value
      }, {
        default: y(() => [
          q(Kc, k({
            ref: o(s),
            "data-state": o(on)(d.value),
            style: {
              pointerEvents: !d.value && o(i).isRootMenu ? "none" : void 0
            }
          }, { ...f.$attrs, ...e, ...o(l) }, {
            onPointerenter: v[0] || (v[0] = (p) => o(i).onContentEnter(o(u).value)),
            onPointerleave: v[1] || (v[1] = (p) => o(gs)(() => o(i).onContentLeave())(p)),
            onPointerDownOutside: v[2] || (v[2] = (p) => n("pointerDownOutside", p)),
            onFocusOutside: v[3] || (v[3] = (p) => n("focusOutside", p)),
            onInteractOutside: v[4] || (v[4] = (p) => n("interactOutside", p))
          }), {
            default: y(() => [
              w(f.$slots, "default")
            ]),
            _: 3
          }, 16, ["data-state", "style"])
        ]),
        _: 3
      }, 8, ["present"])
    ], 8, ["to", "disabled"])) : ce("", !0);
  }
}), fy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "NavigationMenuIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), { injectCollection: n } = Fe("nav"), l = n(), s = _t(), r = T(), i = B(() => s.orientation === "horizontal"), u = B(() => !!s.modelValue.value), d = T();
    function c() {
      d.value && (r.value = {
        size: i.value ? d.value.offsetWidth : d.value.offsetHeight,
        offset: i.value ? d.value.offsetLeft : d.value.offsetTop
      });
    }
    return Ce(() => {
      if (!s.modelValue.value) {
        r.value = void 0;
        return;
      }
      const f = l.value;
      d.value = f.find(
        (v) => v.id.includes(s.modelValue.value)
      ), c();
    }), tt(d, c), tt(s.indicatorTrack, c), (f, v) => o(s).indicatorTrack.value ? (b(), S(qt, {
      key: 0,
      to: o(s).indicatorTrack.value
    }, [
      q(o(Pe), {
        present: f.forceMount || u.value
      }, {
        default: y(() => {
          var p, g, m, _;
          return [
            q(o(O), k({
              ref: o(e),
              "aria-hidden": "true",
              "data-state": u.value ? "visible" : "hidden",
              "data-orientation": o(s).orientation,
              "as-child": t.asChild,
              as: f.as,
              style: {
                position: "absolute",
                ...i.value ? {
                  left: 0,
                  width: `${(p = r.value) == null ? void 0 : p.size}px`,
                  transform: `translateX(${(g = r.value) == null ? void 0 : g.offset}px)`
                } : {
                  top: 0,
                  height: `${(m = r.value) == null ? void 0 : m.size}px`,
                  transform: `translateY(${(_ = r.value) == null ? void 0 : _.offset}px)`
                }
              }
            }, f.$attrs), {
              default: y(() => [
                w(f.$slots, "default")
              ]),
              _: 3
            }, 16, ["data-state", "data-orientation", "as-child", "as", "style"])
          ];
        }),
        _: 3
      }, 8, ["present"])
    ], 8, ["to"])) : ce("", !0);
  }
}), py = /* @__PURE__ */ x({
  __name: "NavigationMenuLink",
  props: {
    active: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "a" }
  },
  emits: ["select"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    async function l(s) {
      var i;
      const r = new CustomEvent(Nc, {
        bubbles: !0,
        cancelable: !0,
        detail: {
          originalEvent: s
        }
      });
      if (n("select", r), !r.defaultPrevented && !s.metaKey) {
        const u = new CustomEvent(
          Va,
          {
            bubbles: !0,
            cancelable: !0
          }
        );
        (i = s.target) == null || i.dispatchEvent(u);
      }
    }
    return (s, r) => (b(), S(o(O), {
      as: s.as,
      "data-active": s.active ? "" : void 0,
      "aria-current": s.active ? "page" : void 0,
      "as-child": e.asChild,
      "data-radix-vue-collection-item": "",
      onClick: l
    }, {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "data-active", "aria-current", "as-child"]));
  }
}), vy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "NavigationMenuList",
  props: {
    asChild: { type: Boolean },
    as: { default: "ul" }
  },
  setup(a) {
    const t = a, e = _t(), { forwardRef: n, currentElement: l } = R();
    return le(() => {
      e.onIndicatorTrackChange(l.value);
    }), (s, r) => (b(), S(o(O), {
      ref: o(n),
      style: { position: "relative" }
    }, {
      default: y(() => [
        q(o(O), k(s.$attrs, {
          "as-child": t.asChild,
          as: s.as,
          "data-orientation": o(e).orientation
        }), {
          default: y(() => [
            w(s.$slots, "default")
          ]),
          _: 3
        }, 16, ["as-child", "as", "data-orientation"])
      ]),
      _: 3
    }, 512));
  }
}), my = /* @__PURE__ */ x({
  __name: "NavigationMenuSub",
  props: {
    modelValue: {},
    defaultValue: {},
    orientation: { default: "horizontal" },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "modelValue", t, {
      defaultValue: e.defaultValue ?? "",
      passive: e.modelValue === void 0
    }), s = T(""), r = _t(), { forwardRef: i, currentElement: u } = R(), d = T(), c = T(), { createCollection: f } = Fe("nav");
    return f(d), ms({
      ...r,
      isRootMenu: !1,
      modelValue: l,
      previousValue: s,
      orientation: e.orientation,
      rootNavigationMenu: u,
      indicatorTrack: d,
      onIndicatorTrackChange: (v) => {
        d.value = v;
      },
      viewport: c,
      onViewportChange: (v) => {
        c.value = v;
      },
      onTriggerEnter: (v) => {
        l.value = v;
      },
      onTriggerLeave: () => {
      },
      onContentEnter: () => {
      },
      onContentLeave: () => {
      },
      onItemSelect: (v) => {
        l.value = v;
      },
      onItemDismiss: () => {
        l.value = "";
      }
    }), (v, p) => (b(), S(o(O), {
      ref: o(i),
      "data-orientation": v.orientation,
      "as-child": e.asChild,
      as: v.as,
      "data-radix-navigation-menu": ""
    }, {
      default: y(() => [
        w(v.$slots, "default", { modelValue: o(l) })
      ]),
      _: 3
    }, 8, ["data-orientation", "as-child", "as"]));
  }
}), Hc = ["aria-owns"], hy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "NavigationMenuTrigger",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = _t(), n = Po(), { forwardRef: l, currentElement: s } = R(), r = T(""), i = T(""), u = Tt(!1, 300), d = T(!1), c = B(() => n.value === e.modelValue.value);
    le(() => {
      n.triggerRef = s, r.value = hs(e.baseId, n.value), i.value = Eo(e.baseId, n.value);
    });
    function f() {
      e.disableHoverTrigger.value || (d.value = !1, n.wasEscapeCloseRef.value = !1);
    }
    function v($) {
      if (!e.disableHoverTrigger.value && $.pointerType === "mouse") {
        if (t.disabled || d.value || n.wasEscapeCloseRef.value || u.value)
          return;
        e.onTriggerEnter(n.value), u.value = !0;
      }
    }
    function p($) {
      if (!e.disableHoverTrigger.value && $.pointerType === "mouse") {
        if (t.disabled)
          return;
        e.onTriggerLeave(), u.value = !1;
      }
    }
    function g($) {
      $.pointerType === "mouse" && e.disableClickTrigger.value || u.value || (c.value ? e.onItemSelect("") : e.onItemSelect(n.value), d.value = c.value);
    }
    function m($) {
      const E = { horizontal: "ArrowDown", vertical: e.dir.value === "rtl" ? "ArrowLeft" : "ArrowRight" }[e.orientation];
      c.value && $.key === E && (n.onEntryKeyDown(), $.preventDefault(), $.stopPropagation());
    }
    function _($) {
      n.focusProxyRef.value = $e($);
    }
    function C($) {
      const h = document.getElementById(n.contentId), E = $.relatedTarget, P = E === s.value, D = h == null ? void 0 : h.contains(E);
      (P || !D) && n.onFocusProxyEnter(P ? "start" : "end");
    }
    return ($, h) => (b(), ve(_e, null, [
      q(o(O), k({
        id: r.value,
        ref: o(l),
        disabled: $.disabled,
        "data-disabled": $.disabled ? "" : void 0,
        "data-state": o(on)(c.value),
        "aria-expanded": c.value,
        "aria-controls": i.value,
        "as-child": t.asChild,
        as: $.as
      }, $.$attrs, {
        "data-radix-vue-collection-item": "",
        onPointerenter: f,
        onPointermove: v,
        onPointerleave: p,
        onClick: g,
        onKeydown: m
      }), {
        default: y(() => [
          w($.$slots, "default")
        ]),
        _: 3
      }, 16, ["id", "disabled", "data-disabled", "data-state", "aria-expanded", "aria-controls", "as-child", "as"]),
      c.value ? (b(), ve(_e, { key: 0 }, [
        q(o(Jt), {
          ref: _,
          "aria-hidden": "true",
          tabindex: 0,
          onFocus: C
        }),
        o(e).viewport ? (b(), ve("span", {
          key: 0,
          "aria-owns": i.value
        }, null, 8, Hc)) : ce("", !0)
      ], 64)) : ce("", !0)
    ], 64));
  }
}), yy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "NavigationMenuViewport",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const { forwardRef: t, currentElement: e } = R(), n = _t(), l = T(), s = B(() => !!n.modelValue.value), r = B(() => n.modelValue.value);
    ee(e, () => {
      e.value && n.onViewportChange(e.value);
    });
    const i = T();
    return ee([r, s], async () => {
      var d, c;
      if (await oe(), !e.value)
        return;
      const u = (c = (d = e.value.querySelector("[data-state=open]")) == null ? void 0 : d.children) == null ? void 0 : c[0];
      i.value = u;
    }, { immediate: !0 }), tt(i, () => {
      i.value && (l.value = {
        width: i.value.offsetWidth,
        height: i.value.offsetHeight
      });
    }), (u, d) => (b(), S(o(Pe), {
      present: u.forceMount || s.value
    }, {
      default: y(() => {
        var c, f;
        return [
          q(o(O), k(u.$attrs, {
            ref: o(t),
            as: u.as,
            "as-child": u.asChild,
            "data-state": o(on)(s.value),
            "data-orientation": o(n).orientation,
            style: {
              // Prevent interaction when animating out
              pointerEvents: !s.value && o(n).isRootMenu ? "none" : void 0,
              "--radix-navigation-menu-viewport-width": l.value ? `${(c = l.value) == null ? void 0 : c.width}px` : void 0,
              "--radix-navigation-menu-viewport-height": l.value ? `${(f = l.value) == null ? void 0 : f.height}px` : void 0
            },
            onPointerenter: d[0] || (d[0] = (v) => o(n).onContentEnter(o(n).modelValue.value)),
            onPointerleave: d[1] || (d[1] = (v) => o(gs)(() => o(n).onContentLeave())(v))
          }), {
            default: y(() => [
              w(u.$slots, "default")
            ]),
            _: 3
          }, 16, ["as", "as-child", "data-state", "data-orientation", "style"])
        ];
      }),
      _: 3
    }, 8, ["present"]));
  }
});
function bs(a) {
  const { disabled: t } = a, e = T(), n = ua(), l = () => window.clearTimeout(e.value), s = (v) => {
    l(), !t.value && (n.trigger(), e.value = window.setTimeout(() => {
      s(60);
    }, v));
  }, r = () => {
    s(400);
  }, i = () => {
    l();
  }, u = T(!1), d = B(() => $e(a.target)), c = (v) => {
    v.button !== 0 || u.value || (v.preventDefault(), u.value = !0, r());
  }, f = () => {
    u.value = !1, i();
  };
  return Je && (He(d || window, "pointerdown", c), He(window, "pointerup", f), He(window, "pointercancel", f)), {
    isPressed: u,
    onTrigger: n.on
  };
}
function Qo(a, t = T({})) {
  return $l(() => new Kr(a.value, t.value));
}
function Wc(a, t = T({})) {
  return $l(() => new Hr(a.value, t.value));
}
function el(a, t, e) {
  let n = a === "+" ? t + e : t - e;
  if (t % 1 !== 0 || e % 1 !== 0) {
    const l = t.toString().split("."), s = e.toString().split("."), r = l[1] && l[1].length || 0, i = s[1] && s[1].length || 0, u = 10 ** Math.max(r, i);
    t = Math.round(t * u), e = Math.round(e * u), n = a === "+" ? t + e : t - e, n /= u;
  }
  return n;
}
const jc = ["value", "name", "disabled", "required"], [Do, Uc] = te("NumberFieldRoot"), gy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "NumberFieldRoot",
  props: {
    defaultValue: { default: void 0 },
    modelValue: {},
    min: {},
    max: {},
    step: { default: 1 },
    formatOptions: {},
    locale: { default: "en-US" },
    disabled: { type: Boolean },
    required: { type: Boolean },
    name: {},
    id: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { disabled: l, min: s, max: r, step: i, locale: u, formatOptions: d, id: c } = ae(e), f = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: e.modelValue === void 0
    }), { primitiveElement: v, currentElement: p } = Re(), g = at(p), m = T(), _ = B(
      () => H(f.value) === s.value || (s.value && !isNaN(f.value) ? el("-", f.value, i.value) < s.value : !1)
    ), C = B(
      () => H(f.value) === r.value || (r.value && !isNaN(f.value) ? el("+", f.value, i.value) > r.value : !1)
    );
    function $(G, J = 1) {
      var K;
      const z = I.parse(((K = m.value) == null ? void 0 : K.value) ?? "");
      e.disabled || (isNaN(z) ? f.value = s.value ?? 0 : G === "increase" ? f.value = H(z + (i.value ?? 1) * J) : f.value = H(z - (i.value ?? 1) * J));
    }
    function h(G = 1) {
      $("increase", G);
    }
    function E(G = 1) {
      $("decrease", G);
    }
    function P(G) {
      G === "min" && s.value !== void 0 ? f.value = H(s.value) : G === "max" && r.value !== void 0 && (f.value = H(r.value));
    }
    const D = Qo(u, d), I = Wc(u, d), M = B(() => D.resolvedOptions().maximumFractionDigits > 0 ? "decimal" : "numeric"), V = Qo(u, d), A = B(() => isNaN(f.value) ? "" : V.format(f.value));
    function F(G) {
      return I.isValidPartialNumber(G, s.value, r.value);
    }
    function j(G) {
      m.value && (m.value.value = G);
    }
    function H(G) {
      let J;
      return i.value === void 0 || isNaN(i.value) ? J = Ut(G, s.value, r.value) : J = Wr(G, s.value, r.value, i.value), J = I.parse(D.format(J)), J;
    }
    function Q(G) {
      const J = I.parse(G);
      return f.value = H(J), G.length ? (isNaN(J), j(A.value)) : j(G);
    }
    return Uc({
      modelValue: f,
      handleDecrease: E,
      handleIncrease: h,
      handleMinMaxValue: P,
      inputMode: M,
      inputEl: m,
      onInputElement: (G) => m.value = G,
      textValue: A,
      validate: F,
      applyInputValue: Q,
      disabled: l,
      max: r,
      min: s,
      isDecreaseDisabled: _,
      isIncreaseDisabled: C,
      id: c
    }), (G, J) => (b(), ve(_e, null, [
      q(o(O), k(G.$attrs, {
        ref_key: "primitiveElement",
        ref: v,
        role: "group",
        as: G.as,
        "as-child": G.asChild,
        "data-disabled": o(l) ? "" : void 0
      }), {
        default: y(() => [
          w(G.$slots, "default", {
            modelValue: o(f),
            textValue: A.value
          })
        ]),
        _: 3
      }, 16, ["as", "as-child", "data-disabled"]),
      o(g) ? (b(), ve("input", {
        key: 0,
        type: "text",
        tabindex: "-1",
        "aria-hidden": "true",
        value: o(f),
        name: e.name,
        disabled: e.disabled,
        required: e.required,
        style: {
          transform: "translateX(-100%)",
          position: "absolute",
          pointerEvents: "none",
          opacity: 0,
          margin: 0
        }
      }, null, 8, jc)) : ce("", !0)
    ], 64));
  }
}), by = /* @__PURE__ */ x({
  __name: "NumberFieldInput",
  props: {
    asChild: { type: Boolean },
    as: { default: "input" }
  },
  setup(a) {
    const t = a, { primitiveElement: e, currentElement: n } = Re(), l = Do();
    function s(u) {
      u.target === me() && (Math.abs(u.deltaY) <= Math.abs(u.deltaX) || (u.preventDefault(), u.deltaY > 0 ? l.handleIncrease() : u.deltaY < 0 && l.handleDecrease()));
    }
    le(() => {
      l.onInputElement(n.value);
    });
    const r = T(l.textValue.value);
    ee(() => l.textValue.value, () => {
      r.value = l.textValue.value;
    }, { immediate: !0, deep: !0 });
    function i() {
      requestAnimationFrame(() => {
        r.value = l.textValue.value;
      });
    }
    return (u, d) => (b(), S(o(O), k(t, {
      id: o(l).id.value,
      ref_key: "primitiveElement",
      ref: e,
      value: r.value,
      role: "spinbutton",
      type: "text",
      tabindex: "0",
      inputmode: o(l).inputMode.value,
      disabled: o(l).disabled.value ? "" : void 0,
      "data-disabled": o(l).disabled.value ? "" : void 0,
      autocomplete: "off",
      autocorrect: "off",
      spellcheck: "false",
      "aria-roledescription": "Number field",
      "aria-valuenow": o(l).modelValue.value,
      "aria-valuemin": o(l).min.value,
      "aria-valuemax": o(l).max.value,
      onKeydown: [
        d[0] || (d[0] = ie(ue((c) => o(l).handleIncrease(), ["prevent"]), ["up"])),
        d[1] || (d[1] = ie(ue((c) => o(l).handleDecrease(), ["prevent"]), ["down"])),
        d[2] || (d[2] = ie(ue((c) => o(l).handleIncrease(10), ["prevent"]), ["page-up"])),
        d[3] || (d[3] = ie(ue((c) => o(l).handleDecrease(10), ["prevent"]), ["page-down"])),
        d[4] || (d[4] = ie(ue((c) => o(l).handleMinMaxValue("min"), ["prevent"]), ["home"])),
        d[5] || (d[5] = ie(ue((c) => o(l).handleMinMaxValue("max"), ["prevent"]), ["end"])),
        d[8] || (d[8] = ie((c) => {
          var f;
          return o(l).applyInputValue((f = c.target) == null ? void 0 : f.value);
        }, ["enter"]))
      ],
      onWheel: s,
      onBeforeinput: d[6] || (d[6] = (c) => {
        const f = c.target;
        let v = f.value.slice(0, f.selectionStart ?? void 0) + (c.data ?? "") + f.value.slice(f.selectionEnd ?? void 0);
        o(l).validate(v) || c.preventDefault();
      }),
      onInput: d[7] || (d[7] = (c) => {
        const f = c.target;
        r.value = f.value;
      }),
      onChange: i,
      onBlur: d[9] || (d[9] = (c) => {
        var f;
        return o(l).applyInputValue((f = c.target) == null ? void 0 : f.value);
      })
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16, ["id", "value", "inputmode", "disabled", "data-disabled", "aria-valuenow", "aria-valuemin", "aria-valuemax"]));
  }
}), Cy = /* @__PURE__ */ x({
  __name: "NumberFieldIncrement",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = Do(), n = B(() => {
      var u;
      return ((u = e.disabled) == null ? void 0 : u.value) || t.disabled || e.isIncreaseDisabled.value;
    }), { primitiveElement: l, currentElement: s } = Re(), { isPressed: r, onTrigger: i } = bs({ target: s, disabled: n });
    return i(() => {
      e.handleIncrease();
    }), (u, d) => (b(), S(o(O), k(t, {
      ref_key: "primitiveElement",
      ref: l,
      tabindex: "-1",
      "aria-label": "Increase",
      type: u.as === "button" ? "button" : void 0,
      style: {
        userSelect: o(r) ? "none" : void 0
      },
      disabled: n.value ? "" : void 0,
      "data-disabled": n.value ? "" : void 0,
      "data-pressed": o(r) ? "true" : void 0,
      onContextmenu: d[0] || (d[0] = ue(() => {
      }, ["prevent"]))
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16, ["type", "style", "disabled", "data-disabled", "data-pressed"]));
  }
}), wy = /* @__PURE__ */ x({
  __name: "NumberFieldDecrement",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = Do(), n = B(() => {
      var u;
      return ((u = e.disabled) == null ? void 0 : u.value) || t.disabled || e.isDecreaseDisabled.value;
    }), { primitiveElement: l, currentElement: s } = Re(), { isPressed: r, onTrigger: i } = bs({ target: s, disabled: n });
    return i(() => {
      e.handleDecrease();
    }), (u, d) => (b(), S(o(O), k(t, {
      ref_key: "primitiveElement",
      ref: l,
      tabindex: "-1",
      "aria-label": "Decrease",
      type: u.as === "button" ? "button" : void 0,
      style: {
        userSelect: o(r) ? "none" : void 0
      },
      disabled: n.value ? "" : void 0,
      "data-disabled": n.value ? "" : void 0,
      "data-pressed": o(r) ? "true" : void 0,
      onContextmenu: d[0] || (d[0] = ue(() => {
      }, ["prevent"]))
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16, ["type", "style", "disabled", "data-disabled", "data-pressed"]));
  }
}), [aa, Gc] = te("PaginationRoot"), _y = /* @__PURE__ */ x({
  __name: "PaginationRoot",
  props: {
    page: {},
    defaultPage: { default: 1 },
    itemsPerPage: { default: 10 },
    total: { default: 0 },
    siblingCount: { default: 2 },
    disabled: { type: Boolean },
    showEdges: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: { default: "nav" }
  },
  emits: ["update:page"],
  setup(a, { emit: t }) {
    const e = a, n = t, { siblingCount: l, disabled: s, showEdges: r } = ae(e);
    R();
    const i = ne(e, "page", n, {
      defaultValue: e.defaultPage,
      passive: e.page === void 0
    }), u = B(() => Math.max(1, Math.ceil(e.total / e.itemsPerPage)));
    return Gc({
      page: i,
      onPageChange(d) {
        i.value = d;
      },
      pageCount: u,
      siblingCount: l,
      disabled: s,
      showEdges: r
    }), (d, c) => (b(), S(o(O), {
      as: d.as,
      "as-child": d.asChild
    }, {
      default: y(() => [
        w(d.$slots, "default", {
          page: o(i),
          pageCount: u.value
        })
      ]),
      _: 3
    }, 8, ["as", "as-child"]));
  }
}), xy = /* @__PURE__ */ x({
  __name: "PaginationEllipsis",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(O), k(t, { "data-type": "ellipsis" }), {
      default: y(() => [
        w(e.$slots, "default", {}, () => [
          ye("…")
        ])
      ]),
      _: 3
    }, 16));
  }
}), Sy = /* @__PURE__ */ x({
  __name: "PaginationFirst",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = aa();
    R();
    const n = B(() => e.page.value === 1 || e.disabled.value);
    return (l, s) => (b(), S(o(O), k(t, {
      "aria-label": "First Page",
      type: l.as === "button" ? "button" : void 0,
      disabled: n.value,
      onClick: s[0] || (s[0] = (r) => !n.value && o(e).onPageChange(1))
    }), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("First page")
        ])
      ]),
      _: 3
    }, 16, ["type", "disabled"]));
  }
}), Ey = /* @__PURE__ */ x({
  __name: "PaginationLast",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = aa();
    R();
    const n = B(() => e.page.value === e.pageCount.value || e.disabled.value);
    return (l, s) => (b(), S(o(O), k(t, {
      "aria-label": "Last Page",
      type: l.as === "button" ? "button" : void 0,
      disabled: n.value,
      onClick: s[0] || (s[0] = (r) => !n.value && o(e).onPageChange(o(e).pageCount.value))
    }), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Last page")
        ])
      ]),
      _: 3
    }, 16, ["type", "disabled"]));
  }
});
function dt(a, t) {
  const e = t - a + 1;
  return Array.from({ length: e }, (n, l) => l + a);
}
function qc(a) {
  return a.map((t) => typeof t == "number" ? { type: "page", value: t } : { type: "ellipsis" });
}
const Ta = "ellipsis";
function Yc(a, t, e, n) {
  const s = t, r = Math.max(a - e, 1), i = Math.min(a + e, s);
  if (n) {
    const d = Math.min(2 * e + 5, t) - 2, c = r > 3 && Math.abs(s - d - 1 + 1) > 2 && Math.abs(r - 1) > 2, f = i < s - 2 && Math.abs(s - d) > 2 && Math.abs(s - i) > 2;
    if (!c && f)
      return [...dt(1, d), Ta, s];
    if (c && !f) {
      const p = dt(s - d + 1, s);
      return [1, Ta, ...p];
    }
    if (c && f) {
      const p = dt(r, i);
      return [1, Ta, ...p, Ta, s];
    }
    return dt(1, s);
  } else {
    const u = e * 2 + 1;
    return t < u ? dt(1, s) : a <= e + 1 ? dt(1, u) : t - a <= e ? dt(t - u + 1, s) : dt(r, i);
  }
}
const Py = /* @__PURE__ */ x({
  __name: "PaginationList",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    R();
    const e = aa(), n = B(() => qc(
      Yc(
        e.page.value,
        e.pageCount.value,
        e.siblingCount.value,
        e.showEdges.value
      )
    ));
    return (l, s) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(l.$slots, "default", { items: n.value })
      ]),
      _: 3
    }, 16));
  }
}), Dy = /* @__PURE__ */ x({
  __name: "PaginationListItem",
  props: {
    value: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = aa(), n = B(() => e.page.value === t.value), l = B(() => e.disabled.value);
    return (s, r) => (b(), S(o(O), k(t, {
      "data-type": "page",
      "aria-label": `Page ${s.value}`,
      "aria-current": n.value ? "page" : void 0,
      "data-selected": n.value ? "true" : void 0,
      disabled: l.value,
      type: s.as === "button" ? "button" : void 0,
      onClick: r[0] || (r[0] = (i) => !l.value && o(e).onPageChange(s.value))
    }), {
      default: y(() => [
        w(s.$slots, "default", {}, () => [
          ye(De(s.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["aria-label", "aria-current", "data-selected", "disabled", "type"]));
  }
}), $y = /* @__PURE__ */ x({
  __name: "PaginationNext",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = aa(), n = B(() => e.page.value === e.pageCount.value || e.disabled.value);
    return (l, s) => (b(), S(o(O), k(t, {
      "aria-label": "Next Page",
      type: l.as === "button" ? "button" : void 0,
      disabled: n.value,
      onClick: s[0] || (s[0] = (r) => !n.value && o(e).onPageChange(o(e).page.value + 1))
    }), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Next page")
        ])
      ]),
      _: 3
    }, 16, ["type", "disabled"]));
  }
}), By = /* @__PURE__ */ x({
  __name: "PaginationPrev",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = aa(), n = B(() => e.page.value === 1 || e.disabled.value);
    return (l, s) => (b(), S(o(O), k(t, {
      "aria-label": "Previous Page",
      type: l.as === "button" ? "button" : void 0,
      disabled: n.value,
      onClick: s[0] || (s[0] = (r) => !n.value && o(e).onPageChange(o(e).page.value - 1))
    }), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Prev page")
        ])
      ]),
      _: 3
    }, 16, ["type", "disabled"]));
  }
}), Xc = ["id", "value", "name", "disabled", "required"], [Zc, Jc] = te("PinInputRoot"), Iy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "PinInputRoot",
  props: {
    modelValue: {},
    defaultValue: {},
    placeholder: { default: "" },
    mask: { type: Boolean },
    otp: { type: Boolean },
    type: { default: "text" },
    dir: {},
    name: {},
    disabled: { type: Boolean },
    required: { type: Boolean },
    id: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "complete"],
  setup(a, { emit: t }) {
    const e = a, n = t, { mask: l, otp: s, placeholder: r, type: i, disabled: u, dir: d } = ae(e), { forwardRef: c } = R(), f = we(d), v = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue ?? [],
      passive: e.modelValue === void 0
    }), p = T(/* @__PURE__ */ new Set());
    function g(_) {
      p.value.add(_);
    }
    const m = B(() => v.value.filter((C) => !!C).length === p.value.size);
    return ee(v, () => {
      m.value && n("complete", v.value);
    }, { deep: !0 }), Jc({
      modelValue: v,
      mask: l,
      otp: s,
      placeholder: r,
      type: i,
      dir: f,
      disabled: u,
      isCompleted: m,
      inputElements: p,
      onInputElementChange: g
    }), (_, C) => (b(), ve(_e, null, [
      q(o(O), k(_.$attrs, {
        ref: o(c),
        dir: o(f),
        "data-complete": m.value ? "" : void 0,
        "data-disabled": o(u) ? "" : void 0
      }), {
        default: y(() => [
          w(_.$slots, "default", { modelValue: o(v) })
        ]),
        _: 3
      }, 16, ["dir", "data-complete", "data-disabled"]),
      Ye("input", {
        id: _.id,
        type: "text",
        tabindex: "-1",
        "aria-hidden": "true",
        value: o(v).join(""),
        name: _.name,
        disabled: o(u),
        required: _.required,
        style: {
          transform: "translateX(-100%)",
          position: "absolute",
          pointerEvents: "none",
          opacity: 0,
          margin: 0
        },
        onFocus: C[0] || (C[0] = ($) => {
          var h, E;
          return (E = (h = Array.from(p.value)) == null ? void 0 : h[0]) == null ? void 0 : E.focus();
        })
      }, null, 40, Xc)
    ], 64));
  }
}), Ty = /* @__PURE__ */ x({
  __name: "PinInputInput",
  props: {
    index: {},
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "input" }
  },
  setup(a) {
    const t = a, e = Zc(), n = B(() => Array.from(e.inputElements.value)), l = B(() => e.modelValue.value[t.index]), s = B(() => t.disabled || e.disabled.value), r = B(() => e.otp.value), i = B(() => e.type.value === "number"), u = B(() => e.mask.value), { primitiveElement: d, currentElement: c } = Re();
    function f(D) {
      var V;
      const I = D.target;
      if ((((V = D.data) == null ? void 0 : V.length) ?? 0) > 1) {
        h(I.value);
        return;
      }
      if (i.value && !/^\d*$/.test(I.value)) {
        I.value = I.value.replace(/\D/g, "");
        return;
      }
      I.value = I.value.slice(-1), P(t.index, I.value);
      const M = n.value[t.index + 1];
      M && M.focus();
    }
    function v() {
      const D = c.value;
      oe(() => {
        D && !D.value && (D.placeholder = e.placeholder.value);
      });
    }
    function p(D) {
      At(D, me(), void 0, {
        itemsArray: n.value,
        focus: !0,
        loop: !1,
        arrowKeyOptions: "horizontal",
        dir: e.dir.value
      });
    }
    function g(D) {
      if (D.preventDefault(), D.target.value)
        P(t.index, "");
      else {
        const V = n.value[t.index - 1];
        V && (V.focus(), P(t.index - 1, ""));
      }
    }
    function m(D) {
      D.key === "Delete" && (D.preventDefault(), P(t.index, ""));
    }
    function _(D) {
      const I = D.target;
      I.setSelectionRange(1, 1), I.value || (I.placeholder = "");
    }
    function C(D) {
      v();
    }
    function $(D) {
      D.preventDefault();
      const I = D.clipboardData;
      if (!I)
        return;
      const M = I.getData("text");
      h(M);
    }
    function h(D) {
      var A;
      const I = [...e.modelValue.value], M = D.length >= n.value.length ? 0 : t.index, V = Math.min(M + D.length, n.value.length);
      for (let F = M; F < V; F++) {
        const j = n.value[F], H = D[F - M];
        i.value && !/^\d*$/.test(H) || (I[F] = H, j.focus());
      }
      e.modelValue.value = I, (A = n.value[V]) == null || A.focus();
    }
    function E(D) {
      let I = D.length - 1;
      for (; I >= 0 && D[I] === ""; )
        D.pop(), I--;
      return D;
    }
    function P(D, I) {
      const M = [...e.modelValue.value];
      M[D] = I, e.modelValue.value = E(M);
    }
    return ee(l, () => {
      l.value || v();
    }), le(() => {
      e.onInputElementChange(c.value);
    }), Be(() => {
      var D;
      (D = e.inputElements) == null || D.value.delete(c.value);
    }), (D, I) => (b(), S(o(O), {
      ref_key: "primitiveElement",
      ref: d,
      autocapitalize: "none",
      as: D.as,
      "as-child": D.asChild,
      autocomplete: r.value ? "one-time-code" : "false",
      type: u.value ? "password" : "text",
      inputmode: i.value ? "numeric" : "text",
      pattern: i.value ? "[0-9]*" : void 0,
      placeholder: o(e).placeholder.value,
      value: l.value,
      disabled: s.value,
      "data-disabled": s.value ? "" : void 0,
      "data-complete": o(e).isCompleted.value ? "" : void 0,
      "aria-label": `pin input ${D.index + 1} of ${n.value.length}`,
      onInput: I[0] || (I[0] = (M) => f(M)),
      onKeydown: [
        ie(p, ["left", "right", "up", "down", "home", "end"]),
        ie(g, ["backspace"]),
        ie(m, ["delete"])
      ],
      onFocus: _,
      onBlur: C,
      onPaste: $
    }, {
      default: y(() => [
        w(D.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child", "autocomplete", "type", "inputmode", "pattern", "placeholder", "value", "disabled", "data-disabled", "data-complete", "aria-label"]));
  }
}), [Lt, Qc] = te("PopoverRoot"), Cs = /* @__PURE__ */ x({
  __name: "PopoverRoot",
  props: {
    defaultOpen: { type: Boolean, default: !1 },
    open: { type: Boolean, default: void 0 },
    modal: { type: Boolean, default: !1 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, { modal: l } = ae(e), s = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    }), r = T(), i = T(!1);
    return Qc({
      contentId: "",
      modal: l,
      open: s,
      onOpenChange: (u) => {
        s.value = u;
      },
      onOpenToggle: () => {
        s.value = !s.value;
      },
      triggerElement: r,
      hasCustomAnchor: i
    }), (u, d) => (b(), S(o(kt), null, {
      default: y(() => [
        w(u.$slots, "default", { open: o(s) })
      ]),
      _: 3
    }));
  }
}), ws = /* @__PURE__ */ x({
  __name: "PopoverTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = Lt(), { forwardRef: n, currentElement: l } = R();
    return le(() => {
      e.triggerElement.value = l.value;
    }), (s, r) => (b(), S(Xe(o(e).hasCustomAnchor.value ? o(O) : o(Mt)), { "as-child": "" }, {
      default: y(() => [
        q(o(O), {
          ref: o(n),
          type: s.as === "button" ? "button" : void 0,
          "aria-haspopup": "dialog",
          "aria-expanded": o(e).open.value,
          "aria-controls": o(e).contentId,
          "data-state": o(e).open.value ? "open" : "closed",
          as: s.as,
          "as-child": t.asChild,
          onClick: o(e).onOpenToggle
        }, {
          default: y(() => [
            w(s.$slots, "default")
          ]),
          _: 3
        }, 8, ["type", "aria-expanded", "aria-controls", "data-state", "as", "as-child", "onClick"])
      ]),
      _: 3
    }));
  }
}), _s = /* @__PURE__ */ x({
  __name: "PopoverPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), xs = /* @__PURE__ */ x({
  __name: "PopoverContentImpl",
  props: {
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Ot(e), { forwardRef: s } = R(), r = Lt();
    return Yn(), (i, u) => (b(), S(o(Za), {
      "as-child": "",
      loop: "",
      trapped: i.trapFocus,
      onMountAutoFocus: u[5] || (u[5] = (d) => n("openAutoFocus", d)),
      onUnmountAutoFocus: u[6] || (u[6] = (d) => n("closeAutoFocus", d))
    }, {
      default: y(() => [
        q(o(Ct), {
          "as-child": "",
          "disable-outside-pointer-events": i.disableOutsidePointerEvents,
          onPointerDownOutside: u[0] || (u[0] = (d) => n("pointerDownOutside", d)),
          onInteractOutside: u[1] || (u[1] = (d) => n("interactOutside", d)),
          onEscapeKeyDown: u[2] || (u[2] = (d) => n("escapeKeyDown", d)),
          onFocusOutside: u[3] || (u[3] = (d) => n("focusOutside", d)),
          onDismiss: u[4] || (u[4] = (d) => o(r).onOpenChange(!1))
        }, {
          default: y(() => [
            q(o(It), k(o(l), {
              id: o(r).contentId,
              ref: o(s),
              "data-state": o(r).open.value ? "open" : "closed",
              role: "dialog",
              style: {
                "--radix-popover-content-transform-origin": "var(--radix-popper-transform-origin)",
                "--radix-popover-content-available-width": "var(--radix-popper-available-width)",
                "--radix-popover-content-available-height": "var(--radix-popper-available-height)",
                "--radix-popover-trigger-width": "var(--radix-popper-anchor-width)",
                "--radix-popover-trigger-height": "var(--radix-popper-anchor-height)"
              }
            }), {
              default: y(() => [
                w(i.$slots, "default")
              ]),
              _: 3
            }, 16, ["id", "data-state"])
          ]),
          _: 3
        }, 8, ["disable-outside-pointer-events"])
      ]),
      _: 3
    }, 8, ["trapped"]));
  }
}), ef = /* @__PURE__ */ x({
  __name: "PopoverContentModal",
  props: {
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Lt(), s = T(!1);
    ya(!0);
    const r = Se(e, n), { forwardRef: i, currentElement: u } = R();
    return ga(u), (d, c) => (b(), S(xs, k(o(r), {
      ref: o(i),
      "trap-focus": o(l).open.value,
      "disable-outside-pointer-events": "",
      onCloseAutoFocus: c[0] || (c[0] = ue(
        (f) => {
          var v;
          n("closeAutoFocus", f), s.value || (v = o(l).triggerElement.value) == null || v.focus();
        },
        ["prevent"]
      )),
      onPointerDownOutside: c[1] || (c[1] = (f) => {
        n("pointerDownOutside", f);
        const v = f.detail.originalEvent, p = v.button === 0 && v.ctrlKey === !0, g = v.button === 2 || p;
        s.value = g;
      }),
      onFocusOutside: c[2] || (c[2] = ue(() => {
      }, ["prevent"]))
    }), {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 16, ["trap-focus"]));
  }
}), tf = /* @__PURE__ */ x({
  __name: "PopoverContentNonModal",
  props: {
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Lt(), s = T(!1), r = T(!1), i = Se(e, n);
    return (u, d) => (b(), S(xs, k(o(i), {
      "trap-focus": !1,
      "disable-outside-pointer-events": !1,
      onCloseAutoFocus: d[0] || (d[0] = (c) => {
        var f;
        n("closeAutoFocus", c), c.defaultPrevented || (s.value || (f = o(l).triggerElement.value) == null || f.focus(), c.preventDefault()), s.value = !1, r.value = !1;
      }),
      onInteractOutside: d[1] || (d[1] = async (c) => {
        var p;
        n("interactOutside", c), c.defaultPrevented || (s.value = !0, c.detail.originalEvent.type === "pointerdown" && (r.value = !0));
        const f = c.target;
        ((p = o(l).triggerElement.value) == null ? void 0 : p.contains(f)) && c.preventDefault(), c.detail.originalEvent.type === "focusin" && r.value && c.preventDefault();
      })
    }), {
      default: y(() => [
        w(u.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ss = /* @__PURE__ */ x({
  __name: "PopoverContent",
  props: {
    forceMount: { type: Boolean },
    trapFocus: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    disableOutsidePointerEvents: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside", "focusOutside", "interactOutside", "openAutoFocus", "closeAutoFocus"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Lt(), s = Se(e, n), { forwardRef: r } = R();
    return l.contentId || (l.contentId = ge(void 0, "radix-vue-popover-content")), (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(l).open.value
    }, {
      default: y(() => [
        o(l).modal.value ? (b(), S(ef, k({ key: 0 }, o(s), { ref: o(r) }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16)) : (b(), S(tf, k({ key: 1 }, o(s), { ref: o(r) }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16))
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Es = /* @__PURE__ */ x({
  __name: "PopoverArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Zt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ps = /* @__PURE__ */ x({
  __name: "PopoverClose",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = Lt();
    return (n, l) => (b(), S(o(O), {
      type: n.as === "button" ? "button" : void 0,
      as: n.as,
      "as-child": t.asChild,
      onClick: l[0] || (l[0] = (s) => o(e).onOpenChange(!1))
    }, {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 8, ["type", "as", "as-child"]));
  }
}), Ds = /* @__PURE__ */ x({
  __name: "PopoverAnchor",
  props: {
    element: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    R();
    const e = Lt();
    return gl(() => {
      e.hasCustomAnchor.value = !0;
    }), Be(() => {
      e.hasCustomAnchor.value = !1;
    }), (n, l) => (b(), S(o(Mt), W(U(t)), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), ca = 100, [af, nf] = te("ProgressRoot"), $o = (a) => typeof a == "number";
function of(a, t) {
  return ht(a) || $o(a) && !Number.isNaN(a) && a <= t && a >= 0 ? a : (console.error(`Invalid prop \`value\` of value \`${a}\` supplied to \`ProgressRoot\`. The \`value\` prop must be:
  - a positive number
  - less than the value passed to \`max\` (or ${ca} if no \`max\` prop is set)
  - \`null\`  or \`undefined\` if the progress is indeterminate.

Defaulting to \`null\`.`), null);
}
function lf(a) {
  return $o(a) && !Number.isNaN(a) && a > 0 ? a : (console.error(
    `Invalid prop \`max\` of value \`${a}\` supplied to \`ProgressRoot\`. Only numbers greater than 0 are valid max values. Defaulting to \`${ca}\`.`
  ), ca);
}
const Ry = /* @__PURE__ */ x({
  __name: "ProgressRoot",
  props: {
    modelValue: {},
    max: { default: ca },
    getValueLabel: { type: Function, default: (a, t) => `${Math.round(a / t * ca)}%` },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "update:max"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    const l = ne(e, "modelValue", n, {
      passive: e.modelValue === void 0
    }), s = ne(e, "max", n, {
      passive: e.max === void 0
    });
    ee(
      () => l.value,
      async (i) => {
        const u = of(i, e.max);
        u !== i && (await oe(), l.value = u);
      },
      { immediate: !0 }
    ), ee(
      () => e.max,
      (i) => {
        const u = lf(e.max);
        u !== i && (s.value = u);
      },
      { immediate: !0 }
    );
    const r = B(() => ht(l.value) ? "indeterminate" : l.value === s.value ? "complete" : "loading");
    return nf({
      modelValue: l,
      max: s,
      progressState: r
    }), (i, u) => (b(), S(o(O), {
      "as-child": i.asChild,
      as: i.as,
      "aria-valuemax": o(s),
      "aria-valuemin": 0,
      "aria-valuenow": $o(o(l)) ? o(l) : void 0,
      "aria-valuetext": i.getValueLabel(o(l), o(s)),
      "aria-label": i.getValueLabel(o(l), o(s)),
      role: "progressbar",
      "data-state": r.value,
      "data-value": o(l) ?? void 0,
      "data-max": o(s)
    }, {
      default: y(() => [
        w(i.$slots, "default", { modelValue: o(l) })
      ]),
      _: 3
    }, 8, ["as-child", "as", "aria-valuemax", "aria-valuenow", "aria-valuetext", "aria-label", "data-state", "data-value", "data-max"]));
  }
}), Ay = /* @__PURE__ */ x({
  __name: "ProgressIndicator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = af();
    return R(), (n, l) => {
      var s;
      return b(), S(o(O), k(t, {
        "data-state": o(e).progressState.value,
        "data-value": ((s = o(e).modelValue) == null ? void 0 : s.value) ?? void 0,
        "data-max": o(e).max.value
      }), {
        default: y(() => [
          w(n.$slots, "default")
        ]),
        _: 3
      }, 16, ["data-state", "data-value", "data-max"]);
    };
  }
}), [sf, rf] = te("RadioGroupRoot"), Oy = /* @__PURE__ */ x({
  __name: "RadioGroupRoot",
  props: {
    modelValue: {},
    defaultValue: {},
    disabled: { type: Boolean, default: !1 },
    name: {},
    required: { type: Boolean, default: !1 },
    orientation: { default: void 0 },
    dir: {},
    loop: { type: Boolean, default: !0 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l } = R(), s = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: e.modelValue === void 0
    }), { disabled: r, loop: i, orientation: u, name: d, required: c, dir: f } = ae(e), v = we(f);
    return rf({
      modelValue: s,
      changeModelValue: (p) => {
        s.value = p;
      },
      disabled: r,
      loop: i,
      orientation: u,
      name: d == null ? void 0 : d.value,
      required: c
    }), (p, g) => (b(), S(o(Ft), {
      "as-child": "",
      orientation: o(u),
      dir: o(v),
      loop: o(i)
    }, {
      default: y(() => [
        q(o(O), {
          ref: o(l),
          role: "radiogroup",
          "data-disabled": o(r) ? "" : void 0,
          "as-child": p.asChild,
          as: p.as,
          required: o(c),
          "aria-orientation": o(u),
          "aria-required": o(c),
          dir: o(v),
          name: o(d)
        }, {
          default: y(() => [
            w(p.$slots, "default", { modelValue: o(s) })
          ]),
          _: 3
        }, 8, ["data-disabled", "as-child", "as", "required", "aria-orientation", "aria-required", "dir", "name"])
      ]),
      _: 3
    }, 8, ["orientation", "dir", "loop"]));
  }
}), uf = ["value", "checked", "name", "disabled", "required"], df = /* @__PURE__ */ x({
  __name: "Radio",
  props: {
    id: {},
    value: {},
    disabled: { type: Boolean, default: !1 },
    required: { type: Boolean },
    checked: { type: Boolean, default: void 0 },
    name: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  emits: ["update:checked"],
  setup(a, { emit: t }) {
    const e = a, l = ne(e, "checked", t, {
      passive: e.checked === void 0
    }), { value: s } = ae(e), { forwardRef: r, currentElement: i } = R(), u = at(i), d = B(() => {
      var f;
      return e.id && i.value ? ((f = document.querySelector(`[for="${e.id}"]`)) == null ? void 0 : f.innerText) ?? e.value : void 0;
    });
    function c(f) {
      l.value = !0, u.value && f.stopPropagation();
    }
    return (f, v) => (b(), S(o(O), k(f.$attrs, {
      id: f.id,
      ref: o(r),
      role: "radio",
      type: f.as === "button" ? "button" : void 0,
      as: f.as,
      "aria-checked": o(l),
      "aria-label": d.value,
      "as-child": f.asChild,
      disabled: f.disabled ? "" : void 0,
      "data-state": o(l) ? "checked" : "unchecked",
      "data-disabled": f.disabled ? "" : void 0,
      value: o(s),
      required: f.required,
      name: f.name,
      onClick: ue(c, ["stop"])
    }), {
      default: y(() => [
        w(f.$slots, "default", { checked: o(l) }),
        o(u) ? (b(), ve("input", {
          key: 0,
          type: "radio",
          tabindex: "-1",
          "aria-hidden": "true",
          value: o(s),
          checked: !!o(l),
          name: f.name,
          disabled: f.disabled,
          required: f.required,
          style: {
            transform: "translateX(-100%)",
            position: "absolute",
            pointerEvents: "none",
            opacity: 0,
            margin: 0
          }
        }, null, 8, uf)) : ce("", !0)
      ]),
      _: 3
    }, 16, ["id", "type", "as", "aria-checked", "aria-label", "as-child", "disabled", "data-state", "data-disabled", "value", "required", "name"]));
  }
}), [cf, ff] = te("RadioGroupItem"), ky = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "RadioGroupItem",
  props: {
    id: {},
    value: {},
    disabled: { type: Boolean, default: !1 },
    required: { type: Boolean },
    name: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, { forwardRef: e, currentElement: n } = R(), l = sf(), s = B(() => l.disabled.value || t.disabled), r = B(() => l.required.value || t.required), i = B(() => {
      var f;
      return ((f = l.modelValue) == null ? void 0 : f.value) === t.value;
    });
    ff({ disabled: s, checked: i });
    const u = T(!1), d = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
    He("keydown", (f) => {
      d.includes(f.key) && (u.value = !0);
    }), He("keyup", () => {
      u.value = !1;
    });
    function c() {
      setTimeout(() => {
        var f;
        u.value && ((f = n.value) == null || f.click());
      }, 0);
    }
    return (f, v) => (b(), S(o(Nt), {
      checked: i.value,
      disabled: s.value,
      "as-child": "",
      focusable: !s.value,
      active: i.value
    }, {
      default: y(() => [
        q(df, k({ ...f.$attrs, ...t }, {
          ref: o(e),
          checked: i.value,
          required: r.value,
          disabled: s.value,
          "onUpdate:checked": v[0] || (v[0] = (p) => o(l).changeModelValue(f.value)),
          onKeydown: v[1] || (v[1] = ie(ue(() => {
          }, ["prevent"]), ["enter"])),
          onFocus: c
        }), {
          default: y(() => [
            w(f.$slots, "default")
          ]),
          _: 3
        }, 16, ["checked", "required", "disabled"])
      ]),
      _: 3
    }, 8, ["checked", "disabled", "focusable", "active"]));
  }
}), My = /* @__PURE__ */ x({
  __name: "RadioGroupIndicator",
  props: {
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const { forwardRef: t } = R(), e = cf();
    return (n, l) => (b(), S(o(Pe), {
      present: n.forceMount || o(e).checked.value
    }, {
      default: y(() => [
        q(o(O), k({
          ref: o(t),
          "data-state": o(e).checked.value ? "checked" : "unchecked",
          "data-disabled": o(e).disabled.value ? "" : void 0,
          "as-child": n.asChild,
          as: n.as
        }, n.$attrs), {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 16, ["data-state", "data-disabled", "as-child", "as"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
});
function pf(a) {
  const t = B(() => a.start.value ? !!a.isDateDisabled(a.start.value) : !1), e = B(() => a.end.value ? !!a.isDateDisabled(a.end.value) : !1), n = B(
    () => t.value || e.value ? !1 : !!(a.start.value && a.end.value && Ke(a.end.value, a.start.value))
  ), l = (c) => a.start.value ? Oe(a.start.value, c) : !1, s = (c) => a.end.value ? Oe(a.end.value, c) : !1, r = (c) => a.start.value && Oe(a.start.value, c) || a.end.value && Oe(a.end.value, c) ? !0 : a.end.value && a.start.value ? Rr(c, a.start.value, a.end.value) : !1, i = B(() => {
    if (a.start.value && a.end.value || !a.start.value || !a.focusedValue.value)
      return null;
    const c = Ke(a.start.value, a.focusedValue.value), f = c ? a.start.value : a.focusedValue.value, v = c ? a.focusedValue.value : a.start.value;
    return Oe(f, v) ? {
      start: f,
      end: v
    } : _l(f, v, a.isDateUnavailable, a.isDateDisabled) ? {
      start: f,
      end: v
    } : null;
  });
  return {
    isInvalid: n,
    isSelected: r,
    highlightedRange: i,
    isSelectionStart: l,
    isSelectionEnd: s,
    isHighlightedStart: (c) => !i.value || !i.value.start ? !1 : Oe(i.value.start, c),
    isHighlightedEnd: (c) => !i.value || !i.value.end ? !1 : Oe(i.value.end, c)
  };
}
const vf = { style: { border: "0px", clip: "rect(0px, 0px, 0px, 0px)", "clip-path": "inset(50%)", height: "1px", margin: "-1px", overflow: "hidden", padding: "0px", position: "absolute", "white-space": "nowrap", width: "1px" } }, mf = {
  role: "heading",
  "aria-level": "2"
}, [na, hf] = te("RangeCalendarRoot"), yf = /* @__PURE__ */ x({
  __name: "RangeCalendarRoot",
  props: {
    defaultPlaceholder: {},
    defaultValue: { default: () => ({ start: void 0, end: void 0 }) },
    modelValue: {},
    placeholder: { default: void 0 },
    pagedNavigation: { type: Boolean, default: !1 },
    preventDeselect: { type: Boolean, default: !1 },
    weekStartsOn: { default: 0 },
    weekdayFormat: { default: "narrow" },
    calendarLabel: {},
    fixedWeeks: { type: Boolean, default: !1 },
    maxValue: {},
    minValue: {},
    locale: { default: "en" },
    numberOfMonths: { default: 1 },
    disabled: { type: Boolean, default: !1 },
    readonly: { type: Boolean, default: !1 },
    initialFocus: { type: Boolean, default: !1 },
    isDateDisabled: { type: Function, default: void 0 },
    isDateUnavailable: { type: Function, default: void 0 },
    dir: {},
    nextPage: {},
    prevPage: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  emits: ["update:modelValue", "update:placeholder", "update:startValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, {
      disabled: l,
      readonly: s,
      initialFocus: r,
      pagedNavigation: i,
      weekStartsOn: u,
      weekdayFormat: d,
      fixedWeeks: c,
      numberOfMonths: f,
      preventDeselect: v,
      isDateUnavailable: p,
      isDateDisabled: g,
      calendarLabel: m,
      maxValue: _,
      minValue: C,
      locale: $,
      dir: h,
      nextPage: E,
      prevPage: P
    } = ae(e), { primitiveElement: D, currentElement: I } = Re(), M = we(h), V = T(), A = T(), F = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue ?? { start: void 0, end: void 0 },
      passive: e.modelValue === void 0
    }), j = Yt({
      defaultPlaceholder: e.placeholder,
      defaultValue: F.value.start,
      locale: e.locale
    }), H = T(F.value.start), Q = T(F.value.end), G = ne(e, "placeholder", n, {
      defaultValue: e.defaultPlaceholder ?? j.copy(),
      passive: e.placeholder === void 0
    });
    function J(he) {
      G.value = he.copy();
    }
    const {
      fullCalendarLabel: z,
      headingValue: K,
      isDateDisabled: L,
      isDateUnavailable: N,
      isNextButtonDisabled: Z,
      isPrevButtonDisabled: Y,
      grid: re,
      weekdays: X,
      isOutsideVisibleView: se,
      nextPage: fe,
      prevPage: xe,
      formatter: Ee
    } = Jl({
      locale: $,
      placeholder: G,
      weekStartsOn: u,
      fixedWeeks: c,
      numberOfMonths: f,
      minValue: C,
      maxValue: _,
      disabled: l,
      weekdayFormat: d,
      pagedNavigation: i,
      isDateDisabled: g.value,
      isDateUnavailable: p.value,
      calendarLabel: m,
      nextPage: E,
      prevPage: P
    }), {
      isInvalid: be,
      isSelected: de,
      highlightedRange: Ie,
      isSelectionStart: Ae,
      isSelectionEnd: We,
      isHighlightedStart: Et,
      isHighlightedEnd: yr
    } = pf({
      start: H,
      end: Q,
      isDateDisabled: L,
      isDateUnavailable: N,
      focusedValue: A
    });
    return ee(F, (he) => {
      var Ne, Ve, Ea, Fo;
      (!he || !he.start || H.value && !ke(he.start, H.value)) && (H.value = (Ve = (Ne = he == null ? void 0 : he.start) == null ? void 0 : Ne.copy) == null ? void 0 : Ve.call(Ne)), (!he || !he.end || Q.value && !ke(he.end, Q.value)) && (Q.value = (Fo = (Ea = he == null ? void 0 : he.end) == null ? void 0 : Ea.copy) == null ? void 0 : Fo.call(Ea));
    }), ee(H, (he) => {
      he && !ke(he, G.value) && J(he), n("update:startValue", he);
    }), ee([H, Q], ([he, Ne]) => {
      const Ve = F.value;
      if (!(Ve && Ve.start && Ve.end && he && Ne && ke(Ve.start, he) && ke(Ve.end, Ne)))
        if (he && Ne) {
          if (Ve.start && Ve.end && ke(Ve.start, he) && ke(Ve.end, Ne))
            return;
          Ke(Ne, he) ? F.value = {
            start: Ne.copy(),
            end: he.copy()
          } : F.value = {
            start: he.copy(),
            end: Ne.copy()
          };
        } else Ve.start && Ve.end && (F.value = {
          start: he == null ? void 0 : he.copy(),
          end: void 0
        });
    }), hf({
      isDateUnavailable: N,
      startValue: H,
      endValue: Q,
      formatter: Ee,
      modelValue: F,
      placeholder: G,
      disabled: l,
      initialFocus: r,
      pagedNavigation: i,
      weekStartsOn: u,
      weekdayFormat: d,
      fixedWeeks: c,
      numberOfMonths: f,
      readonly: s,
      preventDeselect: v,
      fullCalendarLabel: z,
      headingValue: K,
      isInvalid: be,
      isDateDisabled: L,
      highlightedRange: Ie,
      focusedValue: A,
      lastPressedDateValue: V,
      isSelected: de,
      isSelectionEnd: We,
      isSelectionStart: Ae,
      isNextButtonDisabled: Z,
      isPrevButtonDisabled: Y,
      isOutsideVisibleView: se,
      nextPage: fe,
      prevPage: xe,
      parentElement: I,
      onPlaceholderChange: J,
      locale: $,
      dir: M,
      isHighlightedStart: Et,
      isHighlightedEnd: yr
    }), le(() => {
      r.value && Pl(I.value);
    }), (he, Ne) => (b(), S(o(O), {
      ref_key: "primitiveElement",
      ref: D,
      as: he.as,
      "as-child": he.asChild,
      role: "application",
      "aria-label": o(z),
      "data-readonly": o(s) ? "" : void 0,
      "data-disabled": o(l) ? "" : void 0,
      "data-invalid": o(be) ? "" : void 0,
      dir: o(M)
    }, {
      default: y(() => [
        Ye("div", vf, [
          Ye("div", mf, De(o(z)), 1)
        ]),
        w(he.$slots, "default", {
          date: o(G),
          grid: o(re),
          weekDays: o(X),
          weekStartsOn: o(u),
          locale: o($),
          fixedWeeks: o(c)
        })
      ]),
      _: 3
    }, 8, ["as", "as-child", "aria-label", "data-readonly", "data-disabled", "data-invalid", "dir"]));
  }
}), gf = /* @__PURE__ */ x({
  __name: "RangeCalendarHeader",
  props: {
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), bf = /* @__PURE__ */ x({
  __name: "RangeCalendarHeading",
  props: {
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = na();
    return (n, l) => (b(), S(o(O), k(t, {
      "data-disabled": o(e).disabled.value ? "" : void 0
    }), {
      default: y(() => [
        w(n.$slots, "default", {
          headingValue: o(e).headingValue.value
        }, () => [
          ye(De(o(e).headingValue.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["data-disabled"]));
  }
}), Cf = /* @__PURE__ */ x({
  __name: "RangeCalendarGrid",
  props: {
    asChild: { type: Boolean },
    as: { default: "table" }
  },
  setup(a) {
    const t = a, e = na(), n = B(() => e.disabled.value ? !0 : void 0), l = B(() => e.readonly.value ? !0 : void 0);
    return (s, r) => (b(), S(o(O), k(t, {
      tabindex: "-1",
      role: "grid",
      "aria-readonly": l.value,
      "aria-disabled": n.value,
      "data-readonly": l.value && "",
      "data-disabled": n.value && ""
    }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-readonly", "aria-disabled", "data-readonly", "data-disabled"]));
  }
}), wf = /* @__PURE__ */ x({
  __name: "RangeCalendarCell",
  props: {
    date: {},
    asChild: { type: Boolean },
    as: { default: "td" }
  },
  setup(a) {
    const t = na();
    return (e, n) => {
      var l, s;
      return b(), S(o(O), {
        as: e.as,
        "as-child": e.asChild,
        role: "gridcell",
        "aria-selected": o(t).isSelected(e.date) ? !0 : void 0,
        "aria-disabled": o(t).isDateDisabled(e.date) || ((s = (l = o(t)).isDateUnavailable) == null ? void 0 : s.call(l, e.date)),
        "data-disabled": o(t).isDateDisabled(e.date) ? "" : void 0
      }, {
        default: y(() => [
          w(e.$slots, "default")
        ]),
        _: 3
      }, 8, ["as", "as-child", "aria-selected", "aria-disabled", "data-disabled"]);
    };
  }
}), _f = /* @__PURE__ */ x({
  __name: "RangeCalendarHeadCell",
  props: {
    asChild: { type: Boolean },
    as: { default: "th" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), xf = /* @__PURE__ */ x({
  __name: "RangeCalendarNext",
  props: {
    step: {},
    nextPage: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = B(() => n.disabled.value || n.isNextButtonDisabled(t.step, t.nextPage)), n = na();
    return (l, s) => (b(), S(o(O), k(t, {
      "aria-label": "Next page",
      type: l.as === "button" ? "button" : void 0,
      "aria-disabled": e.value || void 0,
      "data-disabled": e.value || void 0,
      disabled: e.value,
      onClick: s[0] || (s[0] = (r) => o(n).nextPage(t.step, t.nextPage))
    }), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Next page")
        ])
      ]),
      _: 3
    }, 16, ["type", "aria-disabled", "data-disabled", "disabled"]));
  }
}), Sf = /* @__PURE__ */ x({
  __name: "RangeCalendarPrev",
  props: {
    step: {},
    prevPage: {},
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = B(() => n.disabled.value || n.isPrevButtonDisabled(t.step, t.prevPage)), n = na();
    return (l, s) => (b(), S(o(O), k(t, {
      "aria-label": "Previous page",
      type: l.as === "button" ? "button" : void 0,
      "aria-disabled": e.value || void 0,
      "data-disabled": e.value || void 0,
      disabled: e.value,
      onClick: s[0] || (s[0] = (r) => o(n).prevPage(t.step, t.prevPage))
    }), {
      default: y(() => [
        w(l.$slots, "default", {}, () => [
          ye("Prev page")
        ])
      ]),
      _: 3
    }, 16, ["type", "aria-disabled", "data-disabled", "disabled"]));
  }
}), Ef = /* @__PURE__ */ x({
  __name: "RangeCalendarGridHead",
  props: {
    asChild: { type: Boolean },
    as: { default: "thead" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), k(t, { "aria-hidden": "true" }), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Pf = /* @__PURE__ */ x({
  __name: "RangeCalendarGridBody",
  props: {
    asChild: { type: Boolean },
    as: { default: "tbody" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Df = /* @__PURE__ */ x({
  __name: "RangeCalendarGridRow",
  props: {
    asChild: { type: Boolean },
    as: { default: "tr" }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), $f = /* @__PURE__ */ x({
  __name: "RangeCalendarCellTrigger",
  props: {
    day: {},
    month: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = na(), n = nt(), { primitiveElement: l, currentElement: s } = Re(), r = B(() => e.formatter.custom(ze(t.day), {
      weekday: "long",
      month: "long",
      day: "numeric",
      year: "numeric"
    })), i = B(() => e.isDateDisabled(t.day)), u = B(() => {
      var V;
      return (V = e.isDateUnavailable) == null ? void 0 : V.call(e, t.day);
    }), d = B(() => e.isSelected(t.day)), c = B(() => e.isSelectionStart(t.day)), f = B(() => e.isSelectionEnd(t.day)), v = B(() => e.isHighlightedStart(t.day)), p = B(() => e.isHighlightedEnd(t.day)), g = B(() => e.highlightedRange.value ? Ar(t.day, e.highlightedRange.value.start, e.highlightedRange.value.end) : !1), m = "[data-radix-vue-calendar-cell-trigger]:not([data-disabled]):not([data-outside-view]):not([data-outside-visible-view])", _ = B(() => bl(t.day, Hn())), C = B(() => !Cl(t.day, t.month)), $ = B(
      () => e.isOutsideVisibleView(t.day)
    ), h = B(() => t.day.day.toLocaleString(e.locale.value)), E = B(() => !e.disabled.value && Oe(t.day, e.placeholder.value));
    function P(V, A) {
      var F;
      if (!e.readonly.value && !(e.isDateDisabled(A) || (F = e.isDateUnavailable) != null && F.call(e, A))) {
        if (e.lastPressedDateValue.value = A.copy(), e.startValue.value && e.highlightedRange.value === null) {
          if (Oe(A, e.startValue.value) && !e.preventDeselect.value && !e.endValue.value) {
            e.startValue.value = void 0, e.onPlaceholderChange(A);
            return;
          } else if (!e.endValue.value) {
            V.preventDefault(), e.lastPressedDateValue.value && Oe(e.lastPressedDateValue.value, A) && (e.startValue.value = A.copy());
            return;
          }
        }
        if (e.startValue.value && e.endValue.value && Oe(e.endValue.value, A) && !e.preventDeselect.value) {
          e.startValue.value = void 0, e.endValue.value = void 0, e.onPlaceholderChange(A);
          return;
        }
        e.startValue.value ? e.endValue.value ? e.endValue.value && e.startValue.value && (e.endValue.value = void 0, e.startValue.value = A.copy()) : e.endValue.value = A.copy() : e.startValue.value = A.copy();
      }
    }
    function D(V) {
      P(V, t.day);
    }
    function I() {
      var V;
      e.isDateDisabled(t.day) || (V = e.isDateUnavailable) != null && V.call(e, t.day) || (e.focusedValue.value = t.day.copy());
    }
    function M(V) {
      V.preventDefault(), V.stopPropagation();
      const A = e.parentElement.value, F = A ? Array.from(A.querySelectorAll(m)) : [];
      let H = F.indexOf(s.value);
      const Q = 7, G = e.dir.value === "rtl" ? -1 : 1;
      switch (V.code) {
        case n.ARROW_RIGHT:
          H += G;
          break;
        case n.ARROW_LEFT:
          H -= G;
          break;
        case n.ARROW_UP:
          H -= Q;
          break;
        case n.ARROW_DOWN:
          H += Q;
          break;
        case n.ENTER:
        case n.SPACE_CODE:
          P(V, t.day);
          return;
        default:
          return;
      }
      if (H >= 0 && H < F.length) {
        F[H].focus();
        return;
      }
      if (H < 0) {
        if (e.isPrevButtonDisabled("month"))
          return;
        e.prevPage(), oe(() => {
          const J = A ? Array.from(A.querySelectorAll(m)) : [];
          if (!e.pagedNavigation.value) {
            const z = Ze(e.placeholder.value);
            J[z - Math.abs(H)].focus();
            return;
          }
          J[J.length - Math.abs(H)].focus();
        });
        return;
      }
      if (H >= F.length) {
        if (e.isNextButtonDisabled("month"))
          return;
        e.nextPage(), oe(() => {
          const J = A ? Array.from(A.querySelectorAll(m)) : [];
          if (!e.pagedNavigation.value) {
            const z = Ze(e.placeholder.value.add({ months: e.numberOfMonths.value - 1 }));
            J[J.length - z + H - F.length].focus();
            return;
          }
          J[H - F.length].focus();
        });
      }
    }
    return (V, A) => (b(), S(o(O), k({
      ref_key: "primitiveElement",
      ref: l
    }, t, {
      role: "button",
      "aria-label": r.value,
      "data-radix-vue-calendar-cell-trigger": "",
      "aria-selected": d.value ? !0 : void 0,
      "aria-disabled": i.value || u.value ? !0 : void 0,
      "data-highlighted": g.value ? "" : void 0,
      "data-selection-start": c.value ? !0 : void 0,
      "data-selection-end": f.value ? !0 : void 0,
      "data-highlighted-start": v.value ? !0 : void 0,
      "data-highlighted-end": p.value ? !0 : void 0,
      "data-selected": d.value ? !0 : void 0,
      "data-outside-visible-view": $.value ? "" : void 0,
      "data-value": V.day.toString(),
      "data-disabled": i.value ? "" : void 0,
      "data-unavailable": u.value ? "" : void 0,
      "data-today": _.value ? "" : void 0,
      "data-outside-view": C.value ? "" : void 0,
      "data-focused": E.value ? "" : void 0,
      tabindex: E.value ? 0 : C.value || i.value ? void 0 : -1,
      onClick: D,
      onFocusin: I,
      onMouseenter: I,
      onKeydown: ie(M, ["up", "down", "left", "right", "enter", "space"])
    }), {
      default: y(() => [
        w(V.$slots, "default", { dayValue: h.value }, () => [
          ye(De(h.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["aria-label", "aria-selected", "aria-disabled", "data-highlighted", "data-selection-start", "data-selection-end", "data-highlighted-start", "data-highlighted-end", "data-selected", "data-outside-visible-view", "data-value", "data-disabled", "data-unavailable", "data-today", "data-outside-view", "data-focused", "tabindex"]));
  }
}), [Ue, Bf] = te("ScrollAreaRoot"), Vy = /* @__PURE__ */ x({
  __name: "ScrollAreaRoot",
  props: {
    type: { default: "hover" },
    dir: {},
    scrollHideDelay: { default: 600 },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a, { expose: t }) {
    const e = a, n = T(0), l = T(0), s = T(), r = T(), i = T(), u = T(), d = T(!1), c = T(!1), { type: f, dir: v, scrollHideDelay: p } = ae(e), g = we(v);
    function m() {
      var h;
      (h = s.value) == null || h.scrollTo({
        top: 0
      });
    }
    function _() {
      var h;
      (h = s.value) == null || h.scrollTo({
        top: 0,
        left: 0
      });
    }
    t({
      /** Viewport element within ScrollArea */
      viewport: s,
      /** Scroll viewport to top */
      scrollTop: m,
      /** Scroll viewport to top-left */
      scrollTopLeft: _
    });
    const { forwardRef: C, currentElement: $ } = R();
    return Bf({
      type: f,
      dir: g,
      scrollHideDelay: p,
      scrollArea: $,
      viewport: s,
      onViewportChange: (h) => {
        s.value = h || void 0;
      },
      content: r,
      onContentChange: (h) => {
        r.value = h;
      },
      scrollbarX: i,
      scrollbarXEnabled: d,
      scrollbarY: u,
      scrollbarYEnabled: c,
      onScrollbarXChange: (h) => {
        i.value = h || void 0;
      },
      onScrollbarYChange: (h) => {
        u.value = h || void 0;
      },
      onScrollbarXEnabledChange: (h) => {
        d.value = h;
      },
      onScrollbarYEnabledChange: (h) => {
        c.value = h;
      },
      onCornerWidthChange: (h) => {
        n.value = h;
      },
      onCornerHeightChange: (h) => {
        l.value = h;
      }
    }), (h, E) => (b(), S(o(O), {
      ref: o(C),
      "as-child": e.asChild,
      as: h.as,
      dir: o(g),
      style: Me({
        position: "relative",
        // Pass corner sizes as CSS vars to reduce re-renders of context consumers
        "--radix-scroll-area-corner-width": `${n.value}px`,
        "--radix-scroll-area-corner-height": `${l.value}px`
      })
    }, {
      default: y(() => [
        w(h.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as", "dir", "style"]));
  }
}), Fy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ScrollAreaViewport",
  props: {
    nonce: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a, { expose: t }) {
    const e = a, { nonce: n } = ae(e), l = Ja(n), s = Ue(), r = T();
    le(() => {
      s.onViewportChange(r.value), s.onContentChange(u.value);
    }), t({
      viewportElement: r
    });
    const { forwardRef: i, currentElement: u } = R();
    return (d, c) => (b(), ve(_e, null, [
      Ye("div", k({
        ref_key: "viewportElement",
        ref: r,
        "data-radix-scroll-area-viewport": "",
        style: {
          /**
           * We don't support `visible` because the intention is to have at least one scrollbar
           * if this component is used and `visible` will behave like `auto` in that case
           * https://developer.mozilla.org/en-US/docs/Web/CSS/overflowed#description
           *
           * We don't handle `auto` because the intention is for the native implementation
           * to be hidden if using this component. We just want to ensure the node is scrollable
           * so could have used either `scroll` or `auto` here. We picked `scroll` to prevent
           * the browser from having to work out whether to render native scrollbars or not,
           * we tell it to with the intention of hiding them in CSS.
           */
          overflowX: o(s).scrollbarXEnabled.value ? "scroll" : "hidden",
          overflowY: o(s).scrollbarYEnabled.value ? "scroll" : "hidden"
        }
      }, d.$attrs, { tabindex: 0 }), [
        q(o(O), {
          ref: o(i),
          style: Me({
            /**
             * When horizontal scrollbar is visible: this element should be at least
             * as wide as its children for size calculations to work correctly.
             *
             * When horizontal scrollbar is NOT visible: this element's width should
             * be constrained by the parent container to enable `text-overflow: ellipsis`
             */
            minWidth: o(s).scrollbarXEnabled.value ? "fit-content" : void 0
          }),
          "as-child": e.asChild,
          as: d.as
        }, {
          default: y(() => [
            w(d.$slots, "default")
          ]),
          _: 3
        }, 8, ["style", "as-child", "as"])
      ], 16),
      q(o(O), {
        as: "style",
        nonce: o(l)
      }, {
        default: y(() => [
          ye(" /* Hide scrollbars cross-browser and enable momentum scroll for touch devices */ [data-radix-scroll-area-viewport] { scrollbar-width:none; -ms-overflow-style:none; -webkit-overflow-scrolling:touch; } [data-radix-scroll-area-viewport]::-webkit-scrollbar { display:none; } ")
        ]),
        _: 1
      }, 8, ["nonce"])
    ], 64));
  }
});
function $s(a, t) {
  return (e) => {
    if (a[0] === a[1] || t[0] === t[1])
      return t[0];
    const n = (t[1] - t[0]) / (a[1] - a[0]);
    return t[0] + n * (e - a[0]);
  };
}
function ln(a) {
  const t = Bs(a.viewport, a.content), e = a.scrollbar.paddingStart + a.scrollbar.paddingEnd, n = (a.scrollbar.size - e) * t;
  return Math.max(n, 18);
}
function Bs(a, t) {
  const e = a / t;
  return Number.isNaN(e) ? 0 : e;
}
function If(a, t = () => {
}) {
  let e = { left: a.scrollLeft, top: a.scrollTop }, n = 0;
  return function l() {
    const s = { left: a.scrollLeft, top: a.scrollTop }, r = e.left !== s.left, i = e.top !== s.top;
    (r || i) && t(), e = s, n = window.requestAnimationFrame(l);
  }(), () => window.cancelAnimationFrame(n);
}
function tl(a, t, e = "ltr") {
  const n = ln(t), l = t.scrollbar.paddingStart + t.scrollbar.paddingEnd, s = t.scrollbar.size - l, r = t.content - t.viewport, i = s - n, u = e === "ltr" ? [0, r] : [r * -1, 0], d = Ut(
    a,
    u[0],
    u[1]
  );
  return $s([0, r], [0, i])(d);
}
function Ra(a) {
  return a ? Number.parseInt(a, 10) : 0;
}
function Tf(a, t, e, n = "ltr") {
  const l = ln(e), s = l / 2, r = t || s, i = l - r, u = e.scrollbar.paddingStart + r, d = e.scrollbar.size - e.scrollbar.paddingEnd - i, c = e.content - e.viewport, f = n === "ltr" ? [0, c] : [c * -1, 0];
  return $s(
    [u, d],
    f
  )(a);
}
function al(a, t) {
  return a > 0 && a < t;
}
const Is = /* @__PURE__ */ x({
  __name: "ScrollAreaScrollbarImpl",
  props: {
    isHorizontal: { type: Boolean }
  },
  emits: ["onDragScroll", "onWheelScroll", "onThumbPointerDown"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = Ue(), s = sn(), r = rn(), { forwardRef: i, currentElement: u } = R(), d = T(""), c = T();
    function f(C) {
      var $, h;
      if (c.value) {
        const E = C.clientX - (($ = c.value) == null ? void 0 : $.left), P = C.clientY - ((h = c.value) == null ? void 0 : h.top);
        n("onDragScroll", { x: E, y: P });
      }
    }
    function v(C) {
      C.button === 0 && (C.target.setPointerCapture(C.pointerId), c.value = u.value.getBoundingClientRect(), d.value = document.body.style.webkitUserSelect, document.body.style.webkitUserSelect = "none", l.viewport && (l.viewport.value.style.scrollBehavior = "auto"), f(C));
    }
    function p(C) {
      f(C);
    }
    function g(C) {
      const $ = C.target;
      $.hasPointerCapture(C.pointerId) && $.releasePointerCapture(C.pointerId), document.body.style.webkitUserSelect = d.value, l.viewport && (l.viewport.value.style.scrollBehavior = ""), c.value = void 0;
    }
    function m(C) {
      var P;
      const $ = C.target, h = (P = u.value) == null ? void 0 : P.contains($), E = s.sizes.value.content - s.sizes.value.viewport;
      h && s.handleWheelScroll(C, E);
    }
    le(() => {
      document.addEventListener("wheel", m, { passive: !1 });
    }), Be(() => {
      document.removeEventListener("wheel", m);
    });
    function _() {
      var C, $, h, E, P;
      u.value && (e.isHorizontal ? s.handleSizeChange({
        content: ((C = l.viewport.value) == null ? void 0 : C.scrollWidth) ?? 0,
        viewport: (($ = l.viewport.value) == null ? void 0 : $.offsetWidth) ?? 0,
        scrollbar: {
          size: u.value.clientWidth ?? 0,
          paddingStart: Ra(getComputedStyle(u.value).paddingLeft),
          paddingEnd: Ra(getComputedStyle(u.value).paddingRight)
        }
      }) : s.handleSizeChange({
        content: ((h = l.viewport.value) == null ? void 0 : h.scrollHeight) ?? 0,
        viewport: ((E = l.viewport.value) == null ? void 0 : E.offsetHeight) ?? 0,
        scrollbar: {
          size: ((P = u.value) == null ? void 0 : P.clientHeight) ?? 0,
          paddingStart: Ra(getComputedStyle(u.value).paddingLeft),
          paddingEnd: Ra(getComputedStyle(u.value).paddingRight)
        }
      }));
    }
    return tt(u, _), tt(l.content, _), (C, $) => (b(), S(o(O), {
      ref: o(i),
      style: { position: "absolute" },
      "data-scrollbarimpl": "",
      as: o(r).as.value,
      "as-child": o(r).asChild.value,
      onPointerdown: v,
      onPointermove: p,
      onPointerup: g
    }, {
      default: y(() => [
        w(C.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child"]));
  }
}), Rf = /* @__PURE__ */ x({
  __name: "ScrollAreaScrollbarX",
  setup(a) {
    const t = Ue(), e = sn(), { forwardRef: n, currentElement: l } = R();
    le(() => {
      l.value && t.onScrollbarXChange(l.value);
    });
    const s = B(() => e.sizes.value);
    return (r, i) => (b(), S(Is, {
      ref: o(n),
      "is-horizontal": !0,
      "data-orientation": "horizontal",
      style: Me({
        bottom: 0,
        left: o(t).dir.value === "rtl" ? "var(--radix-scroll-area-corner-width)" : 0,
        right: o(t).dir.value === "ltr" ? "var(--radix-scroll-area-corner-width)" : 0,
        "--radix-scroll-area-thumb-width": s.value ? `${o(ln)(s.value)}px` : void 0
      }),
      onOnDragScroll: i[0] || (i[0] = (u) => o(e).onDragScroll(u.x))
    }, {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 8, ["style"]));
  }
}), Af = /* @__PURE__ */ x({
  __name: "ScrollAreaScrollbarY",
  setup(a) {
    const t = Ue(), e = sn(), { forwardRef: n, currentElement: l } = R();
    le(() => {
      l.value && t.onScrollbarYChange(l.value);
    });
    const s = B(() => e.sizes.value);
    return (r, i) => (b(), S(Is, {
      ref: o(n),
      "is-horizontal": !1,
      "data-orientation": "vertical",
      style: Me({
        top: 0,
        right: o(t).dir.value === "ltr" ? 0 : void 0,
        left: o(t).dir.value === "rtl" ? 0 : void 0,
        bottom: "var(--radix-scroll-area-corner-height)",
        "--radix-scroll-area-thumb-height": s.value ? `${o(ln)(s.value)}px` : void 0
      }),
      onOnDragScroll: i[0] || (i[0] = (u) => o(e).onDragScroll(u.y))
    }, {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 8, ["style"]));
  }
}), [sn, Of] = te("ScrollAreaScrollbarVisible"), Bo = /* @__PURE__ */ x({
  __name: "ScrollAreaScrollbarVisible",
  setup(a) {
    const t = Ue(), e = rn(), { forwardRef: n } = R(), l = T({
      content: 0,
      viewport: 0,
      scrollbar: { size: 0, paddingStart: 0, paddingEnd: 0 }
    }), s = B(() => {
      const C = Bs(l.value.viewport, l.value.content);
      return C > 0 && C < 1;
    }), r = T(), i = T(0);
    function u(C, $) {
      if (p.value) {
        const h = t.viewport.value.scrollLeft + C.deltaY;
        t.viewport.value.scrollLeft = h, al(h, $) && C.preventDefault();
      } else {
        const h = t.viewport.value.scrollTop + C.deltaY;
        t.viewport.value.scrollTop = h, al(h, $) && C.preventDefault();
      }
    }
    function d(C, $) {
      p.value ? i.value = $.x : i.value = $.y;
    }
    function c(C) {
      i.value = 0;
    }
    function f(C) {
      l.value = C;
    }
    function v(C, $) {
      return Tf(
        C,
        i.value,
        l.value,
        $
      );
    }
    const p = B(
      () => e.isHorizontal.value
    );
    function g(C) {
      p.value ? t.viewport.value.scrollLeft = v(
        C,
        t.dir.value
      ) : t.viewport.value.scrollTop = v(C);
    }
    function m() {
      if (p.value) {
        if (t.viewport.value && r.value) {
          const C = t.viewport.value.scrollLeft, $ = tl(
            C,
            l.value,
            t.dir.value
          );
          r.value.style.transform = `translate3d(${$}px, 0, 0)`;
        }
      } else if (t.viewport.value && r.value) {
        const C = t.viewport.value.scrollTop, $ = tl(C, l.value);
        r.value.style.transform = `translate3d(0, ${$}px, 0)`;
      }
    }
    function _(C) {
      r.value = C;
    }
    return Of({
      sizes: l,
      hasThumb: s,
      handleWheelScroll: u,
      handleThumbDown: d,
      handleThumbUp: c,
      handleSizeChange: f,
      onThumbPositionChange: m,
      onThumbChange: _,
      onDragScroll: g
    }), (C, $) => p.value ? (b(), S(Rf, k({ key: 0 }, C.$attrs, { ref: o(n) }), {
      default: y(() => [
        w(C.$slots, "default")
      ]),
      _: 3
    }, 16)) : (b(), S(Af, k({ key: 1 }, C.$attrs, { ref: o(n) }), {
      default: y(() => [
        w(C.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ts = /* @__PURE__ */ x({
  __name: "ScrollAreaScrollbarAuto",
  props: {
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = Ue(), e = rn(), { forwardRef: n } = R(), l = T(!1), s = jn(() => {
      if (t.viewport.value) {
        const r = t.viewport.value.offsetWidth < t.viewport.value.scrollWidth, i = t.viewport.value.offsetHeight < t.viewport.value.scrollHeight;
        l.value = e.isHorizontal.value ? r : i;
      }
    }, 10);
    return le(() => s()), tt(t.viewport, s), tt(t.content, s), (r, i) => (b(), S(o(Pe), {
      present: r.forceMount || l.value
    }, {
      default: y(() => [
        q(Bo, k(r.$attrs, {
          ref: o(n),
          "data-state": l.value ? "visible" : "hidden"
        }), {
          default: y(() => [
            w(r.$slots, "default")
          ]),
          _: 3
        }, 16, ["data-state"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), kf = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ScrollAreaScrollbarHover",
  props: {
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = Ue(), { forwardRef: e } = R();
    let n;
    const l = T(!1);
    function s() {
      window.clearTimeout(n), l.value = !0;
    }
    function r() {
      n = window.setTimeout(() => {
        l.value = !1;
      }, t.scrollHideDelay.value);
    }
    return le(() => {
      const i = t.scrollArea.value;
      i && (i.addEventListener("pointerenter", s), i.addEventListener("pointerleave", r));
    }), Be(() => {
      const i = t.scrollArea.value;
      i && (window.clearTimeout(n), i.removeEventListener("pointerenter", s), i.removeEventListener("pointerleave", r));
    }), (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || l.value
    }, {
      default: y(() => [
        q(Ts, k(i.$attrs, {
          ref: o(e),
          "data-state": l.value ? "visible" : "hidden"
        }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16, ["data-state"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Mf = /* @__PURE__ */ x({
  __name: "ScrollAreaScrollbarScroll",
  props: {
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = Ue(), e = rn(), { forwardRef: n } = R(), { state: l, dispatch: s } = zl("hidden", {
      hidden: {
        SCROLL: "scrolling"
      },
      scrolling: {
        SCROLL_END: "idle",
        POINTER_ENTER: "interacting"
      },
      interacting: {
        SCROLL: "interacting",
        POINTER_LEAVE: "idle"
      },
      idle: {
        HIDE: "hidden",
        SCROLL: "scrolling",
        POINTER_ENTER: "interacting"
      }
    });
    Ce((i) => {
      if (l.value === "idle") {
        const u = window.setTimeout(
          () => s("HIDE"),
          t.scrollHideDelay.value
        );
        i(() => {
          window.clearTimeout(u);
        });
      }
    });
    const r = jn(() => s("SCROLL_END"), 100);
    return Ce((i) => {
      const u = t.viewport.value, d = e.isHorizontal.value ? "scrollLeft" : "scrollTop";
      if (u) {
        let c = u[d];
        const f = () => {
          const v = u[d];
          c !== v && (s("SCROLL"), r()), c = v;
        };
        u.addEventListener("scroll", f), i(() => {
          u.removeEventListener("scroll", f);
        });
      }
    }), (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(l) !== "hidden"
    }, {
      default: y(() => [
        q(Bo, k(i.$attrs, { ref: o(n) }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), [rn, Vf] = te("ScrollAreaScrollbar"), Ny = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ScrollAreaScrollbar",
  props: {
    orientation: { default: "vertical" },
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), n = Ue(), l = B(() => t.orientation === "horizontal");
    ee(
      l,
      () => {
        l.value ? n.onScrollbarXEnabledChange(!0) : n.onScrollbarYEnabledChange(!0);
      },
      { immediate: !0 }
    ), Be(() => {
      n.onScrollbarXEnabledChange(!1), n.onScrollbarYEnabledChange(!1);
    });
    const { orientation: s, forceMount: r, asChild: i, as: u } = ae(t);
    return Vf({
      orientation: s,
      forceMount: r,
      isHorizontal: l,
      as: u,
      asChild: i
    }), (d, c) => o(n).type.value === "hover" ? (b(), S(kf, k({ key: 0 }, d.$attrs, {
      ref: o(e),
      "force-mount": o(r)
    }), {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 16, ["force-mount"])) : o(n).type.value === "scroll" ? (b(), S(Mf, k({ key: 1 }, d.$attrs, {
      ref: o(e),
      "force-mount": o(r)
    }), {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 16, ["force-mount"])) : o(n).type.value === "auto" ? (b(), S(Ts, k({ key: 2 }, d.$attrs, {
      ref: o(e),
      "force-mount": o(r)
    }), {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 16, ["force-mount"])) : o(n).type.value === "always" ? (b(), S(Bo, k({ key: 3 }, d.$attrs, {
      ref: o(e),
      "data-state": "visible"
    }), {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
}), Ly = /* @__PURE__ */ x({
  __name: "ScrollAreaThumb",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Ue(), n = sn();
    function l(v) {
      const g = v.target.getBoundingClientRect(), m = v.clientX - g.left, _ = v.clientY - g.top;
      n.handleThumbDown(v, { x: m, y: _ });
    }
    function s(v) {
      n.handleThumbUp(v);
    }
    const { forwardRef: r, currentElement: i } = R(), u = T(), d = B(() => e.viewport.value);
    function c() {
      if (!u.value) {
        const v = If(
          d.value,
          n.onThumbPositionChange
        );
        u.value = v, n.onThumbPositionChange();
      }
    }
    const f = B(() => n.sizes.value);
    return bi(f, () => {
      n.onThumbChange(i.value), d.value && (n.onThumbPositionChange(), d.value.addEventListener("scroll", c));
    }), Be(() => {
      var v;
      d.value.removeEventListener("scroll", c), (v = e.viewport.value) == null || v.removeEventListener("scroll", c);
    }), (v, p) => (b(), S(o(O), {
      ref: o(r),
      "data-state": o(n).hasThumb ? "visible" : "hidden",
      style: {
        width: "var(--radix-scroll-area-thumb-width)",
        height: "var(--radix-scroll-area-thumb-height)"
      },
      "as-child": t.asChild,
      as: v.as,
      onPointerdown: l,
      onPointerup: s
    }, {
      default: y(() => [
        w(v.$slots, "default")
      ]),
      _: 3
    }, 8, ["data-state", "as-child", "as"]));
  }
}), Ff = /* @__PURE__ */ x({
  __name: "ScrollAreaCornerImpl",
  setup(a) {
    const t = Ue(), e = T(0), n = T(0), l = B(() => !!e.value && !!n.value);
    function s() {
      var u;
      const i = ((u = t.scrollbarX.value) == null ? void 0 : u.offsetHeight) || 0;
      t.onCornerHeightChange(i), n.value = i;
    }
    function r() {
      var u;
      const i = ((u = t.scrollbarY.value) == null ? void 0 : u.offsetWidth) || 0;
      t.onCornerWidthChange(i), e.value = i;
    }
    return tt(t.scrollbarX.value, s), tt(t.scrollbarY.value, r), ee(() => t.scrollbarX.value, s), ee(() => t.scrollbarY.value, r), (i, u) => {
      var d;
      return l.value ? (b(), S(o(O), k({
        key: 0,
        style: {
          width: `${e.value}px`,
          height: `${n.value}px`,
          position: "absolute",
          right: o(t).dir.value === "ltr" ? 0 : void 0,
          left: o(t).dir.value === "rtl" ? 0 : void 0,
          bottom: 0
        }
      }, (d = i.$parent) == null ? void 0 : d.$props), {
        default: y(() => [
          w(i.$slots, "default")
        ]),
        _: 3
      }, 16, ["style"])) : ce("", !0);
    };
  }
}), zy = /* @__PURE__ */ x({
  __name: "ScrollAreaCorner",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), n = Ue(), l = B(
      () => !!n.scrollbarX.value && !!n.scrollbarY.value
    ), s = B(
      () => n.type.value !== "scroll" && l.value
    );
    return (r, i) => s.value ? (b(), S(Ff, k({ key: 0 }, t, { ref: o(e) }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
}), Nf = ["default-value"], Lf = /* @__PURE__ */ x({
  __name: "BubbleSelect",
  props: {
    autocomplete: {},
    autofocus: { type: Boolean },
    disabled: { type: Boolean },
    form: {},
    multiple: { type: Boolean },
    name: {},
    required: { type: Boolean },
    size: {},
    value: {}
  },
  setup(a) {
    const t = a, { value: e } = ae(t), n = T();
    return (l, s) => (b(), S(o(Jt), { "as-child": "" }, {
      default: y(() => [
        ja(Ye("select", k({
          ref_key: "selectElement",
          ref: n
        }, t, {
          "onUpdate:modelValue": s[0] || (s[0] = (r) => et(e) ? e.value = r : null),
          "default-value": o(e)
        }), [
          w(l.$slots, "default")
        ], 16, Nf), [
          [Er, o(e)]
        ])
      ]),
      _: 3
    }));
  }
}), zf = {
  key: 0,
  value: ""
}, [xt, Rs] = te("SelectRoot"), [Kf, Hf] = te("SelectRoot"), Ky = /* @__PURE__ */ x({
  __name: "SelectRoot",
  props: {
    open: { type: Boolean, default: void 0 },
    defaultOpen: { type: Boolean },
    defaultValue: { default: "" },
    modelValue: { default: void 0 },
    dir: {},
    name: {},
    autocomplete: {},
    disabled: { type: Boolean },
    required: { type: Boolean }
  },
  emits: ["update:modelValue", "update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: e.modelValue === void 0
    }), s = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    }), r = T(), i = T(), u = T({
      x: 0,
      y: 0
    }), d = T(!1), { required: c, disabled: f, dir: v } = ae(e), p = we(v);
    Rs({
      triggerElement: r,
      onTriggerChange: (C) => {
        r.value = C;
      },
      valueElement: i,
      onValueElementChange: (C) => {
        i.value = C;
      },
      valueElementHasChildren: d,
      onValueElementHasChildrenChange: (C) => {
        d.value = C;
      },
      contentId: "",
      modelValue: l,
      onValueChange: (C) => {
        l.value = C;
      },
      open: s,
      required: c,
      onOpenChange: (C) => {
        s.value = C;
      },
      dir: p,
      triggerPointerDownPosRef: u,
      disabled: f
    });
    const g = at(r), m = T(/* @__PURE__ */ new Set()), _ = B(() => Array.from(m.value).map((C) => {
      var $;
      return ($ = C.props) == null ? void 0 : $.value;
    }).join(";"));
    return Hf({
      onNativeOptionAdd: (C) => {
        m.value.add(C);
      },
      onNativeOptionRemove: (C) => {
        m.value.delete(C);
      }
    }), (C, $) => (b(), S(o(kt), null, {
      default: y(() => [
        w(C.$slots, "default", {
          modelValue: o(l),
          open: o(s)
        }),
        o(g) ? (b(), S(Lf, k({ key: _.value }, C.$attrs, {
          "aria-hidden": "true",
          tabindex: "-1",
          required: o(c),
          name: C.name,
          autocomplete: C.autocomplete,
          disabled: o(f),
          value: o(l),
          onChange: $[0] || ($[0] = (h) => l.value = h.target.value)
        }), {
          default: y(() => [
            o(l) === void 0 ? (b(), ve("option", zf)) : ce("", !0),
            (b(!0), ve(_e, null, ma(Array.from(m.value), (h) => (b(), S(Xe(h), k({ ref_for: !0 }, h.props, {
              key: h.key ?? ""
            }), null, 16))), 128))
          ]),
          _: 1
        }, 16, ["required", "name", "autocomplete", "disabled", "value"])) : ce("", !0)
      ]),
      _: 3
    }));
  }
}), Wf = [" ", "Enter", "ArrowUp", "ArrowDown"], jf = [" ", "Enter"], qe = 10;
function As(a) {
  return a === "" || ht(a);
}
const Hy = /* @__PURE__ */ x({
  __name: "SelectTrigger",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = xt(), n = B(() => {
      var p;
      return ((p = e.disabled) == null ? void 0 : p.value) || t.disabled;
    }), { forwardRef: l, currentElement: s } = R();
    e.contentId || (e.contentId = ge(void 0, "radix-vue-select-content")), le(() => {
      e.triggerElement = s;
    });
    const { injectCollection: r } = Fe(), i = r(), { search: u, handleTypeaheadSearch: d, resetTypeahead: c } = ba(i);
    function f() {
      n.value || (e.onOpenChange(!0), c());
    }
    function v(p) {
      f(), e.triggerPointerDownPosRef.value = {
        x: Math.round(p.pageX),
        y: Math.round(p.pageY)
      };
    }
    return (p, g) => (b(), S(o(Mt), { "as-child": "" }, {
      default: y(() => {
        var m, _, C, $;
        return [
          q(o(O), {
            ref: o(l),
            role: "combobox",
            type: p.as === "button" ? "button" : void 0,
            "aria-controls": o(e).contentId,
            "aria-expanded": o(e).open.value || !1,
            "aria-required": (m = o(e).required) == null ? void 0 : m.value,
            "aria-autocomplete": "none",
            disabled: n.value,
            dir: (_ = o(e)) == null ? void 0 : _.dir.value,
            "data-state": (C = o(e)) != null && C.open.value ? "open" : "closed",
            "data-disabled": n.value ? "" : void 0,
            "data-placeholder": o(As)(($ = o(e).modelValue) == null ? void 0 : $.value) ? "" : void 0,
            "as-child": p.asChild,
            as: p.as,
            onClick: g[0] || (g[0] = (h) => {
              var E;
              (E = h == null ? void 0 : h.currentTarget) == null || E.focus();
            }),
            onPointerdown: g[1] || (g[1] = (h) => {
              if (h.pointerType === "touch")
                return h.preventDefault();
              const E = h.target;
              E.hasPointerCapture(h.pointerId) && E.releasePointerCapture(h.pointerId), h.button === 0 && h.ctrlKey === !1 && (v(h), h.preventDefault());
            }),
            onPointerup: g[2] || (g[2] = ue(
              (h) => {
                h.pointerType === "touch" && v(h);
              },
              ["prevent"]
            )),
            onKeydown: g[3] || (g[3] = (h) => {
              const E = o(u) !== "";
              !(h.ctrlKey || h.altKey || h.metaKey) && h.key.length === 1 && E && h.key === " " || (o(d)(h.key), o(Wf).includes(h.key) && (f(), h.preventDefault()));
            })
          }, {
            default: y(() => [
              w(p.$slots, "default")
            ]),
            _: 3
          }, 8, ["type", "aria-controls", "aria-expanded", "aria-required", "disabled", "dir", "data-state", "data-disabled", "data-placeholder", "as-child", "as"])
        ];
      }),
      _: 3
    }));
  }
}), Wy = /* @__PURE__ */ x({
  __name: "SelectPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [Io, Uf] = te("SelectItemAlignedPosition"), Gf = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "SelectItemAlignedPosition",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["placed"],
  setup(a, { emit: t }) {
    const e = a, n = t, { injectCollection: l } = Fe(), s = xt(), r = St(), i = l(), u = T(!1), d = T(!0), c = T(), { forwardRef: f, currentElement: v } = R(), { viewport: p, selectedItem: g, selectedItemText: m, focusSelectedItem: _ } = r;
    function C() {
      if (s.triggerElement.value && s.valueElement.value && c.value && v.value && (p != null && p.value) && (g != null && g.value) && (m != null && m.value)) {
        const E = s.triggerElement.value.getBoundingClientRect(), P = v.value.getBoundingClientRect(), D = s.valueElement.value.getBoundingClientRect(), I = m.value.getBoundingClientRect();
        if (s.dir.value !== "rtl") {
          const Ee = I.left - P.left, be = D.left - Ee, de = E.left - be, Ie = E.width + de, Ae = Math.max(Ie, P.width), We = window.innerWidth - qe, Et = Ut(be, qe, Math.max(qe, We - Ae));
          c.value.style.minWidth = `${Ie}px`, c.value.style.left = `${Et}px`;
        } else {
          const Ee = P.right - I.right, be = window.innerWidth - D.right - Ee, de = window.innerWidth - E.right - be, Ie = E.width + de, Ae = Math.max(Ie, P.width), We = window.innerWidth - qe, Et = Ut(
            be,
            qe,
            Math.max(qe, We - Ae)
          );
          c.value.style.minWidth = `${Ie}px`, c.value.style.right = `${Et}px`;
        }
        const M = i.value, V = window.innerHeight - qe * 2, A = p.value.scrollHeight, F = window.getComputedStyle(v.value), j = Number.parseInt(
          F.borderTopWidth,
          10
        ), H = Number.parseInt(F.paddingTop, 10), Q = Number.parseInt(
          F.borderBottomWidth,
          10
        ), G = Number.parseInt(
          F.paddingBottom,
          10
        ), J = j + H + A + G + Q, z = Math.min(
          g.value.offsetHeight * 5,
          J
        ), K = window.getComputedStyle(p.value), L = Number.parseInt(K.paddingTop, 10), N = Number.parseInt(
          K.paddingBottom,
          10
        ), Z = E.top + E.height / 2 - qe, Y = V - Z, re = g.value.offsetHeight / 2, X = g.value.offsetTop + re, se = j + H + X, fe = J - se;
        if (se <= Z) {
          const Ee = g.value === M[M.length - 1];
          c.value.style.bottom = "0px";
          const be = v.value.clientHeight - p.value.offsetTop - p.value.offsetHeight, de = Math.max(
            Y,
            re + (Ee ? N : 0) + be + Q
          ), Ie = se + de;
          c.value.style.height = `${Ie}px`;
        } else {
          const Ee = g.value === M[0];
          c.value.style.top = "0px";
          const de = Math.max(
            Z,
            j + p.value.offsetTop + (Ee ? L : 0) + re
          ) + fe;
          c.value.style.height = `${de}px`, p.value.scrollTop = se - Z + p.value.offsetTop;
        }
        c.value.style.margin = `${qe}px 0`, c.value.style.minHeight = `${z}px`, c.value.style.maxHeight = `${V}px`, n("placed"), requestAnimationFrame(() => u.value = !0);
      }
    }
    const $ = T("");
    le(async () => {
      await oe(), C(), v.value && ($.value = window.getComputedStyle(v.value).zIndex);
    });
    function h(E) {
      E && d.value === !0 && (C(), _ == null || _(), d.value = !1);
    }
    return Uf({
      contentWrapper: c,
      shouldExpandOnScrollRef: u,
      onScrollButtonChange: h
    }), (E, P) => (b(), ve("div", {
      ref_key: "contentWrapperElement",
      ref: c,
      style: Me({
        display: "flex",
        flexDirection: "column",
        position: "fixed",
        zIndex: $.value
      })
    }, [
      q(o(O), k({
        ref: o(f),
        style: {
          // When we get the height of the content, it includes borders. If we were to set
          // the height without having `boxSizing: 'border-box'` it would be too big.
          boxSizing: "border-box",
          // We need to ensure the content doesn't get taller than the wrapper
          maxHeight: "100%"
        }
      }, { ...E.$attrs, ...e }), {
        default: y(() => [
          w(E.$slots, "default")
        ]),
        _: 3
      }, 16)
    ], 4));
  }
}), qf = /* @__PURE__ */ x({
  __name: "SelectPopperPosition",
  props: {
    side: {},
    sideOffset: {},
    align: { default: "start" },
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: { default: qe },
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const e = Ot(a);
    return (n, l) => (b(), S(o(It), k(o(e), { style: {
      // Ensure border-box for floating-ui calculations
      boxSizing: "border-box",
      "--radix-select-content-transform-origin": "var(--radix-popper-transform-origin)",
      "--radix-select-content-available-width": "var(--radix-popper-available-width)",
      "--radix-select-content-available-height": "var(--radix-popper-available-height)",
      "--radix-select-trigger-width": "var(--radix-popper-anchor-width)",
      "--radix-select-trigger-height": "var(--radix-popper-anchor-height)"
    } }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), zt = {
  onViewportChange: () => {
  },
  itemTextRefCallback: () => {
  },
  itemRefCallback: () => {
  }
}, [St, Yf] = te("SelectContent"), Xf = /* @__PURE__ */ x({
  __name: "SelectContentImpl",
  props: {
    position: { default: "item-aligned" },
    bodyLock: { type: Boolean, default: !0 },
    side: {},
    sideOffset: {},
    align: { default: "start" },
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["closeAutoFocus", "escapeKeyDown", "pointerDownOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = xt();
    Yn(), ya(e.bodyLock);
    const { createCollection: s } = Fe(), r = T();
    ga(r);
    const i = s(r), { search: u, handleTypeaheadSearch: d } = ba(i), c = T(), f = T(), v = T(), p = T(!1), g = T(!1);
    function m() {
      f.value && r.value && In([f.value, r.value]);
    }
    ee(p, () => {
      m();
    });
    const { onOpenChange: _, triggerPointerDownPosRef: C } = l;
    Ce((P) => {
      if (!r.value)
        return;
      let D = { x: 0, y: 0 };
      const I = (V) => {
        var A, F;
        D = {
          x: Math.abs(
            Math.round(V.pageX) - (((A = C.value) == null ? void 0 : A.x) ?? 0)
          ),
          y: Math.abs(
            Math.round(V.pageY) - (((F = C.value) == null ? void 0 : F.y) ?? 0)
          )
        };
      }, M = (V) => {
        var A;
        V.pointerType !== "touch" && (D.x <= 10 && D.y <= 10 ? V.preventDefault() : (A = r.value) != null && A.contains(V.target) || _(!1), document.removeEventListener("pointermove", I), C.value = null);
      };
      C.value !== null && (document.addEventListener("pointermove", I), document.addEventListener("pointerup", M, {
        capture: !0,
        once: !0
      })), P(() => {
        document.removeEventListener("pointermove", I), document.removeEventListener("pointerup", M, {
          capture: !0
        });
      });
    });
    function $(P) {
      const D = P.ctrlKey || P.altKey || P.metaKey;
      if (P.key === "Tab" && P.preventDefault(), !D && P.key.length === 1 && d(P.key), ["ArrowUp", "ArrowDown", "Home", "End"].includes(P.key)) {
        let I = i.value;
        if (["ArrowUp", "End"].includes(P.key) && (I = I.slice().reverse()), ["ArrowUp", "ArrowDown"].includes(P.key)) {
          const M = P.target, V = I.indexOf(M);
          I = I.slice(V + 1);
        }
        setTimeout(() => In(I)), P.preventDefault();
      }
    }
    const h = B(() => e.position === "popper" ? e : {}), E = Ot(h.value);
    return Yf({
      content: r,
      viewport: c,
      onViewportChange: (P) => {
        c.value = P;
      },
      itemRefCallback: (P, D, I) => {
        var A, F;
        const M = !g.value && !I;
        (((A = l.modelValue) == null ? void 0 : A.value) !== void 0 && ((F = l.modelValue) == null ? void 0 : F.value) === D || M) && (f.value = P, M && (g.value = !0));
      },
      selectedItem: f,
      selectedItemText: v,
      onItemLeave: () => {
        var P;
        (P = r.value) == null || P.focus();
      },
      itemTextRefCallback: (P, D, I) => {
        var A, F;
        const M = !g.value && !I;
        (((A = l.modelValue) == null ? void 0 : A.value) !== void 0 && ((F = l.modelValue) == null ? void 0 : F.value) === D || M) && (v.value = P);
      },
      focusSelectedItem: m,
      position: e.position,
      isPositioned: p,
      searchRef: u
    }), (P, D) => (b(), S(o(Za), {
      "as-child": "",
      onMountAutoFocus: D[6] || (D[6] = ue(() => {
      }, ["prevent"])),
      onUnmountAutoFocus: D[7] || (D[7] = (I) => {
        var M;
        n("closeAutoFocus", I), !I.defaultPrevented && ((M = o(l).triggerElement.value) == null || M.focus({ preventScroll: !0 }), I.preventDefault());
      })
    }, {
      default: y(() => [
        q(o(Ct), {
          "as-child": "",
          "disable-outside-pointer-events": "",
          onFocusOutside: D[2] || (D[2] = ue(() => {
          }, ["prevent"])),
          onDismiss: D[3] || (D[3] = (I) => o(l).onOpenChange(!1)),
          onEscapeKeyDown: D[4] || (D[4] = (I) => n("escapeKeyDown", I)),
          onPointerDownOutside: D[5] || (D[5] = (I) => n("pointerDownOutside", I))
        }, {
          default: y(() => [
            (b(), S(Xe(
              P.position === "popper" ? qf : Gf
            ), k({ ...P.$attrs, ...o(E) }, {
              id: o(l).contentId,
              ref: (I) => {
                r.value = o($e)(I);
              },
              role: "listbox",
              "data-state": o(l).open.value ? "open" : "closed",
              dir: o(l).dir.value,
              style: {
                // flex layout so we can place the scroll buttons properly
                display: "flex",
                flexDirection: "column",
                // reset the outline by default as the content MAY get focused
                outline: "none"
              },
              onContextmenu: D[0] || (D[0] = ue(() => {
              }, ["prevent"])),
              onPlaced: D[1] || (D[1] = (I) => p.value = !0),
              onKeydown: $
            }), {
              default: y(() => [
                w(P.$slots, "default")
              ]),
              _: 3
            }, 16, ["id", "data-state", "dir", "onKeydown"]))
          ]),
          _: 3
        })
      ]),
      _: 3
    }));
  }
}), Zf = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "SelectProvider",
  props: {
    context: {}
  },
  setup(a) {
    return Rs(a.context), (e, n) => w(e.$slots, "default");
  }
}), Jf = { key: 1 }, jy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "SelectContent",
  props: {
    forceMount: { type: Boolean },
    position: {},
    bodyLock: { type: Boolean },
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean },
    updatePositionStrategy: {},
    prioritizePosition: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["closeAutoFocus", "escapeKeyDown", "pointerDownOutside"],
  setup(a, { emit: t }) {
    const e = a, l = Se(e, t), s = xt(), r = T();
    le(() => {
      r.value = new DocumentFragment();
    });
    const i = T(), u = B(() => e.forceMount || s.open.value);
    return (d, c) => {
      var f;
      return u.value ? (b(), S(o(Pe), {
        key: 0,
        ref_key: "presenceRef",
        ref: i,
        present: !0
      }, {
        default: y(() => [
          q(Xf, W(U({ ...o(l), ...d.$attrs })), {
            default: y(() => [
              w(d.$slots, "default")
            ]),
            _: 3
          }, 16)
        ]),
        _: 3
      }, 512)) : !((f = i.value) != null && f.present) && r.value ? (b(), ve("div", Jf, [
        (b(), S(qt, { to: r.value }, [
          q(Zf, { context: o(s) }, {
            default: y(() => [
              w(d.$slots, "default")
            ]),
            _: 3
          }, 8, ["context"])
        ], 8, ["to"]))
      ])) : ce("", !0);
    };
  }
}), Uy = /* @__PURE__ */ x({
  __name: "SelectArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a, e = xt(), n = St(zt);
    return (l, s) => o(e).open.value && o(n).position === "popper" ? (b(), S(o(Zt), W(k({ key: 0 }, t)), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
}), Gy = /* @__PURE__ */ x({
  __name: "SelectSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(O), k({ "aria-hidden": "true" }, t), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), [Os, Qf] = te("SelectItem"), qy = /* @__PURE__ */ x({
  __name: "SelectItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    textValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { disabled: e } = ae(t), n = xt(), l = St(zt), { forwardRef: s, currentElement: r } = R(), i = B(() => {
      var m;
      return ((m = n.modelValue) == null ? void 0 : m.value) === t.value;
    }), u = T(!1), d = T(t.textValue ?? ""), c = ge(void 0, "radix-vue-select-item-text");
    async function f(m) {
      await oe(), !(m != null && m.defaultPrevented) && (e.value || (n.onValueChange(t.value), n.onOpenChange(!1)));
    }
    async function v(m) {
      var _;
      await oe(), !m.defaultPrevented && (e.value ? (_ = l.onItemLeave) == null || _.call(l) : m.currentTarget.focus({ preventScroll: !0 }));
    }
    async function p(m) {
      var _;
      await oe(), !m.defaultPrevented && m.currentTarget === me() && ((_ = l.onItemLeave) == null || _.call(l));
    }
    async function g(m) {
      var C;
      await oe(), !(m.defaultPrevented || ((C = l.searchRef) == null ? void 0 : C.value) !== "" && m.key === " ") && (jf.includes(m.key) && f(), m.key === " " && m.preventDefault());
    }
    if (t.value === "")
      throw new Error(
        "A <SelectItem /> must have a value prop that is not an empty string. This is because the Select value can be set to an empty string to clear the selection and show the placeholder."
      );
    return le(() => {
      r.value && l.itemRefCallback(
        r.value,
        t.value,
        t.disabled
      );
    }), Qf({
      value: t.value,
      disabled: e,
      textId: c,
      isSelected: i,
      onItemTextChange: (m) => {
        d.value = ((d.value || (m == null ? void 0 : m.textContent)) ?? "").trim();
      }
    }), (m, _) => (b(), S(o(O), {
      ref: o(s),
      role: "option",
      "data-radix-vue-collection-item": "",
      "aria-labelledby": o(c),
      "data-highlighted": u.value ? "" : void 0,
      "aria-selected": i.value,
      "data-state": i.value ? "checked" : "unchecked",
      "aria-disabled": o(e) || void 0,
      "data-disabled": o(e) ? "" : void 0,
      tabindex: o(e) ? void 0 : -1,
      as: m.as,
      "as-child": m.asChild,
      onFocus: _[0] || (_[0] = (C) => u.value = !0),
      onBlur: _[1] || (_[1] = (C) => u.value = !1),
      onPointerup: f,
      onPointerdown: _[2] || (_[2] = (C) => {
        C.currentTarget.focus({ preventScroll: !0 });
      }),
      onTouchend: _[3] || (_[3] = ue(() => {
      }, ["prevent", "stop"])),
      onPointermove: v,
      onPointerleave: p,
      onKeydown: g
    }, {
      default: y(() => [
        w(m.$slots, "default")
      ]),
      _: 3
    }, 8, ["aria-labelledby", "data-highlighted", "aria-selected", "data-state", "aria-disabled", "data-disabled", "tabindex", "as", "as-child"]));
  }
}), Yy = /* @__PURE__ */ x({
  __name: "SelectItemIndicator",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, e = Os();
    return (n, l) => o(e).isSelected.value ? (b(), S(o(O), k({
      key: 0,
      "aria-hidden": "true"
    }, t), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16)) : ce("", !0);
  }
}), [ep, tp] = te("SelectGroup"), Xy = /* @__PURE__ */ x({
  __name: "SelectGroup",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = ge(void 0, "radix-vue-select-group");
    return tp({ id: e }), (n, l) => (b(), S(o(O), k({ role: "group" }, t, { "aria-labelledby": o(e) }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-labelledby"]));
  }
}), Zy = /* @__PURE__ */ x({
  __name: "SelectLabel",
  props: {
    for: {},
    asChild: { type: Boolean },
    as: { default: "div" }
  },
  setup(a) {
    const t = a, e = ep({ id: "" });
    return (n, l) => (b(), S(o(O), k(t, {
      id: o(e).id
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), Jy = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "SelectItemText",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, e = xt(), n = St(zt), l = Kf(), s = Os(), { forwardRef: r, currentElement: i } = R(), u = B(() => {
      var d;
      return mt("option", {
        key: s.value,
        value: s.value,
        disabled: s.disabled.value,
        textContent: (d = i.value) == null ? void 0 : d.textContent
      });
    });
    return le(() => {
      i.value && (s.onItemTextChange(i.value), n.itemTextRefCallback(
        i.value,
        s.value,
        s.disabled.value
      ), l.onNativeOptionAdd(u.value));
    }), Nn(() => {
      l.onNativeOptionRemove(u.value);
    }), (d, c) => (b(), ve(_e, null, [
      q(o(O), k({
        id: o(s).textId,
        ref: o(r)
      }, { ...t, ...d.$attrs }, { "data-item-text": "" }), {
        default: y(() => [
          w(d.$slots, "default")
        ]),
        _: 3
      }, 16, ["id"]),
      o(s).isSelected.value && o(e).valueElement.value && !o(e).valueElementHasChildren.value ? (b(), S(qt, {
        key: 0,
        to: o(e).valueElement.value
      }, [
        w(d.$slots, "default")
      ], 8, ["to"])) : ce("", !0)
    ], 64));
  }
}), Qy = /* @__PURE__ */ x({
  __name: "SelectViewport",
  props: {
    nonce: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { nonce: e } = ae(t), n = Ja(e), l = St(zt), s = l.position === "item-aligned" ? Io() : void 0, { forwardRef: r, currentElement: i } = R();
    le(() => {
      l == null || l.onViewportChange(i.value);
    });
    const u = T(0);
    function d(c) {
      const f = c.currentTarget, { shouldExpandOnScrollRef: v, contentWrapper: p } = s ?? {};
      if (v != null && v.value && (p != null && p.value)) {
        const g = Math.abs(u.value - f.scrollTop);
        if (g > 0) {
          const m = window.innerHeight - qe * 2, _ = Number.parseFloat(
            p.value.style.minHeight
          ), C = Number.parseFloat(p.value.style.height), $ = Math.max(_, C);
          if ($ < m) {
            const h = $ + g, E = Math.min(m, h), P = h - E;
            p.value.style.height = `${E}px`, p.value.style.bottom === "0px" && (f.scrollTop = P > 0 ? P : 0, p.value.style.justifyContent = "flex-end");
          }
        }
      }
      u.value = f.scrollTop;
    }
    return (c, f) => (b(), ve(_e, null, [
      q(o(O), k({
        ref: o(r),
        "data-radix-select-viewport": "",
        role: "presentation"
      }, { ...c.$attrs, ...t }, {
        style: {
          // we use position: 'relative' here on the `viewport` so that when we call
          // `selectedItem.offsetTop` in calculations, the offset is relative to the viewport
          // (independent of the scrollUpButton).
          position: "relative",
          flex: 1,
          overflow: "hidden auto"
        },
        onScroll: d
      }), {
        default: y(() => [
          w(c.$slots, "default")
        ]),
        _: 3
      }, 16),
      q(o(O), {
        as: "style",
        nonce: o(n)
      }, {
        default: y(() => [
          ye(" /* Hide scrollbars cross-browser and enable momentum scroll for touch devices */ [data-radix-select-viewport] { scrollbar-width:none; -ms-overflow-style: none; -webkit-overflow-scrolling: touch; } [data-radix-select-viewport]::-webkit-scrollbar { display: none; } ")
        ]),
        _: 1
      }, 8, ["nonce"])
    ], 64));
  }
}), ks = /* @__PURE__ */ x({
  __name: "SelectScrollButtonImpl",
  emits: ["autoScroll"],
  setup(a, { emit: t }) {
    const e = t, { injectCollection: n } = Fe(), l = n(), s = St(zt), r = T(null);
    function i() {
      r.value !== null && (window.clearInterval(r.value), r.value = null);
    }
    Ce(() => {
      const c = l.value.find(
        (f) => f === me()
      );
      c == null || c.scrollIntoView({ block: "nearest" });
    });
    function u() {
      r.value === null && (r.value = window.setInterval(() => {
        e("autoScroll");
      }, 50));
    }
    function d() {
      var c;
      (c = s.onItemLeave) == null || c.call(s), r.value === null && (r.value = window.setInterval(() => {
        e("autoScroll");
      }, 50));
    }
    return Nn(() => i()), (c, f) => {
      var v;
      return b(), S(o(O), k({
        "aria-hidden": "true",
        style: {
          flexShrink: 0
        }
      }, (v = c.$parent) == null ? void 0 : v.$props, {
        onPointerdown: u,
        onPointermove: d,
        onPointerleave: f[0] || (f[0] = () => {
          i();
        })
      }), {
        default: y(() => [
          w(c.$slots, "default")
        ]),
        _: 3
      }, 16);
    };
  }
}), eg = /* @__PURE__ */ x({
  __name: "SelectScrollUpButton",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = St(zt), e = t.position === "item-aligned" ? Io() : void 0, { forwardRef: n, currentElement: l } = R(), s = T(!1);
    return Ce((r) => {
      var i, u;
      if ((i = t.viewport) != null && i.value && ((u = t.isPositioned) != null && u.value)) {
        let d = function() {
          s.value = c.scrollTop > 0;
        };
        const c = t.viewport.value;
        d(), c.addEventListener("scroll", d), r(() => c.removeEventListener("scroll", d));
      }
    }), ee(l, () => {
      l.value && (e == null || e.onScrollButtonChange(l.value));
    }), (r, i) => s.value ? (b(), S(ks, {
      key: 0,
      ref: o(n),
      onAutoScroll: i[0] || (i[0] = () => {
        const { viewport: u, selectedItem: d } = o(t);
        u != null && u.value && (d != null && d.value) && (u.value.scrollTop = u.value.scrollTop - d.value.offsetHeight);
      })
    }, {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 512)) : ce("", !0);
  }
}), tg = /* @__PURE__ */ x({
  __name: "SelectScrollDownButton",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = St(zt), e = t.position === "item-aligned" ? Io() : void 0, { forwardRef: n, currentElement: l } = R(), s = T(!1);
    return Ce((r) => {
      var i, u;
      if ((i = t.viewport) != null && i.value && ((u = t.isPositioned) != null && u.value)) {
        let d = function() {
          const f = c.scrollHeight - c.clientHeight;
          s.value = Math.ceil(c.scrollTop) < f;
        };
        const c = t.viewport.value;
        d(), c.addEventListener("scroll", d), r(() => c.removeEventListener("scroll", d));
      }
    }), ee(l, () => {
      l.value && (e == null || e.onScrollButtonChange(l.value));
    }), (r, i) => s.value ? (b(), S(ks, {
      key: 0,
      ref: o(n),
      onAutoScroll: i[0] || (i[0] = () => {
        const { viewport: u, selectedItem: d } = o(t);
        u != null && u.value && (d != null && d.value) && (u.value.scrollTop = u.value.scrollTop + d.value.offsetHeight);
      })
    }, {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 512)) : ce("", !0);
  }
}), ag = /* @__PURE__ */ x({
  __name: "SelectValue",
  props: {
    placeholder: { default: "" },
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const { forwardRef: t, currentElement: e } = R(), n = xt(), l = Ua();
    return gl(() => {
      var r;
      const s = !!qa((r = l == null ? void 0 : l.default) == null ? void 0 : r.call(l)).length;
      n.onValueElementHasChildrenChange(s);
    }), le(() => {
      n.valueElement = e;
    }), (s, r) => (b(), S(o(O), {
      ref: o(t),
      as: s.as,
      "as-child": s.asChild,
      style: { pointerEvents: "none" }
    }, {
      default: y(() => {
        var i;
        return [
          o(As)((i = o(n).modelValue) == null ? void 0 : i.value) ? (b(), ve(_e, { key: 0 }, [
            ye(De(s.placeholder), 1)
          ], 64)) : w(s.$slots, "default", { key: 1 })
        ];
      }),
      _: 3
    }, 8, ["as", "as-child"]));
  }
}), ng = /* @__PURE__ */ x({
  __name: "SelectIcon",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    return (t, e) => (b(), S(o(O), {
      "aria-hidden": "true",
      as: t.as,
      "as-child": t.asChild
    }, {
      default: y(() => [
        w(t.$slots, "default", {}, () => [
          ye("▼")
        ])
      ]),
      _: 3
    }, 8, ["as", "as-child"]));
  }
}), Ms = /* @__PURE__ */ x({
  __name: "BaseSeparator",
  props: {
    orientation: { default: "horizontal" },
    decorative: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = ["horizontal", "vertical"];
    function n(i) {
      return e.includes(i);
    }
    const l = B(
      () => n(t.orientation) ? t.orientation : "horizontal"
    ), s = B(
      () => l.value === "vertical" ? t.orientation : void 0
    ), r = B(
      () => t.decorative ? { role: "none" } : { "aria-orientation": s.value, role: "separator" }
    );
    return (i, u) => (b(), S(o(O), k({
      as: i.as,
      "as-child": i.asChild,
      "data-orientation": l.value
    }, r.value), {
      default: y(() => [
        w(i.$slots, "default")
      ]),
      _: 3
    }, 16, ["as", "as-child", "data-orientation"]));
  }
}), ap = /* @__PURE__ */ x({
  __name: "Separator",
  props: {
    orientation: { default: "horizontal" },
    decorative: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(Ms, W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
});
function np(a = [], t, e) {
  const n = [...a];
  return n[e] = t, n.sort((l, s) => l - s);
}
function Vs(a, t, e) {
  const s = 100 / (e - t) * (a - t);
  return Ut(s, 0, 100);
}
function op(a, t) {
  return t > 2 ? `Value ${a + 1} of ${t}` : t === 2 ? ["Minimum", "Maximum"][a] : void 0;
}
function lp(a, t) {
  if (a.length === 1)
    return 0;
  const e = a.map((l) => Math.abs(l - t)), n = Math.min(...e);
  return e.indexOf(n);
}
function sp(a, t, e) {
  const n = a / 2, s = To([0, 50], [0, n]);
  return (n - s(t) * e) * e;
}
function rp(a) {
  return a.slice(0, -1).map((t, e) => a[e + 1] - t);
}
function ip(a, t) {
  if (t > 0) {
    const e = rp(a);
    return Math.min(...e) >= t;
  }
  return !0;
}
function To(a, t) {
  return (e) => {
    if (a[0] === a[1] || t[0] === t[1])
      return t[0];
    const n = (t[1] - t[0]) / (a[1] - a[0]);
    return t[0] + n * (e - a[0]);
  };
}
function up(a) {
  return (String(a).split(".")[1] || "").length;
}
function dp(a, t) {
  const e = 10 ** t;
  return Math.round(a * e) / e;
}
const Fs = ["PageUp", "PageDown"], Ns = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"], Ls = {
  "from-left": ["Home", "PageDown", "ArrowDown", "ArrowLeft"],
  "from-right": ["Home", "PageDown", "ArrowDown", "ArrowRight"],
  "from-bottom": ["Home", "PageDown", "ArrowDown", "ArrowLeft"],
  "from-top": ["Home", "PageDown", "ArrowUp", "ArrowLeft"]
}, [zs, Ks] = te(["SliderVertical", "SliderHorizontal"]), Hs = /* @__PURE__ */ x({
  __name: "SliderImpl",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  emits: ["slideStart", "slideMove", "slideEnd", "homeKeyDown", "endKeyDown", "stepKeyDown"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = un();
    return (s, r) => (b(), S(o(O), k({ "data-slider-impl": "" }, e, {
      onKeydown: r[0] || (r[0] = (i) => {
        i.key === "Home" ? (n("homeKeyDown", i), i.preventDefault()) : i.key === "End" ? (n("endKeyDown", i), i.preventDefault()) : o(Fs).concat(o(Ns)).includes(i.key) && (n("stepKeyDown", i), i.preventDefault());
      }),
      onPointerdown: r[1] || (r[1] = (i) => {
        const u = i.target;
        u.setPointerCapture(i.pointerId), i.preventDefault(), o(l).thumbElements.value.includes(u) ? u.focus() : n("slideStart", i);
      }),
      onPointermove: r[2] || (r[2] = (i) => {
        i.target.hasPointerCapture(i.pointerId) && n("slideMove", i);
      }),
      onPointerup: r[3] || (r[3] = (i) => {
        const u = i.target;
        u.hasPointerCapture(i.pointerId) && (u.releasePointerCapture(i.pointerId), n("slideEnd", i));
      })
    }), {
      default: y(() => [
        w(s.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), cp = /* @__PURE__ */ x({
  __name: "SliderHorizontal",
  props: {
    dir: {},
    min: {},
    max: {},
    inverted: { type: Boolean }
  },
  emits: ["slideEnd", "slideStart", "slideMove", "homeKeyDown", "endKeyDown", "stepKeyDown"],
  setup(a, { emit: t }) {
    const e = a, n = t, { max: l, min: s, dir: r, inverted: i } = ae(e), { forwardRef: u, currentElement: d } = R(), c = T(), f = B(() => (r == null ? void 0 : r.value) === "ltr" && !i.value || (r == null ? void 0 : r.value) !== "ltr" && i.value);
    function v(p) {
      const g = c.value || d.value.getBoundingClientRect(), m = [0, g.width], _ = f.value ? [s.value, l.value] : [l.value, s.value], C = To(m, _);
      return c.value = g, C(p - g.left);
    }
    return Ks({
      startEdge: f.value ? "left" : "right",
      endEdge: f.value ? "right" : "left",
      direction: f.value ? 1 : -1,
      size: "width"
    }), (p, g) => (b(), S(Hs, {
      ref: o(u),
      dir: o(r),
      "data-orientation": "horizontal",
      style: {
        "--radix-slider-thumb-transform": "translateX(-50%)"
      },
      onSlideStart: g[0] || (g[0] = (m) => {
        const _ = v(m.clientX);
        n("slideStart", _);
      }),
      onSlideMove: g[1] || (g[1] = (m) => {
        const _ = v(m.clientX);
        n("slideMove", _);
      }),
      onSlideEnd: g[2] || (g[2] = () => {
        c.value = void 0, n("slideEnd");
      }),
      onStepKeyDown: g[3] || (g[3] = (m) => {
        const _ = f.value ? "from-left" : "from-right", C = o(Ls)[_].includes(m.key);
        n("stepKeyDown", m, C ? -1 : 1);
      }),
      onEndKeyDown: g[4] || (g[4] = (m) => n("endKeyDown", m)),
      onHomeKeyDown: g[5] || (g[5] = (m) => n("homeKeyDown", m))
    }, {
      default: y(() => [
        w(p.$slots, "default")
      ]),
      _: 3
    }, 8, ["dir"]));
  }
}), fp = /* @__PURE__ */ x({
  __name: "SliderVertical",
  props: {
    min: {},
    max: {},
    inverted: { type: Boolean }
  },
  emits: ["slideEnd", "slideStart", "slideMove", "homeKeyDown", "endKeyDown", "stepKeyDown"],
  setup(a, { emit: t }) {
    const e = a, n = t, { max: l, min: s, inverted: r } = ae(e), { forwardRef: i, currentElement: u } = R(), d = T(), c = B(() => !r.value);
    function f(v) {
      const p = d.value || u.value.getBoundingClientRect(), g = [0, p.height], m = c.value ? [l.value, s.value] : [s.value, l.value], _ = To(g, m);
      return d.value = p, _(v - p.top);
    }
    return Ks({
      startEdge: c.value ? "bottom" : "top",
      endEdge: c.value ? "top" : "bottom",
      size: "height",
      direction: c.value ? 1 : -1
    }), (v, p) => (b(), S(Hs, {
      ref: o(i),
      "data-orientation": "vertical",
      style: {
        "--radix-slider-thumb-transform": "translateY(50%)"
      },
      onSlideStart: p[0] || (p[0] = (g) => {
        const m = f(g.clientY);
        n("slideStart", m);
      }),
      onSlideMove: p[1] || (p[1] = (g) => {
        const m = f(g.clientY);
        n("slideMove", m);
      }),
      onSlideEnd: p[2] || (p[2] = () => {
        d.value = void 0, n("slideEnd");
      }),
      onStepKeyDown: p[3] || (p[3] = (g) => {
        const m = c.value ? "from-bottom" : "from-top", _ = o(Ls)[m].includes(g.key);
        n("stepKeyDown", g, _ ? -1 : 1);
      }),
      onEndKeyDown: p[4] || (p[4] = (g) => n("endKeyDown", g)),
      onHomeKeyDown: p[5] || (p[5] = (g) => n("homeKeyDown", g))
    }, {
      default: y(() => [
        w(v.$slots, "default")
      ]),
      _: 3
    }, 512));
  }
}), pp = ["value", "name", "disabled", "step"], [un, vp] = te("SliderRoot"), og = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "SliderRoot",
  props: {
    name: {},
    defaultValue: { default: () => [0] },
    modelValue: {},
    disabled: { type: Boolean, default: !1 },
    orientation: { default: "horizontal" },
    dir: {},
    inverted: { type: Boolean, default: !1 },
    min: { default: 0 },
    max: { default: 100 },
    step: { default: 1 },
    minStepsBetweenThumbs: { default: 0 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "valueCommit"],
  setup(a, { emit: t }) {
    const e = a, n = t, { min: l, max: s, step: r, minStepsBetweenThumbs: i, orientation: u, disabled: d, dir: c } = ae(e), f = we(c), { forwardRef: v, currentElement: p } = R(), g = at(p);
    Ca();
    const m = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: e.modelValue === void 0
    }), _ = T(0), C = T(m.value);
    function $(I) {
      const M = lp(m.value, I);
      P(I, M);
    }
    function h(I) {
      P(I, _.value);
    }
    function E() {
      const I = C.value[_.value];
      m.value[_.value] !== I && n("valueCommit", Pr(m.value));
    }
    function P(I, M, { commit: V } = { commit: !1 }) {
      var Q;
      const A = up(r.value), F = dp(Math.round((I - l.value) / r.value) * r.value + l.value, A), j = Ut(F, l.value, s.value), H = np(m.value, j, M);
      if (ip(H, i.value * r.value)) {
        _.value = H.indexOf(j);
        const G = String(H) !== String(m.value);
        G && V && n("valueCommit", H), G && ((Q = D.value[_.value]) == null || Q.focus(), m.value = H);
      }
    }
    const D = T([]);
    return vp({
      modelValue: m,
      valueIndexToChangeRef: _,
      thumbElements: D,
      orientation: u,
      min: l,
      max: s,
      disabled: d
    }), (I, M) => (b(), ve(_e, null, [
      q(o(wa), null, {
        default: y(() => [
          (b(), S(Xe(o(u) === "horizontal" ? cp : fp), k(I.$attrs, {
            ref: o(v),
            "as-child": I.asChild,
            as: I.as,
            min: o(l),
            max: o(s),
            dir: o(f),
            inverted: I.inverted,
            "aria-disabled": o(d),
            "data-disabled": o(d) ? "" : void 0,
            onPointerdown: M[0] || (M[0] = () => {
              o(d) || (C.value = o(m));
            }),
            onSlideStart: M[1] || (M[1] = (V) => !o(d) && $(V)),
            onSlideMove: M[2] || (M[2] = (V) => !o(d) && h(V)),
            onSlideEnd: M[3] || (M[3] = (V) => !o(d) && E()),
            onHomeKeyDown: M[4] || (M[4] = (V) => !o(d) && P(o(l), 0, { commit: !0 })),
            onEndKeyDown: M[5] || (M[5] = (V) => !o(d) && P(o(s), o(m).length - 1, { commit: !0 })),
            onStepKeyDown: M[6] || (M[6] = (V, A) => {
              if (!o(d)) {
                const H = o(Fs).includes(V.key) || V.shiftKey && o(Ns).includes(V.key) ? 10 : 1, Q = _.value, G = o(m)[Q], J = o(r) * H * A;
                P(G + J, Q, { commit: !0 });
              }
            })
          }), {
            default: y(() => [
              w(I.$slots, "default", { modelValue: o(m) })
            ]),
            _: 3
          }, 16, ["as-child", "as", "min", "max", "dir", "inverted", "aria-disabled", "data-disabled"]))
        ]),
        _: 3
      }),
      o(g) ? (b(!0), ve(_e, { key: 0 }, ma(o(m), (V, A) => (b(), ve("input", {
        key: A,
        value: V,
        type: "number",
        style: { display: "none" },
        name: I.name ? I.name + (o(m).length > 1 ? "[]" : "") : void 0,
        disabled: o(d),
        step: o(r)
      }, null, 8, pp))), 128)) : ce("", !0)
    ], 64));
  }
}), mp = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "SliderThumbImpl",
  props: {
    index: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = un(), n = zs(), { forwardRef: l, currentElement: s } = R(), r = B(() => {
      var p, g;
      return (g = (p = e.modelValue) == null ? void 0 : p.value) == null ? void 0 : g[t.index];
    }), i = B(() => r.value === void 0 ? 0 : Vs(r.value, e.min.value ?? 0, e.max.value ?? 100)), u = B(() => {
      var p, g;
      return op(t.index, ((g = (p = e.modelValue) == null ? void 0 : p.value) == null ? void 0 : g.length) ?? 0);
    }), d = Ll(s), c = B(() => d[n.size].value), f = B(() => c.value ? sp(c.value, i.value, n.direction) : 0), v = Ga();
    return le(() => {
      e.thumbElements.value.push(s.value);
    }), Be(() => {
      const p = e.thumbElements.value.findIndex((g) => g === s.value) ?? -1;
      e.thumbElements.value.splice(p, 1);
    }), (p, g) => (b(), S(o(Qt), null, {
      default: y(() => [
        q(o(O), k(p.$attrs, {
          ref: o(l),
          role: "slider",
          "data-radix-vue-collection-item": "",
          tabindex: o(e).disabled.value ? void 0 : 0,
          "aria-label": p.$attrs["aria-label"] || u.value,
          "data-disabled": o(e).disabled.value ? "" : void 0,
          "data-orientation": o(e).orientation.value,
          "aria-valuenow": r.value,
          "aria-valuemin": o(e).min.value,
          "aria-valuemax": o(e).max.value,
          "aria-orientation": o(e).orientation.value,
          "as-child": p.asChild,
          as: p.as,
          style: {
            transform: "var(--radix-slider-thumb-transform)",
            position: "absolute",
            [o(n).startEdge]: `calc(${i.value}% + ${f.value}px)`,
            /**
             * There will be no value on initial render while we work out the index so we hide thumbs
             * without a value, otherwise SSR will render them in the wrong position before they
             * snap into the correct position during hydration which would be visually jarring for
             * slower connections.
             */
            display: !o(v) && r.value === void 0 ? "none" : void 0
          },
          onFocus: g[0] || (g[0] = () => {
            o(e).valueIndexToChangeRef.value = p.index;
          })
        }), {
          default: y(() => [
            w(p.$slots, "default")
          ]),
          _: 3
        }, 16, ["tabindex", "aria-label", "data-disabled", "data-orientation", "aria-valuenow", "aria-valuemin", "aria-valuemax", "aria-orientation", "as-child", "as", "style"])
      ]),
      _: 3
    }));
  }
}), lg = /* @__PURE__ */ x({
  __name: "SliderThumb",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { getItems: e } = ea(), { forwardRef: n, currentElement: l } = R(), s = B(() => l.value ? e().findIndex((r) => r.ref === l.value) : -1);
    return (r, i) => (b(), S(mp, k({ ref: o(n) }, t, { index: s.value }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16, ["index"]));
  }
}), sg = /* @__PURE__ */ x({
  __name: "SliderTrack",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = un();
    return R(), (e, n) => (b(), S(o(O), {
      "as-child": e.asChild,
      as: e.as,
      "data-disabled": o(t).disabled.value ? "" : void 0,
      "data-orientation": o(t).orientation.value
    }, {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 8, ["as-child", "as", "data-disabled", "data-orientation"]));
  }
}), rg = /* @__PURE__ */ x({
  __name: "SliderRange",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = un(), e = zs();
    R();
    const n = B(() => {
      var r, i;
      return (i = (r = t.modelValue) == null ? void 0 : r.value) == null ? void 0 : i.map(
        (u) => Vs(u, t.min.value, t.max.value)
      );
    }), l = B(() => t.modelValue.value.length > 1 ? Math.min(...n.value) : 0), s = B(() => 100 - Math.max(...n.value));
    return (r, i) => (b(), S(o(O), {
      "data-disabled": o(t).disabled.value ? "" : void 0,
      "data-orientation": o(t).orientation.value,
      "as-child": r.asChild,
      as: r.as,
      style: Me({
        [o(e).startEdge]: `${l.value}%`,
        [o(e).endEdge]: `${s.value}%`
      })
    }, {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 8, ["data-disabled", "data-orientation", "as-child", "as", "style"]));
  }
});
let kn = null, $t = null;
function hp(a, t) {
  if (t) {
    const e = (t & Xs) !== 0, n = (t & Zs) !== 0, l = (t & Js) !== 0, s = (t & Qs) !== 0;
    if (e)
      return l ? "se-resize" : s ? "ne-resize" : "e-resize";
    if (n)
      return l ? "sw-resize" : s ? "nw-resize" : "w-resize";
    if (l)
      return "s-resize";
    if (s)
      return "n-resize";
  }
  switch (a) {
    case "horizontal":
      return "ew-resize";
    case "intersection":
      return "move";
    case "vertical":
      return "ns-resize";
  }
}
function Ws() {
  $t !== null && (document.head.removeChild($t), kn = null, $t = null);
}
function Pn(a, t) {
  const e = hp(a, t);
  kn !== e && (kn = e, $t === null && ($t = document.createElement("style"), document.head.appendChild($t)), $t.innerHTML = `*{cursor: ${e}!important;}`);
}
function yp({
  defaultSize: a,
  dragState: t,
  layout: e,
  panelData: n,
  panelIndex: l,
  precision: s = 3
}) {
  const r = e[l];
  let i;
  return r == null ? i = a !== void 0 ? a.toPrecision(s) : "1" : n.length === 1 ? i = "1" : i = r.toPrecision(s), {
    flexBasis: 0,
    flexGrow: i,
    flexShrink: 1,
    // Without this, Panel sizes may be unintentionally overridden by their content
    overflow: "hidden",
    // Disable pointer events inside of a panel during resize
    // This avoid edge cases like nested iframes
    pointerEvents: t !== null ? "none" : void 0
  };
}
function js(a) {
  return a.type === "keydown";
}
function Us(a) {
  return a.type.startsWith("mouse");
}
function Gs(a) {
  return a.type.startsWith("touch");
}
function dn(a) {
  if (Us(a))
    return {
      x: a.clientX,
      y: a.clientY
    };
  if (Gs(a)) {
    const t = a.touches[0];
    if (t && t.clientX && t.clientY)
      return {
        x: t.clientX,
        y: t.clientY
      };
  }
  return {
    x: Number.POSITIVE_INFINITY,
    y: Number.POSITIVE_INFINITY
  };
}
function qs(a, t) {
  const e = a === "horizontal", { x: n, y: l } = dn(t);
  return e ? n : l;
}
function gp(a, t, e) {
  return a.x < t.x + t.width && a.x + a.width > t.x && a.y < t.y + t.height && a.y + a.height > t.y;
}
function pe(a, t = "Assertion failed!") {
  if (!a)
    throw console.error(t), new Error(t);
}
function bp(a, t) {
  if (a === t)
    throw new Error("Cannot compare node with itself");
  const e = {
    a: ll(a),
    b: ll(t)
  };
  let n;
  for (; e.a.at(-1) === e.b.at(-1); )
    a = e.a.pop(), t = e.b.pop(), n = a;
  pe(n);
  const l = {
    a: ol(nl(e.a)),
    b: ol(nl(e.b))
  };
  if (l.a === l.b) {
    const s = n.childNodes, r = {
      a: e.a.at(-1),
      b: e.b.at(-1)
    };
    let i = s.length;
    for (; i--; ) {
      const u = s[i];
      if (u === r.a)
        return 1;
      if (u === r.b)
        return -1;
    }
  }
  return Math.sign(l.a - l.b);
}
const Cp = /\b(?:position|zIndex|opacity|transform|webkitTransform|mixBlendMode|filter|webkitFilter|isolation)\b/;
function wp(a) {
  const t = getComputedStyle(Ys(a)).display;
  return t === "flex" || t === "inline-flex";
}
function _p(a) {
  const t = getComputedStyle(a);
  return !!(t.position === "fixed" || t.zIndex !== "auto" && (t.position !== "static" || wp(a)) || +t.opacity < 1 || "transform" in t && t.transform !== "none" || "webkitTransform" in t && t.webkitTransform !== "none" || "mixBlendMode" in t && t.mixBlendMode !== "normal" || "filter" in t && t.filter !== "none" || "webkitFilter" in t && t.webkitFilter !== "none" || "isolation" in t && t.isolation === "isolate" || Cp.test(t.willChange) || t.webkitOverflowScrolling === "touch");
}
function nl(a) {
  let t = a.length;
  for (; t--; ) {
    const e = a[t];
    if (pe(e), _p(e))
      return e;
  }
  return null;
}
function ol(a) {
  return a && Number(getComputedStyle(a).zIndex) || 0;
}
function ll(a) {
  const t = [];
  for (; a; )
    t.push(a), a = Ys(a);
  return t;
}
function Ys(a) {
  var t;
  return a.parentNode instanceof DocumentFragment && ((t = a.parentNode) == null ? void 0 : t.host) || a.parentNode;
}
const Xs = 1, Zs = 2, Js = 4, Qs = 8;
function xp() {
  if (typeof matchMedia == "function")
    return matchMedia("(pointer:coarse)").matches ? "coarse" : "fine";
}
const Sp = xp() === "coarse", yt = [];
let cn = !1;
const vt = /* @__PURE__ */ new Map(), fn = /* @__PURE__ */ new Map(), fa = /* @__PURE__ */ new Set();
function Ep(a, t, e, n, l) {
  const { ownerDocument: s } = t, r = {
    direction: e,
    element: t,
    hitAreaMargins: n,
    setResizeHandlerState: l
  }, i = vt.get(s) ?? 0;
  return vt.set(s, i + 1), fa.add(r), Ha(), function() {
    fn.delete(a), fa.delete(r);
    const d = vt.get(s) ?? 1;
    vt.set(s, d - 1), Ha(), Ws(), d === 1 && vt.delete(s);
  };
}
function Aa(a) {
  const { target: t } = a, { x: e, y: n } = dn(a);
  cn = !0, Ro({ target: t, x: e, y: n }), Ha(), yt.length > 0 && (Ao("down", a), a.preventDefault());
}
function ct(a) {
  const { x: t, y: e } = dn(a);
  if (!cn) {
    const { target: n } = a;
    Ro({ target: n, x: t, y: e });
  }
  Ao("move", a), er(), yt.length > 0 && a.preventDefault();
}
function ft(a) {
  const { target: t } = a, { x: e, y: n } = dn(a);
  fn.clear(), cn = !1, yt.length > 0 && a.preventDefault(), Ao("up", a), Ro({ target: t, x: e, y: n }), er(), Ha();
}
function Ro({
  target: a,
  x: t,
  y: e
}) {
  yt.splice(0);
  let n = null;
  a instanceof HTMLElement && (n = a), fa.forEach((l) => {
    const { element: s, hitAreaMargins: r } = l, i = s.getBoundingClientRect(), { bottom: u, left: d, right: c, top: f } = i, v = Sp ? r.coarse : r.fine;
    if (t >= d - v && t <= c + v && e >= f - v && e <= u + v) {
      if (n !== null && s !== n && !s.contains(n) && !n.contains(s) && bp(n, s) > 0) {
        let g = n, m = !1;
        for (; g && !g.contains(s); ) {
          if (gp(
            g.getBoundingClientRect(),
            i
          )) {
            m = !0;
            break;
          }
          g = g.parentElement;
        }
        if (m)
          return;
      }
      yt.push(l);
    }
  });
}
function Dn(a, t) {
  fn.set(a, t);
}
function er() {
  let a = !1, t = !1;
  yt.forEach((n) => {
    const { direction: l } = n;
    l.value === "horizontal" ? a = !0 : t = !0;
  });
  let e = 0;
  fn.forEach((n) => {
    e |= n;
  }), a && t ? Pn("intersection", e) : a ? Pn("horizontal", e) : t ? Pn("vertical", e) : Ws();
}
function Ha() {
  vt.forEach((a, t) => {
    const { body: e } = t;
    e.removeEventListener("contextmenu", ft), e.removeEventListener("mousedown", Aa), e.removeEventListener("mouseleave", ct), e.removeEventListener("mousemove", ct), e.removeEventListener("touchmove", ct), e.removeEventListener("touchstart", Aa);
  }), window.removeEventListener("mouseup", ft), window.removeEventListener("touchcancel", ft), window.removeEventListener("touchend", ft), fa.size > 0 && (cn ? (yt.length > 0 && vt.forEach((a, t) => {
    const { body: e } = t;
    a > 0 && (e.addEventListener("contextmenu", ft), e.addEventListener("mouseleave", ct), e.addEventListener("mousemove", ct), e.addEventListener("touchmove", ct, {
      passive: !1
    }));
  }), window.addEventListener("mouseup", ft), window.addEventListener("touchcancel", ft), window.addEventListener("touchend", ft)) : vt.forEach((a, t) => {
    const { body: e } = t;
    a > 0 && (e.addEventListener("mousedown", Aa), e.addEventListener("mousemove", ct), e.addEventListener("touchmove", ct, {
      passive: !1
    }), e.addEventListener("touchstart", Aa));
  }));
}
function Ao(a, t) {
  fa.forEach((e) => {
    const { setResizeHandlerState: n } = e, l = yt.includes(e);
    n(a, l, t);
  });
}
const Oo = 10;
function pa(a, t, e = Oo) {
  a = Number.parseFloat(a.toFixed(e)), t = Number.parseFloat(t.toFixed(e));
  const n = a - t;
  return n === 0 ? 0 : n > 0 ? 1 : -1;
}
function Le(a, t, e) {
  return pa(a, t, e) === 0;
}
function Wt({
  panelConstraints: a,
  panelIndex: t,
  size: e
}) {
  const n = a[t];
  pe(n != null);
  const { collapsedSize: l = 0, collapsible: s, maxSize: r = 100, minSize: i = 0 } = n;
  if (pa(e, i) < 0)
    if (s) {
      const u = (l + i) / 2;
      pa(e, u) < 0 ? e = l : e = i;
    } else
      e = i;
  return e = Math.min(r, e), e = Number.parseFloat(e.toFixed(Oo)), e;
}
function Oa(a, t) {
  if (a.length !== t.length)
    return !1;
  for (let e = 0; e < a.length; e++)
    if (a[e] !== t[e])
      return !1;
  return !0;
}
function sa({
  delta: a,
  layout: t,
  panelConstraints: e,
  pivotIndices: n,
  trigger: l
}) {
  if (Le(a, 0))
    return t;
  const s = [...t], [r, i] = n;
  pe(r != null), pe(i != null);
  let u = 0;
  if (l === "keyboard") {
    {
      const c = a < 0 ? i : r, f = e[c];
      if (pe(f), f.collapsible) {
        const v = t[c];
        pe(v != null);
        const p = e[c];
        pe(p);
        const { collapsedSize: g = 0, minSize: m = 0 } = p;
        if (Le(v, g)) {
          const _ = m - v;
          pa(_, Math.abs(a)) > 0 && (a = a < 0 ? 0 - _ : _);
        }
      }
    }
    {
      const c = a < 0 ? r : i, f = e[c];
      pe(f);
      const { collapsible: v } = f;
      if (v) {
        const p = t[c];
        pe(p != null);
        const g = e[c];
        pe(g);
        const { collapsedSize: m = 0, minSize: _ = 0 } = g;
        if (Le(p, _)) {
          const C = p - m;
          pa(C, Math.abs(a)) > 0 && (a = a < 0 ? 0 - C : C);
        }
      }
    }
  }
  {
    const c = a < 0 ? 1 : -1;
    let f = a < 0 ? i : r, v = 0;
    for (; ; ) {
      const g = t[f];
      pe(g != null);
      const _ = Wt({
        panelConstraints: e,
        panelIndex: f,
        size: 100
      }) - g;
      if (v += _, f += c, f < 0 || f >= e.length)
        break;
    }
    const p = Math.min(Math.abs(a), Math.abs(v));
    a = a < 0 ? 0 - p : p;
  }
  {
    let f = a < 0 ? r : i;
    for (; f >= 0 && f < e.length; ) {
      const v = Math.abs(a) - Math.abs(u), p = t[f];
      pe(p != null);
      const g = p - v, m = Wt({
        panelConstraints: e,
        panelIndex: f,
        size: g
      });
      if (!Le(p, m) && (u += p - m, s[f] = m, u.toPrecision(3).localeCompare(Math.abs(a).toPrecision(3), void 0, {
        numeric: !0
      }) >= 0))
        break;
      a < 0 ? f-- : f++;
    }
  }
  if (Le(u, 0))
    return t;
  {
    const c = a < 0 ? i : r, f = t[c];
    pe(f != null);
    const v = f + u, p = Wt({
      panelConstraints: e,
      panelIndex: c,
      size: v
    });
    if (s[c] = p, !Le(p, v)) {
      let g = v - p, _ = a < 0 ? i : r;
      for (; _ >= 0 && _ < e.length; ) {
        const C = s[_];
        pe(C != null);
        const $ = C + g, h = Wt({
          panelConstraints: e,
          panelIndex: _,
          size: $
        });
        if (Le(C, h) || (g -= h - C, s[_] = h), Le(g, 0))
          break;
        a > 0 ? _-- : _++;
      }
    }
  }
  const d = s.reduce((c, f) => f + c, 0);
  return Le(d, 100) ? s : t;
}
function tr(a, t = document) {
  var n;
  if (!ha)
    return null;
  if (t instanceof HTMLElement && ((n = t == null ? void 0 : t.dataset) == null ? void 0 : n.panelGroupId) === a)
    return t;
  const e = t.querySelector(
    `[data-panel-group][data-panel-group-id="${a}"]`
  );
  return e || null;
}
function pn(a, t = document) {
  if (!ha)
    return null;
  const e = t.querySelector(`[data-panel-resize-handle-id="${a}"]`);
  return e || null;
}
function ar(a, t, e = document) {
  return ha ? va(a, e).findIndex(
    (s) => s.getAttribute("data-panel-resize-handle-id") === t
  ) ?? null : null;
}
function va(a, t = document) {
  return ha ? Array.from(
    t.querySelectorAll(
      `[data-panel-resize-handle-id][data-panel-group-id="${a}"]`
    )
  ) : [];
}
function Pp(a, t, e, n = document) {
  var d, c;
  const l = pn(t, n), s = va(a, n), r = l ? s.indexOf(l) : -1, i = ((d = e[r]) == null ? void 0 : d.id) ?? null, u = ((c = e[r + 1]) == null ? void 0 : c.id) ?? null;
  return [i, u];
}
function Dp(a, t, e, n, l) {
  const s = e === "horizontal", r = pn(t, l);
  pe(r);
  const i = r.getAttribute("data-panel-group-id");
  pe(i);
  const { initialCursorPosition: u } = n, d = qs(e, a), c = tr(i, l);
  pe(c);
  const f = c.getBoundingClientRect(), v = s ? f.width : f.height;
  return (d - u) / v * 100;
}
function $p(a, t, e, n, l, s) {
  if (js(a)) {
    const r = e === "horizontal";
    let i = 0;
    a.shiftKey ? i = 100 : i = l ?? 10;
    let u = 0;
    switch (a.key) {
      case "ArrowDown":
        u = r ? 0 : i;
        break;
      case "ArrowLeft":
        u = r ? -i : 0;
        break;
      case "ArrowRight":
        u = r ? i : 0;
        break;
      case "ArrowUp":
        u = r ? 0 : -i;
        break;
      case "End":
        u = 100;
        break;
      case "Home":
        u = -100;
        break;
    }
    return u;
  } else
    return n == null ? 0 : Dp(
      a,
      t,
      e,
      n,
      s
    );
}
function Bp({
  layout: a,
  panelsArray: t,
  pivotIndices: e
}) {
  let n = 0, l = 100, s = 0, r = 0;
  const i = e[0];
  pe(i != null), t.forEach((f, v) => {
    const { constraints: p } = f, { maxSize: g = 100, minSize: m = 0 } = p;
    v === i ? (n = m, l = g) : (s += m, r += g);
  });
  const u = Math.min(l, 100 - s), d = Math.max(n, 100 - r), c = a[i];
  return {
    valueMax: u,
    valueMin: d,
    valueNow: c
  };
}
function Ip({
  panelDataArray: a
}) {
  const t = Array(a.length), e = a.map(
    (s) => s.constraints
  );
  let n = 0, l = 100;
  for (let s = 0; s < a.length; s++) {
    const r = e[s];
    pe(r);
    const { defaultSize: i } = r;
    i != null && (n++, t[s] = i, l -= i);
  }
  for (let s = 0; s < a.length; s++) {
    const r = e[s];
    pe(r);
    const { defaultSize: i } = r;
    if (i != null)
      continue;
    const u = a.length - n, d = l / u;
    n++, t[s] = d, l -= d;
  }
  return t;
}
function la(a, t, e) {
  t.forEach((n, l) => {
    const s = a[l];
    pe(s);
    const { callbacks: r, constraints: i, id: u } = s, { collapsedSize: d = 0, collapsible: c } = i, f = e[u];
    if (f == null || n !== f) {
      e[u] = n;
      const { onCollapse: v, onExpand: p, onResize: g } = r;
      g && g(n, f), c && (v || p) && (p && (f == null || f === d) && n !== d && p(), v && (f == null || f !== d) && n === d && v());
    }
  });
}
function Tp(a, t = 10) {
  let e = null;
  return (...l) => {
    e !== null && clearTimeout(e), e = setTimeout(() => {
      a(...l);
    }, t);
  };
}
function nr(a, t, e) {
  const n = ar(
    a,
    t,
    e
  );
  return n != null ? [n, n + 1] : [-1, -1];
}
function Rp({
  layout: a,
  panelConstraints: t
}) {
  const e = [...a], n = e.reduce(
    (s, r) => s + r,
    0
  );
  if (e.length !== t.length)
    throw new Error(
      `Invalid ${t.length} panel layout: ${e.map((s) => `${s}%`).join(", ")}`
    );
  if (!Le(n, 100)) {
    console.warn(
      `WARNING: Invalid layout total size: ${e.map((s) => `${s}%`).join(", ")}. Layout normalization will be applied.`
    );
    for (let s = 0; s < t.length; s++) {
      const r = e[s];
      pe(r != null);
      const i = 100 / n * r;
      e[s] = i;
    }
  }
  let l = 0;
  for (let s = 0; s < t.length; s++) {
    const r = e[s];
    pe(r != null);
    const i = Wt({
      panelConstraints: t,
      panelIndex: s,
      size: r
    });
    r !== i && (l += r - i, e[s] = i);
  }
  if (!Le(l, 0))
    for (let s = 0; s < t.length; s++) {
      const r = e[s];
      pe(r != null);
      const i = r + l, u = Wt({
        panelConstraints: t,
        panelIndex: s,
        size: i
      });
      if (r !== u && (l -= u - r, e[s] = u, Le(l, 0)))
        break;
    }
  return e;
}
function sl(a) {
  try {
    if (typeof localStorage < "u")
      a.getItem = (t) => localStorage.getItem(t), a.setItem = (t, e) => {
        localStorage.setItem(t, e);
      };
    else
      throw new TypeError("localStorage not supported in this environment");
  } catch (t) {
    console.error(t), a.getItem = () => null, a.setItem = () => {
    };
  }
}
function or(a) {
  return `radix-vue:${a}`;
}
function lr(a) {
  return a.map((t) => {
    const { constraints: e, id: n, idIsFromProps: l, order: s } = t;
    return l ? n : s ? `${s}:${JSON.stringify(e)}` : JSON.stringify(e);
  }).sort((t, e) => t.localeCompare(e)).join(",");
}
function sr(a, t) {
  try {
    const e = or(a), n = t.getItem(e);
    if (n) {
      const l = JSON.parse(n);
      if (typeof l == "object" && l != null)
        return l;
    }
  } catch {
  }
  return null;
}
function Ap(a, t, e) {
  const n = sr(a, e) ?? {}, l = lr(t);
  return n[l] ?? null;
}
function Op(a, t, e, n, l) {
  const s = or(a), r = lr(t), i = sr(a, l) ?? {};
  i[r] = {
    expandToSizes: Object.fromEntries(e.entries()),
    layout: n
  };
  try {
    l.setItem(s, JSON.stringify(i));
  } catch (u) {
    console.error(u);
  }
}
function kp({
  eagerValuesRef: a,
  groupId: t,
  layout: e,
  panelDataArray: n,
  panelGroupElement: l,
  setLayout: s
}) {
  Ce((r) => {
    const i = l.value;
    if (!i)
      return;
    const u = va(
      t,
      i
    );
    for (let d = 0; d < n.length - 1; d++) {
      const { valueMax: c, valueMin: f, valueNow: v } = Bp({
        layout: e.value,
        panelsArray: n,
        pivotIndices: [d, d + 1]
      }), p = u[d];
      if (p != null) {
        const g = n[d];
        pe(g), p.setAttribute("aria-controls", g.id), p.setAttribute(
          "aria-valuemax",
          `${Math.round(c)}`
        ), p.setAttribute(
          "aria-valuemin",
          `${Math.round(f)}`
        ), p.setAttribute(
          "aria-valuenow",
          v != null ? `${Math.round(v)}` : ""
        );
      }
    }
    r(() => {
      u.forEach((d) => {
        d.removeAttribute("aria-controls"), d.removeAttribute("aria-valuemax"), d.removeAttribute("aria-valuemin"), d.removeAttribute("aria-valuenow");
      });
    });
  }), Ce((r) => {
    const i = l.value;
    if (!i)
      return;
    const u = a.value;
    pe(u);
    const { panelDataArray: d } = u, c = tr(t, i);
    pe(c != null, `No group found for id "${t}"`);
    const f = va(t, i);
    pe(f);
    const v = f.map((p) => {
      const g = p.getAttribute("data-panel-resize-handle-id");
      pe(g);
      const [m, _] = Pp(
        t,
        g,
        d,
        i
      );
      if (m == null || _ == null)
        return () => {
        };
      const C = ($) => {
        if (!$.defaultPrevented)
          switch ($.key) {
            case "Enter": {
              $.preventDefault();
              const h = d.findIndex(
                (E) => E.id === m
              );
              if (h >= 0) {
                const E = d[h];
                pe(E);
                const P = e.value[h], {
                  collapsedSize: D = 0,
                  collapsible: I,
                  minSize: M = 0
                } = E.constraints;
                if (P != null && I) {
                  const V = sa({
                    delta: Le(P, D) ? M - D : D - P,
                    layout: e.value,
                    panelConstraints: d.map(
                      (A) => A.constraints
                    ),
                    pivotIndices: nr(
                      t,
                      g,
                      i
                    ),
                    trigger: "keyboard"
                  });
                  e.value !== V && s(V);
                }
              }
              break;
            }
          }
      };
      return p.addEventListener("keydown", C), () => {
        p.removeEventListener("keydown", C);
      };
    });
    r(() => {
      v.forEach((p) => p());
    });
  });
}
const Mp = 100, ra = {
  getItem: (a) => (sl(ra), ra.getItem(a)),
  setItem: (a, t) => {
    sl(ra), ra.setItem(a, t);
  }
}, [rr, Vp] = te("PanelGroup"), ig = /* @__PURE__ */ x({
  __name: "SplitterGroup",
  props: {
    id: {},
    autoSaveId: { default: null },
    direction: {},
    keyboardResizeBy: { default: 10 },
    storage: { default: () => ra },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["layout"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = {}, { direction: s } = ae(e), r = ge(e.id, "radix-vue-splitter-group"), i = we(), { forwardRef: u, currentElement: d } = R(), c = T(null), f = T([]), v = T({}), p = T(/* @__PURE__ */ new Map()), g = T(0), m = B(() => ({
      autoSaveId: e.autoSaveId,
      direction: e.direction,
      dragState: c.value,
      id: r,
      keyboardResizeBy: e.keyboardResizeBy,
      storage: e.storage
    })), _ = T({
      layout: f.value,
      panelDataArray: [],
      panelDataArrayChanged: !1
    }), C = (z) => f.value = z;
    kp({
      eagerValuesRef: _,
      groupId: r,
      layout: f,
      panelDataArray: _.value.panelDataArray,
      setLayout: C,
      panelGroupElement: d
    }), Ce(() => {
      const { panelDataArray: z } = _.value, { autoSaveId: K } = e;
      if (K) {
        if (f.value.length === 0 || f.value.length !== z.length)
          return;
        let L = l[K];
        L || (L = Tp(
          Op,
          Mp
        ), l[K] = L);
        const N = [...z], Z = new Map(
          p.value
        );
        L(
          K,
          N,
          Z,
          f.value,
          e.storage
        );
      }
    });
    function $(z, K) {
      const { panelDataArray: L } = _.value, N = G(L, z);
      return yp({
        defaultSize: K,
        dragState: c.value,
        layout: f.value,
        panelData: L,
        panelIndex: N
      });
    }
    function h(z) {
      const { panelDataArray: K } = _.value;
      K.push(z), K.sort((L, N) => {
        const Z = L.order, Y = N.order;
        return Z == null && Y == null ? 0 : Z == null ? -1 : Y == null ? 1 : Z - Y;
      }), _.value.panelDataArrayChanged = !0;
    }
    ee(() => _.value.panelDataArrayChanged, () => {
      if (_.value.panelDataArrayChanged) {
        _.value.panelDataArrayChanged = !1;
        const { autoSaveId: z, storage: K } = m.value, { layout: L, panelDataArray: N } = _.value;
        let Z = null;
        if (z) {
          const re = Ap(z, N, K);
          re && (p.value = new Map(
            Object.entries(re.expandToSizes)
          ), Z = re.layout);
        }
        Z === null && (Z = Ip({
          panelDataArray: N
        }));
        const Y = Rp({
          layout: Z,
          panelConstraints: N.map(
            (re) => re.constraints
          )
        });
        Gr(L, Y) || (C(Y), _.value.layout = Y, n("layout", Y), la(
          N,
          Y,
          v.value
        ));
      }
    });
    function E(z) {
      return function(L) {
        L.preventDefault();
        const N = d.value;
        if (!N)
          return () => null;
        const { direction: Z, dragState: Y, id: re, keyboardResizeBy: X } = m.value, { layout: se, panelDataArray: fe } = _.value, { initialLayout: xe } = Y ?? {}, Ee = nr(
          re,
          z,
          N
        );
        let be = $p(
          L,
          z,
          Z,
          Y,
          X,
          N
        );
        if (be === 0)
          return;
        const de = Z === "horizontal";
        i.value === "rtl" && de && (be = -be);
        const Ie = fe.map((Et) => Et.constraints), Ae = sa({
          delta: be,
          layout: xe ?? se,
          panelConstraints: Ie,
          pivotIndices: Ee,
          trigger: js(L) ? "keyboard" : "mouse-or-touch"
        }), We = !Oa(se, Ae);
        (Us(L) || Gs(L)) && g.value !== be && (g.value = be, We ? Dn(z, 0) : de ? Dn(
          z,
          be < 0 ? Xs : Zs
        ) : Dn(
          z,
          be < 0 ? Js : Qs
        )), We && (C(Ae), _.value.layout = Ae, n("layout", Ae), la(
          fe,
          Ae,
          v.value
        ));
      };
    }
    function P(z, K) {
      const { layout: L, panelDataArray: N } = _.value, Z = N.map((xe) => xe.constraints), { panelSize: Y, pivotIndices: re } = J(
        N,
        z,
        L
      );
      pe(Y != null);
      const se = G(N, z) === N.length - 1 ? Y - K : K - Y, fe = sa({
        delta: se,
        layout: L,
        panelConstraints: Z,
        pivotIndices: re,
        trigger: "imperative-api"
      });
      Oa(L, fe) || (C(fe), _.value.layout = fe, n("layout", fe), la(
        N,
        fe,
        v.value
      ));
    }
    function D(z, K) {
      const { layout: L, panelDataArray: N } = _.value, Z = G(N, z);
      N[Z] = z, _.value.panelDataArrayChanged = !0;
      const {
        collapsedSize: Y = 0,
        collapsible: re
      } = K, {
        collapsedSize: X = 0,
        collapsible: se,
        maxSize: fe = 100,
        minSize: xe = 0
      } = z.constraints, { panelSize: Ee } = J(
        N,
        z,
        L
      );
      Ee !== null && (re && se && Ee === Y ? Y !== X && P(z, X) : Ee < xe ? P(z, xe) : Ee > fe && P(z, fe));
    }
    function I(z, K) {
      const { direction: L } = m.value, { layout: N } = _.value;
      if (!d.value)
        return;
      const Z = pn(
        z,
        d.value
      );
      pe(Z);
      const Y = qs(
        L,
        K
      );
      c.value = {
        dragHandleId: z,
        dragHandleRect: Z.getBoundingClientRect(),
        initialCursorPosition: Y,
        initialLayout: N
      };
    }
    function M() {
      c.value = null;
    }
    function V(z) {
      const { panelDataArray: K } = _.value, L = G(K, z);
      L >= 0 && (K.splice(L, 1), delete v.value[z.id], _.value.panelDataArrayChanged = !0);
    }
    function A(z) {
      const { layout: K, panelDataArray: L } = _.value;
      if (z.constraints.collapsible) {
        const N = L.map(
          (X) => X.constraints
        ), {
          collapsedSize: Z = 0,
          panelSize: Y,
          pivotIndices: re
        } = J(L, z, K);
        if (pe(
          Y != null,
          `Panel size not found for panel "${z.id}"`
        ), Y !== Z) {
          p.value.set(z.id, Y);
          const se = G(L, z) === L.length - 1 ? Y - Z : Z - Y, fe = sa({
            delta: se,
            layout: K,
            panelConstraints: N,
            pivotIndices: re,
            trigger: "imperative-api"
          });
          Oa(K, fe) || (C(fe), _.value.layout = fe, n("layout", fe), la(
            L,
            fe,
            v.value
          ));
        }
      }
    }
    function F(z) {
      const { layout: K, panelDataArray: L } = _.value;
      if (z.constraints.collapsible) {
        const N = L.map(
          (se) => se.constraints
        ), {
          collapsedSize: Z = 0,
          panelSize: Y,
          minSize: re = 0,
          pivotIndices: X
        } = J(L, z, K);
        if (Y === Z) {
          const se = p.value.get(
            z.id
          ), fe = se != null && se >= re ? se : re, Ee = G(L, z) === L.length - 1 ? Y - fe : fe - Y, be = sa({
            delta: Ee,
            layout: K,
            panelConstraints: N,
            pivotIndices: X,
            trigger: "imperative-api"
          });
          Oa(K, be) || (C(be), _.value.layout = be, n("layout", be), la(
            L,
            be,
            v.value
          ));
        }
      }
    }
    function j(z) {
      const { layout: K, panelDataArray: L } = _.value, { panelSize: N } = J(L, z, K);
      return pe(
        N != null,
        `Panel size not found for panel "${z.id}"`
      ), N;
    }
    function H(z) {
      const { layout: K, panelDataArray: L } = _.value, {
        collapsedSize: N = 0,
        collapsible: Z,
        panelSize: Y
      } = J(L, z, K);
      return Z ? Y === void 0 ? z.constraints.defaultSize === z.constraints.collapsedSize : Y === N : !1;
    }
    function Q(z) {
      const { layout: K, panelDataArray: L } = _.value, {
        collapsedSize: N = 0,
        collapsible: Z,
        panelSize: Y
      } = J(L, z, K);
      return pe(
        Y != null,
        `Panel size not found for panel "${z.id}"`
      ), !Z || Y > N;
    }
    Vp({
      direction: s,
      dragState: c.value,
      groupId: r,
      reevaluatePanelConstraints: D,
      registerPanel: h,
      registerResizeHandle: E,
      resizePanel: P,
      startDragging: I,
      stopDragging: M,
      unregisterPanel: V,
      panelGroupElement: d,
      collapsePanel: A,
      expandPanel: F,
      isPanelCollapsed: H,
      isPanelExpanded: Q,
      getPanelSize: j,
      getPanelStyle: $
    });
    function G(z, K) {
      return z.findIndex(
        (L) => L === K || L.id === K.id
      );
    }
    function J(z, K, L) {
      const N = G(z, K), Y = N === z.length - 1 ? [N - 1, N] : [N, N + 1], re = L[N];
      return {
        ...K.constraints,
        panelSize: re,
        pivotIndices: Y
      };
    }
    return (z, K) => (b(), S(o(O), {
      ref: o(u),
      as: z.as,
      "as-child": z.asChild,
      style: Me({
        display: "flex",
        flexDirection: o(s) === "horizontal" ? "row" : "column",
        height: "100%",
        overflow: "hidden",
        width: "100%"
      }),
      "data-panel-group": "",
      "data-orientation": o(s),
      "data-panel-group-id": o(r)
    }, {
      default: y(() => [
        w(z.$slots, "default", { layout: f.value })
      ]),
      _: 3
    }, 8, ["as", "as-child", "style", "data-orientation", "data-panel-group-id"]));
  }
}), ug = /* @__PURE__ */ x({
  __name: "SplitterPanel",
  props: {
    collapsedSize: {},
    collapsible: { type: Boolean },
    defaultSize: {},
    id: {},
    maxSize: {},
    minSize: {},
    order: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["collapse", "expand", "resize"],
  setup(a, { expose: t, emit: e }) {
    const n = a, l = e, s = rr();
    if (s === null)
      throw new Error(
        "SplitterPanel components must be rendered within a SplitterGroup container"
      );
    const { collapsePanel: r, expandPanel: i, getPanelSize: u, getPanelStyle: d, isPanelCollapsed: c, resizePanel: f, groupId: v, reevaluatePanelConstraints: p, registerPanel: g, unregisterPanel: m } = s, _ = ge(n.id, "radix-vue-splitter-panel"), C = B(() => ({
      callbacks: {
        onCollapse: () => l("collapse"),
        onExpand: () => l("expand"),
        onResize: (...P) => l("resize", ...P)
      },
      constraints: {
        collapsedSize: n.collapsedSize && Number.parseFloat(n.collapsedSize.toFixed(Oo)),
        collapsible: n.collapsible,
        defaultSize: n.defaultSize,
        /** Panel id (unique within group); falls back to useId when not provided */
        /** Panel id (unique within group); falls back to useId when not provided */
        maxSize: n.maxSize,
        minSize: n.minSize
      },
      id: _,
      idIsFromProps: n.id !== void 0,
      order: n.order
    }));
    ee(() => C.value.constraints, (P, D) => {
      (D.collapsedSize !== P.collapsedSize || D.collapsible !== P.collapsible || D.maxSize !== P.maxSize || D.minSize !== P.minSize) && p(C.value, D);
    }, { deep: !0 }), le(() => {
      const P = C.value;
      g(P), Be(() => {
        m(P);
      });
    });
    const $ = B(() => d(C.value, n.defaultSize)), h = B(() => c(C.value)), E = B(() => !h.value);
    return t({
      /** If panel is `collapsible`, collapse it fully. */
      collapse: () => {
        r(C.value);
      },
      /** If panel is currently collapsed, expand it to its most recent size. */
      expand: () => {
        i(C.value);
      },
      /** Gets the current size of the panel as a percentage (1 - 100). */
      getSize() {
        return u(C.value);
      },
      /** Resize panel to the specified percentage (1 - 100). */
      resize: (P) => {
        f(C.value, P);
      },
      /** Returns `true` if the panel is currently collapsed */
      isCollapsed: h,
      /** Returns `true` if the panel is currently not collapsed */
      isExpanded: E
    }), (P, D) => (b(), S(o(O), {
      id: o(_),
      style: Me($.value),
      as: P.as,
      "as-child": P.asChild,
      "data-panel": "",
      "data-panel-collapsible": P.collapsible || void 0,
      "data-panel-group-id": o(v),
      "data-panel-id": o(_),
      "data-panel-size": Number.parseFloat(`${$.value.flexGrow}`).toFixed(1),
      "data-state": P.collapsible ? h.value ? "collapsed" : "expanded" : void 0
    }, {
      default: y(() => [
        w(P.$slots, "default", {
          isCollapsed: h.value,
          isExpanded: E.value
        })
      ]),
      _: 3
    }, 8, ["id", "style", "as", "as-child", "data-panel-collapsible", "data-panel-group-id", "data-panel-id", "data-panel-size", "data-state"]));
  }
});
function Fp({
  disabled: a,
  handleId: t,
  resizeHandler: e,
  panelGroupElement: n
}) {
  Ce((l) => {
    const s = n.value;
    if (a.value || e.value === null || s === null)
      return;
    const r = pn(t, s);
    if (r == null)
      return;
    const i = (u) => {
      var d;
      if (!u.defaultPrevented)
        switch (u.key) {
          case "ArrowDown":
          case "ArrowLeft":
          case "ArrowRight":
          case "ArrowUp":
          case "End":
          case "Home": {
            u.preventDefault(), (d = e.value) == null || d.call(e, u);
            break;
          }
          case "F6": {
            u.preventDefault();
            const c = r.getAttribute("data-panel-group-id");
            pe(c);
            const f = va(
              c,
              s
            ), v = ar(
              c,
              t,
              s
            );
            pe(v !== null);
            const p = u.shiftKey ? v > 0 ? v - 1 : f.length - 1 : v + 1 < f.length ? v + 1 : 0;
            f[p].focus();
            break;
          }
        }
    };
    r.addEventListener("keydown", i), l(() => {
      r.removeEventListener("keydown", i);
    });
  });
}
const dg = /* @__PURE__ */ x({
  __name: "SplitterResizeHandle",
  props: {
    id: {},
    hitAreaMargins: {},
    tabindex: { default: 0 },
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["dragging"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l, currentElement: s } = R(), { disabled: r } = ae(e), i = rr();
    if (i === null)
      throw new Error(
        "PanelResizeHandle components must be rendered within a PanelGroup container"
      );
    const {
      direction: u,
      groupId: d,
      registerResizeHandle: c,
      startDragging: f,
      stopDragging: v,
      panelGroupElement: p
    } = i, g = ge(e.id, "radix-vue-splitter-resize-handle"), m = T("inactive"), _ = T(!1), C = T(null);
    return ee(r, () => {
      ha && (r.value ? C.value = null : C.value = c(g));
    }, { immediate: !0 }), Ce(($) => {
      var P, D;
      if (r.value || C.value === null)
        return;
      const h = s.value;
      if (!h)
        return;
      pe(h);
      const E = (I, M, V) => {
        var A;
        if (M)
          switch (I) {
            case "down": {
              m.value = "drag", f(g, V), n("dragging", !0);
              break;
            }
            case "move": {
              m.value !== "drag" && (m.value = "hover"), (A = C.value) == null || A.call(C, V);
              break;
            }
            case "up": {
              m.value = "hover", v(), n("dragging", !1);
              break;
            }
          }
        else
          m.value = "inactive";
      };
      $(Ep(
        g,
        h,
        u,
        {
          // Coarse inputs (e.g. finger/touch)
          coarse: ((P = e.hitAreaMargins) == null ? void 0 : P.coarse) ?? 15,
          // Fine inputs (e.g. mouse)
          fine: ((D = e.hitAreaMargins) == null ? void 0 : D.fine) ?? 5
        },
        E
      ));
    }), Fp({
      disabled: r,
      resizeHandler: C,
      handleId: g,
      panelGroupElement: p
    }), ($, h) => (b(), S(o(O), {
      id: o(g),
      ref: o(l),
      style: {
        touchAction: "none",
        userSelect: "none"
      },
      as: $.as,
      "as-child": $.asChild,
      role: "separator",
      "data-resize-handle": "",
      tabindex: $.tabindex,
      "data-state": m.value,
      "data-disabled": o(r) ? "" : void 0,
      "data-orientation": o(u),
      "data-panel-group-id": o(d),
      "data-resize-handle-active": m.value === "drag" ? "pointer" : _.value ? "keyboard" : void 0,
      "data-resize-handle-state": m.value,
      "data-panel-resize-handle-enabled": !o(r),
      "data-panel-resize-handle-id": o(g),
      onBlur: h[0] || (h[0] = (E) => _.value = !1),
      onFocus: h[1] || (h[1] = (E) => _.value = !1)
    }, {
      default: y(() => [
        w($.$slots, "default")
      ]),
      _: 3
    }, 8, ["id", "as", "as-child", "tabindex", "data-state", "data-disabled", "data-orientation", "data-panel-group-id", "data-resize-handle-active", "data-resize-handle-state", "data-panel-resize-handle-enabled", "data-panel-resize-handle-id"]));
  }
}), Np = {
  "aria-live": "polite",
  "aria-atomic": "true",
  role: "status",
  style: {
    transform: "translateX(-100%)",
    position: "absolute",
    pointerEvents: "none",
    opacity: 0,
    margin: 0
  }
}, [ko, Lp] = te("StepperRoot"), cg = /* @__PURE__ */ x({
  __name: "StepperRoot",
  props: {
    defaultValue: { default: 1 },
    orientation: { default: "horizontal" },
    dir: {},
    modelValue: {},
    linear: { type: Boolean, default: !0 },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { dir: l, orientation: s, linear: r } = ae(e), i = we(l);
    R();
    const u = T(/* @__PURE__ */ new Set()), d = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: e.modelValue === void 0
    }), c = B(() => Array.from(u.value)), f = B(() => d.value === 1), v = B(() => d.value === c.value.length), p = B(() => u.value.size);
    function g(h) {
      h > p.value || h < 1 || u.value.size && c.value[h] && c.value[h].getAttribute("disabled") || r.value && h > (d.value ?? 1) + 1 || (d.value = h);
    }
    const m = T(null), _ = T(null), C = B(() => m.value ? m.value.getAttribute("disabled") === "" : !0), $ = B(() => _.value ? _.value.getAttribute("disabled") === "" : !0);
    return ee(d, async () => {
      await oe(() => {
        m.value = c.value.length && d.value < c.value.length ? c.value[d.value] : null, _.value = c.value.length && d.value > 1 ? c.value[d.value - 2] : null;
      });
    }), ee(c, async () => {
      await oe(() => {
        m.value = c.value.length && d.value < c.value.length ? c.value[d.value] : null, _.value = c.value.length && d.value > 1 ? c.value[d.value - 2] : null;
      });
    }), Lp({
      modelValue: d,
      changeModelValue: (h) => {
        d.value = h;
      },
      orientation: s,
      dir: i,
      linear: r,
      totalStepperItems: u
    }), (h, E) => (b(), S(o(O), {
      role: "group",
      "aria-label": "progress",
      as: h.as,
      "as-child": h.asChild,
      "data-linear": o(r) ? "" : void 0,
      "data-orientation": h.orientation
    }, {
      default: y(() => [
        w(h.$slots, "default", {
          modelValue: o(d),
          totalSteps: u.value.size,
          isNextDisabled: C.value,
          isPrevDisabled: $.value,
          isFirstStep: f.value,
          isLastStep: v.value,
          goToStep: g,
          nextStep: () => g((o(d) ?? 1) + 1),
          prevStep: () => g((o(d) ?? 1) - 1)
        }),
        Ye("div", Np, " Step " + De(o(d)) + " of " + De(u.value.size), 1)
      ]),
      _: 3
    }, 8, ["as", "as-child", "data-linear", "data-orientation"]));
  }
}), [Sa, zp] = te("StepperItem"), fg = /* @__PURE__ */ x({
  __name: "StepperItem",
  props: {
    step: {},
    disabled: { type: Boolean, default: !1 },
    completed: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { disabled: e, step: n, completed: l } = ae(t), { forwardRef: s } = R(), r = ko(), i = ge(void 0, "radix-vue-stepper-item-title"), u = ge(void 0, "radix-vue-stepper-item-description"), d = B(() => l.value ? "completed" : r.modelValue.value === n.value ? "active" : r.modelValue.value > n.value ? "completed" : "inactive"), c = B(() => e.value ? !1 : r.linear.value ? n.value <= r.modelValue.value || n.value === r.modelValue.value + 1 : !0);
    return zp({
      titleId: i,
      descriptionId: u,
      state: d,
      disabled: e,
      step: n,
      isFocusable: c
    }), (f, v) => (b(), S(o(O), {
      ref: o(s),
      as: f.as,
      "as-child": f.asChild,
      "aria-current": d.value === "active" ? "true" : void 0,
      "data-state": d.value,
      disabled: o(e) || !c.value ? "" : void 0,
      "data-disabled": o(e) || !c.value ? "" : void 0,
      "data-orientation": o(r).orientation.value
    }, {
      default: y(() => [
        w(f.$slots, "default", { state: d.value })
      ]),
      _: 3
    }, 8, ["as", "as-child", "aria-current", "data-state", "disabled", "data-disabled", "data-orientation"]));
  }
}), pg = /* @__PURE__ */ x({
  __name: "StepperTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = ko(), e = Sa(), n = nt(), l = B(() => Array.from(t.totalStepperItems.value));
    function s(d) {
      if (!e.disabled.value) {
        if (t.linear.value) {
          if ((e.step.value <= t.modelValue.value || e.step.value === t.modelValue.value + 1) && d.ctrlKey === !1) {
            t.changeModelValue(e.step.value);
            return;
          }
        } else if (d.ctrlKey === !1) {
          t.changeModelValue(e.step.value);
          return;
        }
        d.preventDefault();
      }
    }
    function r(d) {
      d.preventDefault(), !e.disabled.value && ((d.key === n.ENTER || d.key === n.SPACE) && !d.ctrlKey && !d.shiftKey && t.changeModelValue(e.step.value), [n.ARROW_LEFT, n.ARROW_RIGHT, n.ARROW_UP, n.ARROW_DOWN].includes(d.key) && At(d, me(), void 0, {
        itemsArray: l.value,
        focus: !0,
        loop: !1,
        arrowKeyOptions: t.orientation.value,
        dir: t.dir.value
      }));
    }
    const { forwardRef: i, currentElement: u } = R();
    return le(() => {
      t.totalStepperItems.value.add(u.value);
    }), Be(() => {
      t.totalStepperItems.value.delete(u.value);
    }), (d, c) => (b(), S(o(O), {
      ref: o(i),
      type: d.as === "button" ? "button" : void 0,
      as: d.as,
      "as-child": d.asChild,
      "data-state": o(e).state.value,
      disabled: o(e).disabled.value || !o(e).isFocusable.value ? "" : void 0,
      "data-disabled": o(e).disabled.value || !o(e).isFocusable.value ? "" : void 0,
      "data-orientation": o(t).orientation.value,
      tabindex: o(e).isFocusable.value ? 0 : -1,
      "aria-describedby": o(e).descriptionId,
      "aria-labelledby": o(e).titleId,
      onMousedown: ue(s, ["left"]),
      onKeydown: ie(r, ["enter", "space", "left", "right", "up", "down"])
    }, {
      default: y(() => [
        w(d.$slots, "default")
      ]),
      _: 3
    }, 8, ["type", "as", "as-child", "data-state", "disabled", "data-disabled", "data-orientation", "tabindex", "aria-describedby", "aria-labelledby"]));
  }
}), vg = /* @__PURE__ */ x({
  __name: "StepperDescription",
  props: {
    asChild: { type: Boolean },
    as: { default: "p" }
  },
  setup(a) {
    const t = a;
    R();
    const e = Sa();
    return (n, l) => (b(), S(o(O), k(t, {
      id: o(e).descriptionId
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), mg = /* @__PURE__ */ x({
  __name: "StepperTitle",
  props: {
    asChild: { type: Boolean },
    as: { default: "h4" }
  },
  setup(a) {
    const t = a, e = Sa();
    return R(), (n, l) => (b(), S(o(O), k(t, {
      id: o(e).titleId
    }), {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), hg = /* @__PURE__ */ x({
  __name: "StepperIndicator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = Sa();
    return R(), (n, l) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(n.$slots, "default", {}, () => [
          ye(" Step " + De(o(e).step.value), 1)
        ])
      ]),
      _: 3
    }, 16));
  }
}), yg = /* @__PURE__ */ x({
  __name: "StepperSeparator",
  props: {
    orientation: {},
    decorative: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = ko(), n = Sa();
    return R(), (l, s) => (b(), S(o(ap), k(t, {
      decorative: "",
      orientation: o(e).orientation.value,
      "data-state": o(n).state.value
    }), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16, ["orientation", "data-state"]));
  }
}), Kp = ["name", "disabled", "required", "value", "checked", "data-state", "data-disabled"], [Hp, Wp] = te("SwitchRoot"), gg = /* @__PURE__ */ x({
  __name: "SwitchRoot",
  props: {
    defaultChecked: { type: Boolean },
    checked: { type: Boolean, default: void 0 },
    disabled: { type: Boolean },
    required: { type: Boolean },
    name: {},
    id: {},
    value: { default: "on" },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  emits: ["update:checked"],
  setup(a, { emit: t }) {
    const e = a, n = t, { disabled: l } = ae(e), s = ne(e, "checked", n, {
      defaultValue: e.defaultChecked,
      passive: e.checked === void 0
    });
    function r() {
      l.value || (s.value = !s.value);
    }
    const { forwardRef: i, currentElement: u } = R(), d = at(u), c = B(() => {
      var f;
      return e.id && u.value ? (f = document.querySelector(`[for="${e.id}"]`)) == null ? void 0 : f.innerText : void 0;
    });
    return Wp({
      checked: s,
      toggleCheck: r,
      disabled: l
    }), (f, v) => (b(), ve(_e, null, [
      q(o(O), k(f.$attrs, {
        id: f.id,
        ref: o(i),
        role: "switch",
        type: f.as === "button" ? "button" : void 0,
        value: f.value,
        "aria-label": f.$attrs["aria-label"] || c.value,
        "aria-checked": o(s),
        "aria-required": f.required,
        "data-state": o(s) ? "checked" : "unchecked",
        "data-disabled": o(l) ? "" : void 0,
        "as-child": f.asChild,
        as: f.as,
        disabled: o(l),
        onClick: r,
        onKeydown: ie(ue(r, ["prevent"]), ["enter"])
      }), {
        default: y(() => [
          w(f.$slots, "default", { checked: o(s) })
        ]),
        _: 3
      }, 16, ["id", "type", "value", "aria-label", "aria-checked", "aria-required", "data-state", "data-disabled", "as-child", "as", "disabled", "onKeydown"]),
      o(d) ? (b(), ve("input", {
        key: 0,
        type: "checkbox",
        name: f.name,
        tabindex: "-1",
        "aria-hidden": "true",
        disabled: o(l),
        required: f.required,
        value: f.value,
        checked: !!o(s),
        "data-state": o(s) ? "checked" : "unchecked",
        "data-disabled": o(l) ? "" : void 0,
        style: {
          transform: "translateX(-100%)",
          position: "absolute",
          pointerEvents: "none",
          opacity: 0,
          margin: 0
        }
      }, null, 8, Kp)) : ce("", !0)
    ], 64));
  }
}), bg = /* @__PURE__ */ x({
  __name: "SwitchThumb",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = Hp();
    return R(), (e, n) => {
      var l;
      return b(), S(o(O), {
        "data-state": (l = o(t).checked) != null && l.value ? "checked" : "unchecked",
        "data-disabled": o(t).disabled.value ? "" : void 0,
        "as-child": e.asChild,
        as: e.as
      }, {
        default: y(() => [
          w(e.$slots, "default")
        ]),
        _: 3
      }, 8, ["data-state", "data-disabled", "as-child", "as"]);
    };
  }
}), [vn, jp] = te("TabsRoot"), Cg = /* @__PURE__ */ x({
  __name: "TabsRoot",
  props: {
    defaultValue: {},
    orientation: { default: "horizontal" },
    dir: {},
    activationMode: { default: "automatic" },
    modelValue: {},
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { orientation: l, dir: s } = ae(e), r = we(s);
    R();
    const i = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: e.modelValue === void 0
    }), u = T();
    return jp({
      modelValue: i,
      changeModelValue: (d) => {
        i.value = d;
      },
      orientation: l,
      dir: r,
      activationMode: e.activationMode,
      baseId: ge(void 0, "radix-vue-tabs"),
      tabsList: u
    }), (d, c) => (b(), S(o(O), {
      dir: o(r),
      "data-orientation": o(l),
      "as-child": d.asChild,
      as: d.as
    }, {
      default: y(() => [
        w(d.$slots, "default", { modelValue: o(i) })
      ]),
      _: 3
    }, 8, ["dir", "data-orientation", "as-child", "as"]));
  }
}), wg = /* @__PURE__ */ x({
  __name: "TabsList",
  props: {
    loop: { type: Boolean, default: !0 },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { loop: e } = ae(t), { forwardRef: n, currentElement: l } = R(), s = vn();
    return s.tabsList = l, (r, i) => (b(), S(o(Ft), {
      "as-child": "",
      orientation: o(s).orientation.value,
      dir: o(s).dir.value,
      loop: o(e)
    }, {
      default: y(() => [
        q(o(O), {
          ref: o(n),
          role: "tablist",
          "as-child": r.asChild,
          as: r.as,
          "aria-orientation": o(s).orientation.value
        }, {
          default: y(() => [
            w(r.$slots, "default")
          ]),
          _: 3
        }, 8, ["as-child", "as", "aria-orientation"])
      ]),
      _: 3
    }, 8, ["orientation", "dir", "loop"]));
  }
});
function ir(a, t) {
  return `${a}-trigger-${t}`;
}
function ur(a, t) {
  return `${a}-content-${t}`;
}
const _g = /* @__PURE__ */ x({
  __name: "TabsContent",
  props: {
    value: {},
    forceMount: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), n = vn(), l = B(() => ir(n.baseId, t.value)), s = B(() => ur(n.baseId, t.value)), r = B(() => t.value === n.modelValue.value), i = T(r.value);
    return le(() => {
      requestAnimationFrame(() => {
        i.value = !1;
      });
    }), (u, d) => (b(), S(o(Pe), {
      present: r.value,
      "force-mount": ""
    }, {
      default: y(({ present: c }) => [
        q(o(O), {
          id: s.value,
          ref: o(e),
          "as-child": u.asChild,
          as: u.as,
          role: "tabpanel",
          "data-state": r.value ? "active" : "inactive",
          "data-orientation": o(n).orientation.value,
          "aria-labelledby": l.value,
          hidden: !c.value,
          tabindex: "0",
          style: Me({
            animationDuration: i.value ? "0s" : void 0
          })
        }, {
          default: y(() => [
            u.forceMount || r.value ? w(u.$slots, "default", { key: 0 }) : ce("", !0)
          ]),
          _: 2
        }, 1032, ["id", "as-child", "as", "data-state", "data-orientation", "aria-labelledby", "hidden", "style"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), xg = /* @__PURE__ */ x({
  __name: "TabsTrigger",
  props: {
    value: {},
    disabled: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), n = vn(), l = B(() => ir(n.baseId, t.value)), s = B(() => ur(n.baseId, t.value)), r = B(() => t.value === n.modelValue.value);
    return (i, u) => (b(), S(o(Nt), {
      "as-child": "",
      focusable: !i.disabled,
      active: r.value
    }, {
      default: y(() => [
        q(o(O), {
          id: l.value,
          ref: o(e),
          role: "tab",
          type: i.as === "button" ? "button" : void 0,
          as: i.as,
          "as-child": i.asChild,
          "aria-selected": r.value ? "true" : "false",
          "aria-controls": s.value,
          "data-state": r.value ? "active" : "inactive",
          disabled: i.disabled,
          "data-disabled": i.disabled ? "" : void 0,
          "data-orientation": o(n).orientation.value,
          onMousedown: u[0] || (u[0] = ue((d) => {
            !i.disabled && d.ctrlKey === !1 ? o(n).changeModelValue(i.value) : d.preventDefault();
          }, ["left"])),
          onKeydown: u[1] || (u[1] = ie((d) => o(n).changeModelValue(i.value), ["enter", "space"])),
          onFocus: u[2] || (u[2] = () => {
            const d = o(n).activationMode !== "manual";
            !r.value && !i.disabled && d && o(n).changeModelValue(i.value);
          })
        }, {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 8, ["id", "type", "as", "as-child", "aria-selected", "aria-controls", "data-state", "disabled", "data-disabled", "data-orientation"])
      ]),
      _: 3
    }, 8, ["focusable", "active"]));
  }
}), Sg = /* @__PURE__ */ x({
  __name: "TabsIndicator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = vn();
    R();
    const n = T(), l = T({
      size: null,
      position: null
    });
    ee(() => [e.modelValue.value, e == null ? void 0 : e.dir.value], async () => {
      await oe(), s();
    }, { immediate: !0 }), tt([e.tabsList, n], s);
    function s() {
      var r;
      n.value = (r = e.tabsList.value) == null ? void 0 : r.querySelector('[role="tab"][data-state="active"]'), n.value && (e.orientation.value === "horizontal" ? l.value = {
        size: n.value.offsetWidth,
        position: n.value.offsetLeft
      } : l.value = {
        size: n.value.offsetHeight,
        position: n.value.offsetTop
      });
    }
    return (r, i) => typeof l.value.size == "number" ? (b(), S(o(O), k({ key: 0 }, t, {
      style: {
        "--radix-tabs-indicator-size": `${l.value.size}px`,
        "--radix-tabs-indicator-position": `${l.value.position}px`
      }
    }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16, ["style"])) : ce("", !0);
  }
}), [mn, Up] = te("TagsInputRoot"), Eg = /* @__PURE__ */ x({
  __name: "TagsInputRoot",
  props: {
    modelValue: {},
    defaultValue: { default: () => [] },
    addOnPaste: { type: Boolean },
    addOnTab: { type: Boolean },
    addOnBlur: { type: Boolean },
    duplicate: { type: Boolean },
    disabled: { type: Boolean },
    delimiter: { default: "," },
    dir: {},
    max: { default: 0 },
    required: { type: Boolean },
    name: {},
    id: {},
    convertValue: {},
    displayValue: { type: Function, default: (a) => a.toString() },
    asChild: { type: Boolean },
    as: {}
  },
  emits: ["update:modelValue", "invalid"],
  setup(a, { emit: t }) {
    const e = a, n = t, { addOnPaste: l, disabled: s, delimiter: r, max: i, id: u, dir: d, addOnBlur: c, addOnTab: f } = ae(e), v = we(d), p = ne(e, "modelValue", n, {
      defaultValue: e.defaultValue,
      passive: !0,
      deep: !0
    }), { forwardRef: g, currentElement: m } = R(), { focused: _ } = Si(m), C = at(m), { getItems: $ } = Ca(), h = T(), E = T(!1);
    return Up({
      modelValue: p,
      onAddValue: (P) => {
        const D = p.value.length > 0 && typeof p.value[0] == "object", I = p.value.length > 0 && typeof e.defaultValue[0] == "object";
        if ((D || I) && typeof e.convertValue != "function")
          throw new Error("You must provide a `convertValue` function when using objects as values.");
        const M = e.convertValue ? e.convertValue(P) : P;
        if (p.value.length >= i.value && i.value)
          return n("invalid", M), !1;
        if (e.duplicate)
          return p.value = [...p.value, M], !0;
        if (p.value.includes(M))
          E.value = !0;
        else
          return p.value = [...p.value, M], !0;
        return n("invalid", M), !1;
      },
      onRemoveValue: (P) => {
        P !== -1 && (p.value = p.value.filter((D, I) => I !== P));
      },
      onInputKeydown: (P) => {
        const D = P.target, I = $().map((V) => V.ref).filter((V) => V.dataset.disabled !== "");
        if (!I.length)
          return;
        const M = I.at(-1);
        switch (P.key) {
          case "Delete":
          case "Backspace": {
            if (D.selectionStart !== 0 || D.selectionEnd !== 0)
              break;
            if (h.value) {
              const V = I.findIndex((A) => A === h.value);
              p.value = p.value.filter((A, F) => F !== V), h.value = h.value === M ? I.at(V - 1) : I.at(V + 1), P.preventDefault();
            } else P.key === "Backspace" && (h.value = M, P.preventDefault());
            break;
          }
          case "Home":
          case "End":
          case "ArrowRight":
          case "ArrowLeft": {
            const V = P.key === "ArrowRight" && v.value === "ltr" || P.key === "ArrowLeft" && v.value === "rtl", A = !V;
            if (D.selectionStart !== 0 || D.selectionEnd !== 0)
              break;
            if (A && !h.value)
              h.value = M, P.preventDefault();
            else if (V && M && h.value === M)
              h.value = void 0, P.preventDefault();
            else if (h.value) {
              const F = At(P, h.value, void 0, {
                itemsArray: I,
                loop: !1,
                dir: v.value
              });
              F && (h.value = F), P.preventDefault();
            }
            break;
          }
          case "ArrowUp":
          case "ArrowDown": {
            h.value && P.preventDefault();
            break;
          }
          default:
            h.value = void 0;
        }
      },
      selectedElement: h,
      isInvalidInput: E,
      addOnPaste: l,
      addOnBlur: c,
      addOnTab: f,
      dir: v,
      disabled: s,
      delimiter: r,
      max: i,
      id: u,
      displayValue: e.displayValue
    }), (P, D) => (b(), S(o(wa), null, {
      default: y(() => [
        q(o(O), {
          ref: o(g),
          dir: o(v),
          as: P.as,
          "as-child": P.asChild,
          "data-invalid": E.value ? "" : void 0,
          "data-disabled": o(s) ? "" : void 0,
          "data-focused": o(_) ? "" : void 0
        }, {
          default: y(() => [
            w(P.$slots, "default", { modelValue: o(p) }),
            o(C) && P.name ? (b(), S(o(no), {
              key: 0,
              name: P.name,
              value: o(p),
              required: P.required,
              disabled: o(s)
            }, null, 8, ["name", "value", "required", "disabled"])) : ce("", !0)
          ]),
          _: 3
        }, 8, ["dir", "as", "as-child", "data-invalid", "data-disabled", "data-focused"])
      ]),
      _: 3
    }));
  }
}), Pg = /* @__PURE__ */ x({
  __name: "TagsInputInput",
  props: {
    placeholder: {},
    autoFocus: { type: Boolean },
    maxLength: {},
    asChild: { type: Boolean },
    as: { default: "input" }
  },
  setup(a) {
    const t = a, e = mn(), { forwardRef: n, currentElement: l } = R();
    function s(p) {
      if (!e.addOnBlur.value)
        return;
      const g = p.target;
      if (!g.value)
        return;
      e.onAddValue(g.value) && (g.value = "");
    }
    function r(p) {
      e.addOnTab.value && c(p);
    }
    const i = T(!1);
    function u() {
      i.value = !0;
    }
    function d() {
      requestAnimationFrame(() => {
        i.value = !1;
      });
    }
    async function c(p) {
      if (i.value || (await oe(), p.defaultPrevented))
        return;
      const g = p.target;
      if (!g.value)
        return;
      e.onAddValue(g.value) && (g.value = ""), p.preventDefault();
    }
    function f(p) {
      e.isInvalidInput.value = !1;
      const g = e.delimiter.value;
      if (g === p.data) {
        const m = p.target;
        m.value = m.value.replaceAll(g, ""), e.onAddValue(m.value) && (m.value = "");
      }
    }
    function v(p) {
      if (e.addOnPaste.value) {
        p.preventDefault();
        const g = p.clipboardData;
        if (!g)
          return;
        const m = g.getData("text");
        e.delimiter.value ? m.split(e.delimiter.value).forEach((C) => {
          e.onAddValue(C);
        }) : e.onAddValue(m);
      }
    }
    return le(() => {
      const p = l.value.nodeName === "INPUT" ? l.value : l.value.querySelector("input");
      p && setTimeout(() => {
        t.autoFocus && (p == null || p.focus());
      }, 1);
    }), (p, g) => {
      var m;
      return b(), S(o(O), {
        id: (m = o(e).id) == null ? void 0 : m.value,
        ref: o(n),
        type: "text",
        autocomplete: "off",
        autocorrect: "off",
        autocapitalize: "off",
        as: p.as,
        "as-child": p.asChild,
        maxlength: p.maxLength,
        placeholder: p.placeholder,
        disabled: o(e).disabled.value,
        "data-invalid": o(e).isInvalidInput.value ? "" : void 0,
        onInput: f,
        onKeydown: [
          ie(c, ["enter"]),
          ie(r, ["tab"]),
          o(e).onInputKeydown
        ],
        onBlur: s,
        onCompositionstart: u,
        onCompositionend: d,
        onPaste: v
      }, {
        default: y(() => [
          w(p.$slots, "default")
        ]),
        _: 3
      }, 8, ["id", "as", "as-child", "maxlength", "placeholder", "disabled", "data-invalid", "onKeydown"]);
    };
  }
}), [dr, Gp] = te("TagsInputItem"), Dg = /* @__PURE__ */ x({
  __name: "TagsInputItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { value: e } = ae(t), n = mn(), { forwardRef: l, currentElement: s } = R(), r = B(() => n.selectedElement.value === s.value), i = B(() => t.disabled || n.disabled.value), u = Gp({
      value: e,
      isSelected: r,
      disabled: i,
      textId: "",
      displayValue: B(() => n.displayValue(e.value))
    });
    return (d, c) => (b(), S(o(Qt), null, {
      default: y(() => [
        q(o(O), {
          ref: o(l),
          as: d.as,
          "as-child": d.asChild,
          "aria-labelledby": o(u).textId,
          "aria-current": r.value,
          "data-disabled": i.value ? "" : void 0,
          "data-state": r.value ? "active" : "inactive"
        }, {
          default: y(() => [
            w(d.$slots, "default")
          ]),
          _: 3
        }, 8, ["as", "as-child", "aria-labelledby", "aria-current", "data-disabled", "data-state"])
      ]),
      _: 3
    }));
  }
}), $g = /* @__PURE__ */ x({
  __name: "TagsInputItemText",
  props: {
    asChild: { type: Boolean },
    as: { default: "span" }
  },
  setup(a) {
    const t = a, e = dr();
    return R(), e.textId || (e.textId = ge(void 0, "radix-vue-tags-input-item-text")), (n, l) => (b(), S(o(O), k(t, {
      id: o(e).textId
    }), {
      default: y(() => [
        w(n.$slots, "default", {}, () => [
          ye(De(o(e).displayValue.value), 1)
        ])
      ]),
      _: 3
    }, 16, ["id"]));
  }
}), Bg = /* @__PURE__ */ x({
  __name: "TagsInputItemDelete",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = mn(), n = dr(), l = B(() => {
      var r;
      return ((r = n.disabled) == null ? void 0 : r.value) || e.disabled.value;
    });
    function s() {
      if (l.value)
        return;
      const r = e.modelValue.value.findIndex((i) => i === n.value.value);
      e.onRemoveValue(r);
    }
    return (r, i) => (b(), S(o(O), k({ tabindex: "-1" }, t, {
      "aria-labelledby": o(n).textId,
      "aria-current": o(n).isSelected.value,
      "data-state": o(n).isSelected.value ? "active" : "inactive",
      "data-disabled": l.value ? "" : void 0,
      type: r.as === "button" ? "button" : void 0,
      onClick: s
    }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16, ["aria-labelledby", "aria-current", "data-state", "data-disabled", "type"]));
  }
}), Ig = /* @__PURE__ */ x({
  __name: "TagsInputClear",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a;
    R();
    const e = mn();
    function n() {
      e.disabled.value || (e.modelValue.value = []);
    }
    return (l, s) => (b(), S(o(O), k(t, {
      type: l.as === "button" ? "button" : void 0,
      "data-disabled": o(e).disabled.value ? "" : void 0,
      onClick: n
    }), {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }, 16, ["type", "data-disabled"]));
  }
}), [hn, qp] = te("ToastProvider"), Tg = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ToastProvider",
  props: {
    label: { default: "Notification" },
    duration: { default: 5e3 },
    swipeDirection: { default: "right" },
    swipeThreshold: { default: 50 }
  },
  setup(a) {
    const t = a, { label: e, duration: n, swipeDirection: l, swipeThreshold: s } = ae(t), r = T(), i = T(0), u = T(!1), d = T(!1);
    if (t.label && typeof t.label == "string" && !t.label.trim()) {
      const c = "Invalid prop `label` supplied to `ToastProvider`. Expected non-empty `string`.";
      throw new Error(c);
    }
    return qp({
      label: e,
      duration: n,
      swipeDirection: l,
      swipeThreshold: s,
      toastCount: i,
      viewport: r,
      onViewportChange(c) {
        r.value = c;
      },
      onToastAdd() {
        i.value++;
      },
      onToastRemove() {
        i.value--;
      },
      isFocusedToastEscapeKeyDownRef: u,
      isClosePausedRef: d
    }), (c, f) => w(c.$slots, "default");
  }
}), Yp = "toast.swipeStart", Xp = "toast.swipeMove", Zp = "toast.swipeCancel", Jp = "toast.swipeEnd", Mn = "toast.viewportPause", Vn = "toast.viewportResume";
function ka(a, t, e) {
  const n = e.originalEvent.currentTarget, l = new CustomEvent(a, {
    bubbles: !1,
    cancelable: !0,
    detail: e
  });
  t && n.addEventListener(a, t, { once: !0 }), n.dispatchEvent(l);
}
function rl(a, t, e = 0) {
  const n = Math.abs(a.x), l = Math.abs(a.y), s = n > l;
  return t === "left" || t === "right" ? s && n > e : !s && l > e;
}
function Qp(a) {
  return a.nodeType === a.ELEMENT_NODE;
}
function cr(a) {
  const t = [];
  return Array.from(a.childNodes).forEach((n) => {
    if (n.nodeType === n.TEXT_NODE && n.textContent && t.push(n.textContent), Qp(n)) {
      const l = n.ariaHidden || n.hidden || n.style.display === "none", s = n.dataset.radixToastAnnounceExclude === "";
      if (!l)
        if (s) {
          const r = n.dataset.radixToastAnnounceAlt;
          r && t.push(r);
        } else
          t.push(...cr(n));
    }
  }), t;
}
const ev = /* @__PURE__ */ x({
  __name: "ToastAnnounce",
  setup(a) {
    const t = hn(), e = gi(1e3), n = T(!1);
    return Ol(() => {
      n.value = !0;
    }), (l, s) => o(e) || n.value ? (b(), S(o(Jt), { key: 0 }, {
      default: y(() => [
        ye(De(o(t).label.value) + " ", 1),
        w(l.$slots, "default")
      ]),
      _: 3
    })) : ce("", !0);
  }
}), [tv, av] = te("ToastRoot"), nv = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ToastRootImpl",
  props: {
    type: {},
    open: { type: Boolean, default: !1 },
    duration: {},
    asChild: { type: Boolean },
    as: { default: "li" }
  },
  emits: ["close", "escapeKeyDown", "pause", "resume", "swipeStart", "swipeMove", "swipeCancel", "swipeEnd"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l, currentElement: s } = R(), r = hn(), i = T(null), u = T(null), d = B(
      () => typeof e.duration == "number" ? e.duration : r.duration.value
    ), c = T(0), f = T(d.value), v = T(0), p = T(d.value), g = Ol(() => {
      const $ = (/* @__PURE__ */ new Date()).getTime() - c.value;
      p.value = Math.max(f.value - $, 0);
    }, { fpsLimit: 60 });
    function m($) {
      $ <= 0 || $ === Number.POSITIVE_INFINITY || Je && (window.clearTimeout(v.value), c.value = (/* @__PURE__ */ new Date()).getTime(), v.value = window.setTimeout(_, $));
    }
    function _() {
      var h, E;
      ((h = s.value) == null ? void 0 : h.contains(me())) && ((E = r.viewport.value) == null || E.focus()), r.isClosePausedRef.value = !1, n("close");
    }
    const C = B(() => s.value ? cr(s.value) : null);
    if (e.type && !["foreground", "background"].includes(e.type)) {
      const $ = "Invalid prop `type` supplied to `Toast`. Expected `foreground | background`.";
      throw new Error($);
    }
    return Ce(($) => {
      const h = r.viewport.value;
      if (h) {
        const E = () => {
          m(f.value), g.resume(), n("resume");
        }, P = () => {
          const D = (/* @__PURE__ */ new Date()).getTime() - c.value;
          f.value = f.value - D, window.clearTimeout(v.value), g.pause(), n("pause");
        };
        return h.addEventListener(Mn, P), h.addEventListener(Vn, E), () => {
          h.removeEventListener(Mn, P), h.removeEventListener(Vn, E);
        };
      }
    }), ee(() => [e.open, d.value], () => {
      f.value = d.value, e.open && !r.isClosePausedRef.value && m(d.value);
    }, { immediate: !0 }), Gn("Escape", ($) => {
      n("escapeKeyDown", $), $.defaultPrevented || (r.isFocusedToastEscapeKeyDownRef.value = !0, _());
    }), le(() => {
      r.onToastAdd();
    }), Be(() => {
      r.onToastRemove();
    }), av({ onClose: _ }), ($, h) => (b(), ve(_e, null, [
      C.value ? (b(), S(ev, {
        key: 0,
        role: "alert",
        "aria-live": $.type === "foreground" ? "assertive" : "polite",
        "aria-atomic": "true"
      }, {
        default: y(() => [
          ye(De(C.value), 1)
        ]),
        _: 1
      }, 8, ["aria-live"])) : ce("", !0),
      o(r).viewport.value ? (b(), S(qt, {
        key: 1,
        to: o(r).viewport.value
      }, [
        q(o(O), k({
          ref: o(l),
          role: "alert",
          "aria-live": "off",
          "aria-atomic": "true",
          tabindex: "0",
          "data-radix-vue-collection-item": ""
        }, $.$attrs, {
          as: $.as,
          "as-child": $.asChild,
          "data-state": $.open ? "open" : "closed",
          "data-swipe-direction": o(r).swipeDirection.value,
          style: { userSelect: "none", touchAction: "none" },
          onPointerdown: h[0] || (h[0] = ue((E) => {
            i.value = { x: E.clientX, y: E.clientY };
          }, ["left"])),
          onPointermove: h[1] || (h[1] = (E) => {
            if (!i.value) return;
            const P = E.clientX - i.value.x, D = E.clientY - i.value.y, I = !!u.value, M = ["left", "right"].includes(o(r).swipeDirection.value), V = ["left", "up"].includes(o(r).swipeDirection.value) ? Math.min : Math.max, A = M ? V(0, P) : 0, F = M ? 0 : V(0, D), j = E.pointerType === "touch" ? 10 : 2, H = { x: A, y: F }, Q = { originalEvent: E, delta: H };
            I ? (u.value = H, o(ka)(o(Xp), (G) => n("swipeMove", G), Q)) : o(rl)(H, o(r).swipeDirection.value, j) ? (u.value = H, o(ka)(o(Yp), (G) => n("swipeStart", G), Q), E.target.setPointerCapture(E.pointerId)) : (Math.abs(P) > j || Math.abs(D) > j) && (i.value = null);
          }),
          onPointerup: h[2] || (h[2] = (E) => {
            const P = u.value, D = E.target;
            if (D.hasPointerCapture(E.pointerId) && D.releasePointerCapture(E.pointerId), u.value = null, i.value = null, P) {
              const I = E.currentTarget, M = { originalEvent: E, delta: P };
              o(rl)(P, o(r).swipeDirection.value, o(r).swipeThreshold.value) ? o(ka)(o(Jp), (V) => n("swipeEnd", V), M) : o(ka)(o(Zp), (V) => n("swipeCancel", V), M), I == null || I.addEventListener("click", (V) => V.preventDefault(), {
                once: !0
              });
            }
          })
        }), {
          default: y(() => [
            w($.$slots, "default", {
              remaining: p.value,
              duration: d.value
            })
          ]),
          _: 3
        }, 16, ["as", "as-child", "data-state", "data-swipe-direction"])
      ], 8, ["to"])) : ce("", !0)
    ], 64));
  }
}), Rg = /* @__PURE__ */ x({
  __name: "ToastRoot",
  props: {
    defaultOpen: { type: Boolean, default: !0 },
    forceMount: { type: Boolean },
    type: { default: "foreground" },
    open: { type: Boolean, default: void 0 },
    duration: {},
    asChild: { type: Boolean },
    as: { default: "li" }
  },
  emits: ["escapeKeyDown", "pause", "resume", "swipeStart", "swipeMove", "swipeCancel", "swipeEnd", "update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t, { forwardRef: l } = R(), s = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    });
    return (r, i) => (b(), S(o(Pe), {
      present: r.forceMount || o(s)
    }, {
      default: y(() => [
        q(nv, k({
          ref: o(l),
          open: o(s),
          type: r.type,
          as: r.as,
          "as-child": r.asChild,
          duration: r.duration
        }, r.$attrs, {
          onClose: i[0] || (i[0] = (u) => s.value = !1),
          onPause: i[1] || (i[1] = (u) => n("pause")),
          onResume: i[2] || (i[2] = (u) => n("resume")),
          onEscapeKeyDown: i[3] || (i[3] = (u) => n("escapeKeyDown", u)),
          onSwipeStart: i[4] || (i[4] = (u) => {
            n("swipeStart", u), u.currentTarget.setAttribute("data-swipe", "start");
          }),
          onSwipeMove: i[5] || (i[5] = (u) => {
            const { x: d, y: c } = u.detail.delta, f = u.currentTarget;
            f.setAttribute("data-swipe", "move"), f.style.setProperty("--radix-toast-swipe-move-x", `${d}px`), f.style.setProperty("--radix-toast-swipe-move-y", `${c}px`);
          }),
          onSwipeCancel: i[6] || (i[6] = (u) => {
            const d = u.currentTarget;
            d.setAttribute("data-swipe", "cancel"), d.style.removeProperty("--radix-toast-swipe-move-x"), d.style.removeProperty("--radix-toast-swipe-move-y"), d.style.removeProperty("--radix-toast-swipe-end-x"), d.style.removeProperty("--radix-toast-swipe-end-y");
          }),
          onSwipeEnd: i[7] || (i[7] = (u) => {
            const { x: d, y: c } = u.detail.delta, f = u.currentTarget;
            f.setAttribute("data-swipe", "end"), f.style.removeProperty("--radix-toast-swipe-move-x"), f.style.removeProperty("--radix-toast-swipe-move-y"), f.style.setProperty("--radix-toast-swipe-end-x", `${d}px`), f.style.setProperty("--radix-toast-swipe-end-y", `${c}px`), s.value = !1;
          })
        }), {
          default: y(({ remaining: u, duration: d }) => [
            w(r.$slots, "default", {
              remaining: u,
              duration: d,
              open: o(s)
            })
          ]),
          _: 3
        }, 16, ["open", "type", "as", "as-child", "duration"])
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Ag = /* @__PURE__ */ x({
  __name: "ToastPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), fr = /* @__PURE__ */ x({
  __name: "ToastAnnounceExclude",
  props: {
    altText: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    return (t, e) => (b(), S(o(O), {
      as: t.as,
      "as-child": t.asChild,
      "data-radix-toast-announce-exclude": "",
      "data-radix-toast-announce-alt": t.altText || void 0
    }, {
      default: y(() => [
        w(t.$slots, "default")
      ]),
      _: 3
    }, 8, ["as", "as-child", "data-radix-toast-announce-alt"]));
  }
}), ov = /* @__PURE__ */ x({
  __name: "ToastClose",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = tv(), { forwardRef: n } = R();
    return (l, s) => (b(), S(fr, { "as-child": "" }, {
      default: y(() => [
        q(o(O), k(t, {
          ref: o(n),
          type: l.as === "button" ? "button" : void 0,
          onClick: s[0] || (s[0] = (r) => o(e).onClose())
        }), {
          default: y(() => [
            w(l.$slots, "default")
          ]),
          _: 3
        }, 16, ["type"])
      ]),
      _: 3
    }));
  }
}), Og = /* @__PURE__ */ x({
  __name: "ToastAction",
  props: {
    altText: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    if (!a.altText)
      throw new Error("Missing prop `altText` expected on `ToastAction`");
    const { forwardRef: e } = R();
    return (n, l) => n.altText ? (b(), S(fr, {
      key: 0,
      "alt-text": n.altText,
      "as-child": ""
    }, {
      default: y(() => [
        q(ov, {
          ref: o(e),
          as: n.as,
          "as-child": n.asChild
        }, {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 8, ["as", "as-child"])
      ]),
      _: 3
    }, 8, ["alt-text"])) : ce("", !0);
  }
}), il = /* @__PURE__ */ x({
  __name: "FocusProxy",
  emits: ["focusFromOutsideViewport"],
  setup(a, { emit: t }) {
    const e = t, n = hn();
    return (l, s) => (b(), S(o(Jt), {
      "aria-hidden": "true",
      tabindex: "0",
      style: { position: "fixed" },
      onFocus: s[0] || (s[0] = (r) => {
        var d;
        const i = r.relatedTarget;
        !((d = o(n).viewport.value) != null && d.contains(i)) && e("focusFromOutsideViewport");
      })
    }, {
      default: y(() => [
        w(l.$slots, "default")
      ]),
      _: 3
    }));
  }
}), kg = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "ToastViewport",
  props: {
    hotkey: { default: () => ["F8"] },
    label: { type: [String, Function], default: "Notifications ({hotkey})" },
    asChild: { type: Boolean },
    as: { default: "ol" }
  },
  setup(a) {
    const t = a, { hotkey: e, label: n } = ae(t), { forwardRef: l, currentElement: s } = R(), { createCollection: r } = Fe(), i = r(s), u = hn(), d = B(() => u.toastCount.value > 0), c = T(), f = T(), v = B(() => e.value.join("+").replace(/Key/g, "").replace(/Digit/g, ""));
    Gn(e.value, () => {
      s.value.focus();
    }), le(() => {
      u.onViewportChange(s.value);
    }), Ce((g) => {
      const m = s.value;
      if (d.value && m) {
        const _ = () => {
          if (!u.isClosePausedRef.value) {
            const P = new CustomEvent(Mn);
            m.dispatchEvent(P), u.isClosePausedRef.value = !0;
          }
        }, C = () => {
          if (u.isClosePausedRef.value) {
            const P = new CustomEvent(Vn);
            m.dispatchEvent(P), u.isClosePausedRef.value = !1;
          }
        }, $ = (P) => {
          !m.contains(P.relatedTarget) && C();
        }, h = () => {
          m.contains(me()) || C();
        }, E = (P) => {
          var M, V, A;
          const D = P.altKey || P.ctrlKey || P.metaKey;
          if (P.key === "Tab" && !D) {
            const F = me(), j = P.shiftKey;
            if (P.target === m && j) {
              (M = c.value) == null || M.focus();
              return;
            }
            const G = p({ tabbingDirection: j ? "backwards" : "forwards" }), J = G.findIndex((z) => z === F);
            Ma(G.slice(J + 1)) ? P.preventDefault() : j ? (V = c.value) == null || V.focus() : (A = f.value) == null || A.focus();
          }
        };
        m.addEventListener("focusin", _), m.addEventListener("focusout", $), m.addEventListener("pointermove", _), m.addEventListener("pointerleave", h), m.addEventListener("keydown", E), window.addEventListener("blur", _), window.addEventListener("focus", C), g(() => {
          m.removeEventListener("focusin", _), m.removeEventListener("focusout", $), m.removeEventListener("pointermove", _), m.removeEventListener("pointerleave", h), m.removeEventListener("keydown", E), window.removeEventListener("blur", _), window.removeEventListener("focus", C);
        });
      }
    });
    function p({ tabbingDirection: g }) {
      const _ = i.value.map((C) => {
        const $ = [C, ...eo(C)];
        return g === "forwards" ? $ : $.reverse();
      });
      return (g === "forwards" ? _.reverse() : _).flat();
    }
    return (g, m) => (b(), S(o(ru), {
      role: "region",
      "aria-label": typeof o(n) == "string" ? o(n).replace("{hotkey}", v.value) : o(n)(v.value),
      tabindex: "-1",
      style: Me({
        // incase list has size when empty (e.g. padding), we remove pointer events so
        // it doesn't prevent interactions with page elements that it overlays
        pointerEvents: d.value ? void 0 : "none"
      })
    }, {
      default: y(() => [
        d.value ? (b(), S(il, {
          key: 0,
          ref: (_) => {
            c.value = o($e)(_);
          },
          onFocusFromOutsideViewport: m[0] || (m[0] = () => {
            const _ = p({
              tabbingDirection: "forwards"
            });
            o(Ma)(_);
          })
        }, null, 512)) : ce("", !0),
        q(o(O), k({
          ref: o(l),
          tabindex: "-1",
          as: g.as,
          "as-child": g.asChild
        }, g.$attrs), {
          default: y(() => [
            w(g.$slots, "default")
          ]),
          _: 3
        }, 16, ["as", "as-child"]),
        d.value ? (b(), S(il, {
          key: 1,
          ref: (_) => {
            f.value = o($e)(_);
          },
          onFocusFromOutsideViewport: m[1] || (m[1] = () => {
            const _ = p({
              tabbingDirection: "backwards"
            });
            o(Ma)(_);
          })
        }, null, 512)) : ce("", !0)
      ]),
      _: 3
    }, 8, ["aria-label", "style"]));
  }
}), Mg = /* @__PURE__ */ x({
  __name: "ToastTitle",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Vg = /* @__PURE__ */ x({
  __name: "ToastDescription",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(O), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), lv = /* @__PURE__ */ x({
  __name: "Toggle",
  props: {
    defaultValue: { type: Boolean },
    pressed: { type: Boolean, default: void 0 },
    disabled: { type: Boolean, default: !1 },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  emits: ["update:pressed"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    const l = ne(e, "pressed", n, {
      defaultValue: e.defaultValue,
      passive: e.pressed === void 0
    });
    function s() {
      l.value = !l.value;
    }
    const r = B(() => l.value ? "on" : "off");
    return (i, u) => (b(), S(o(O), {
      type: i.as === "button" ? "button" : void 0,
      "as-child": e.asChild,
      as: i.as,
      "aria-pressed": o(l),
      "data-state": r.value,
      "data-disabled": i.disabled ? "" : void 0,
      disabled: i.disabled,
      onClick: s
    }, {
      default: y(() => [
        w(i.$slots, "default", { pressed: o(l) })
      ]),
      _: 3
    }, 8, ["type", "as-child", "as", "aria-pressed", "data-state", "data-disabled", "disabled"]));
  }
}), [sv, rv] = te("ToggleGroupRoot"), iv = /* @__PURE__ */ x({
  __name: "ToggleGroupRoot",
  props: {
    rovingFocus: { type: Boolean, default: !0 },
    disabled: { type: Boolean, default: !1 },
    orientation: {},
    dir: {},
    loop: { type: Boolean, default: !0 },
    asChild: { type: Boolean },
    as: {},
    type: {},
    modelValue: {},
    defaultValue: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, { loop: l, rovingFocus: s, disabled: r, dir: i } = ae(e), u = we(i), { forwardRef: d } = R(), { modelValue: c, changeModelValue: f, isSingle: v } = Wl(e, n);
    return rv({
      isSingle: v,
      modelValue: c,
      changeModelValue: f,
      dir: u,
      orientation: e.orientation,
      loop: l,
      rovingFocus: s,
      disabled: r
    }), (p, g) => (b(), S(Xe(o(s) ? o(Ft) : o(O)), {
      "as-child": "",
      orientation: o(s) ? p.orientation : void 0,
      dir: o(u),
      loop: o(s) ? o(l) : void 0
    }, {
      default: y(() => [
        q(o(O), {
          ref: o(d),
          role: "group",
          "as-child": p.asChild,
          as: p.as
        }, {
          default: y(() => [
            w(p.$slots, "default", { modelValue: o(c) })
          ]),
          _: 3
        }, 8, ["as-child", "as"])
      ]),
      _: 3
    }, 8, ["orientation", "dir", "loop"]));
  }
}), uv = /* @__PURE__ */ x({
  __name: "ToggleGroupItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = sv(), n = B(() => {
      var i;
      return ((i = e.disabled) == null ? void 0 : i.value) || t.disabled;
    }), l = B(() => {
      var i;
      return (i = e.modelValue.value) == null ? void 0 : i.includes(t.value);
    }), s = B(() => {
      var i;
      return e.isSingle.value ? e.modelValue.value === t.value : (i = e.modelValue.value) == null ? void 0 : i.includes(t.value);
    }), { forwardRef: r } = R();
    return (i, u) => (b(), S(Xe(o(e).rovingFocus.value ? o(Nt) : o(O)), {
      "as-child": "",
      focusable: !n.value,
      active: l.value
    }, {
      default: y(() => [
        q(o(lv), k(t, {
          ref: o(r),
          disabled: n.value,
          pressed: s.value,
          "onUpdate:pressed": u[0] || (u[0] = (d) => o(e).changeModelValue(i.value))
        }), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16, ["disabled", "pressed"])
      ]),
      _: 3
    }, 8, ["focusable", "active"]));
  }
}), [pr, dv] = te("ToolbarRoot"), Fg = /* @__PURE__ */ x({
  __name: "ToolbarRoot",
  props: {
    orientation: { default: "horizontal" },
    dir: {},
    loop: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { orientation: e, dir: n } = ae(t), l = we(n), { forwardRef: s } = R();
    return dv({ orientation: e, dir: l }), (r, i) => (b(), S(o(Ft), {
      "as-child": "",
      orientation: o(e),
      dir: o(l),
      loop: r.loop
    }, {
      default: y(() => [
        q(o(O), {
          ref: o(s),
          role: "toolbar",
          "aria-orientation": o(e),
          "as-child": r.asChild,
          as: r.as
        }, {
          default: y(() => [
            w(r.$slots, "default")
          ]),
          _: 3
        }, 8, ["aria-orientation", "as-child", "as"])
      ]),
      _: 3
    }, 8, ["orientation", "dir", "loop"]));
  }
}), cv = /* @__PURE__ */ x({
  __name: "ToolbarButton",
  props: {
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, { forwardRef: e } = R();
    return (n, l) => (b(), S(o(Nt), {
      "as-child": "",
      focusable: !n.disabled
    }, {
      default: y(() => [
        q(o(O), k({
          ref: o(e),
          type: n.as === "button" ? "button" : void 0
        }, t), {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 16, ["type"])
      ]),
      _: 3
    }, 8, ["focusable"]));
  }
}), Ng = /* @__PURE__ */ x({
  __name: "ToolbarLink",
  props: {
    asChild: { type: Boolean },
    as: { default: "a" }
  },
  setup(a) {
    const t = a, { forwardRef: e } = R();
    return (n, l) => (b(), S(o(Nt), {
      "as-child": "",
      focusable: ""
    }, {
      default: y(() => [
        q(o(O), k(t, {
          ref: o(e),
          onKeydown: l[0] || (l[0] = (s) => {
            var r;
            s.key === " " && ((r = s.currentTarget) == null || r.click());
          })
        }), {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }));
  }
}), Lg = /* @__PURE__ */ x({
  __name: "ToolbarToggleGroup",
  props: {
    rovingFocus: { type: Boolean },
    disabled: { type: Boolean },
    orientation: {},
    dir: {},
    loop: { type: Boolean },
    asChild: { type: Boolean },
    as: {},
    type: {},
    modelValue: {},
    defaultValue: {}
  },
  emits: ["update:modelValue"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = pr(), s = Te(n);
    return R(), (r, i) => (b(), S(o(iv), k({ ...e, ...o(s) }, {
      "data-orientation": o(l).orientation.value,
      dir: o(l).dir.value,
      "roving-focus": !1
    }), {
      default: y(() => [
        w(r.$slots, "default")
      ]),
      _: 3
    }, 16, ["data-orientation", "dir"]));
  }
}), zg = /* @__PURE__ */ x({
  __name: "ToolbarToggleItem",
  props: {
    value: {},
    disabled: { type: Boolean },
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R();
    return (n, l) => (b(), S(cv, { "as-child": "" }, {
      default: y(() => [
        q(o(uv), k(t, { ref: o(e) }), {
          default: y(() => [
            w(n.$slots, "default")
          ]),
          _: 3
        }, 16)
      ]),
      _: 3
    }));
  }
}), Kg = /* @__PURE__ */ x({
  __name: "ToolbarSeparator",
  props: {
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, e = pr();
    return R(), (n, l) => (b(), S(Ms, {
      orientation: o(e).orientation.value,
      "as-child": t.asChild,
      as: n.as
    }, {
      default: y(() => [
        w(n.$slots, "default")
      ]),
      _: 3
    }, 8, ["orientation", "as-child", "as"]));
  }
}), vr = "tooltip.open", [Mo, fv] = te("TooltipProvider"), Hg = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "TooltipProvider",
  props: {
    delayDuration: { default: 700 },
    skipDelayDuration: { default: 300 },
    disableHoverableContent: { type: Boolean, default: !1 },
    disableClosingTrigger: { type: Boolean },
    disabled: { type: Boolean },
    ignoreNonKeyboardFocus: { type: Boolean, default: !1 }
  },
  setup(a) {
    const t = a, { delayDuration: e, skipDelayDuration: n, disableHoverableContent: l, disableClosingTrigger: s, ignoreNonKeyboardFocus: r, disabled: i } = ae(t);
    R();
    const u = T(!0), d = T(!1), { start: c, stop: f } = Un(() => {
      u.value = !0;
    }, n, { immediate: !1 });
    return fv({
      isOpenDelayed: u,
      delayDuration: e,
      onOpen() {
        f(), u.value = !1;
      },
      onClose() {
        c();
      },
      isPointerInTransitRef: d,
      disableHoverableContent: l,
      disableClosingTrigger: s,
      disabled: i,
      ignoreNonKeyboardFocus: r
    }), (v, p) => w(v.$slots, "default");
  }
}), [yn, pv] = te("TooltipRoot"), Wg = /* @__PURE__ */ x({
  __name: "TooltipRoot",
  props: {
    defaultOpen: { type: Boolean, default: !1 },
    open: { type: Boolean, default: void 0 },
    delayDuration: { default: void 0 },
    disableHoverableContent: { type: Boolean, default: void 0 },
    disableClosingTrigger: { type: Boolean, default: void 0 },
    disabled: { type: Boolean, default: void 0 },
    ignoreNonKeyboardFocus: { type: Boolean, default: void 0 }
  },
  emits: ["update:open"],
  setup(a, { emit: t }) {
    const e = a, n = t;
    R();
    const l = Mo(), s = B(() => e.disableHoverableContent ?? l.disableHoverableContent.value), r = B(() => e.disableClosingTrigger ?? l.disableClosingTrigger.value), i = B(() => e.disabled ?? l.disabled.value), u = B(() => e.delayDuration ?? l.delayDuration.value), d = B(() => e.ignoreNonKeyboardFocus ?? l.ignoreNonKeyboardFocus.value), c = ne(e, "open", n, {
      defaultValue: e.defaultOpen,
      passive: e.open === void 0
    });
    ee(c, (h) => {
      l.onClose && (h ? (l.onOpen(), document.dispatchEvent(new CustomEvent(vr))) : l.onClose());
    });
    const f = T(!1), v = T(), p = B(() => c.value ? f.value ? "delayed-open" : "instant-open" : "closed"), { start: g, stop: m } = Un(() => {
      f.value = !0, c.value = !0;
    }, u, { immediate: !1 });
    function _() {
      m(), f.value = !1, c.value = !0;
    }
    function C() {
      m(), c.value = !1;
    }
    function $() {
      g();
    }
    return pv({
      contentId: "",
      open: c,
      stateAttribute: p,
      trigger: v,
      onTriggerChange(h) {
        v.value = h;
      },
      onTriggerEnter() {
        l.isOpenDelayed.value ? $() : _();
      },
      onTriggerLeave() {
        s.value ? C() : m();
      },
      onOpen: _,
      onClose: C,
      disableHoverableContent: s,
      disableClosingTrigger: r,
      disabled: i,
      ignoreNonKeyboardFocus: d
    }), (h, E) => (b(), S(o(kt), null, {
      default: y(() => [
        w(h.$slots, "default", { open: o(c) })
      ]),
      _: 3
    }));
  }
}), jg = /* @__PURE__ */ x({
  __name: "TooltipTrigger",
  props: {
    asChild: { type: Boolean },
    as: { default: "button" }
  },
  setup(a) {
    const t = a, e = yn(), n = Mo();
    e.contentId || (e.contentId = ge(void 0, "radix-vue-tooltip-content"));
    const { forwardRef: l, currentElement: s } = R(), r = T(!1), i = T(!1), u = B(() => e.disabled.value ? {} : {
      click: m,
      focus: p,
      pointermove: f,
      pointerleave: v,
      pointerdown: c,
      blur: g
    });
    le(() => {
      e.onTriggerChange(s.value);
    });
    function d() {
      setTimeout(() => {
        r.value = !1;
      }, 1);
    }
    function c() {
      r.value = !0, document.addEventListener("pointerup", d, { once: !0 });
    }
    function f(_) {
      _.pointerType !== "touch" && !i.value && !n.isPointerInTransitRef.value && (e.onTriggerEnter(), i.value = !0);
    }
    function v() {
      e.onTriggerLeave(), i.value = !1;
    }
    function p(_) {
      var C, $;
      r.value || e.ignoreNonKeyboardFocus.value && !(($ = (C = _.target).matches) != null && $.call(C, ":focus-visible")) || e.onOpen();
    }
    function g() {
      e.onClose();
    }
    function m() {
      e.disableClosingTrigger.value || e.onClose();
    }
    return (_, C) => (b(), S(o(Mt), { "as-child": "" }, {
      default: y(() => [
        q(o(O), k({
          ref: o(l),
          "aria-describedby": o(e).open.value ? o(e).contentId : void 0,
          "data-state": o(e).stateAttribute.value,
          as: _.as,
          "as-child": t.asChild,
          "data-grace-area-trigger": ""
        }, Kn(u.value)), {
          default: y(() => [
            w(_.$slots, "default")
          ]),
          _: 3
        }, 16, ["aria-describedby", "data-state", "as", "as-child"])
      ]),
      _: 3
    }));
  }
}), mr = /* @__PURE__ */ x({
  __name: "TooltipContentImpl",
  props: {
    ariaLabel: {},
    asChild: { type: Boolean },
    as: {},
    side: { default: "top" },
    sideOffset: { default: 0 },
    align: { default: "center" },
    alignOffset: {},
    avoidCollisions: { type: Boolean, default: !0 },
    collisionBoundary: { default: () => [] },
    collisionPadding: { default: 0 },
    arrowPadding: { default: 0 },
    sticky: { default: "partial" },
    hideWhenDetached: { type: Boolean, default: !1 }
  },
  emits: ["escapeKeyDown", "pointerDownOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = yn(), { forwardRef: s } = R(), r = Ua(), i = B(() => {
      var c;
      return (c = r.default) == null ? void 0 : c.call(r);
    }), u = B(() => {
      var v;
      if (e.ariaLabel)
        return e.ariaLabel;
      let c = "";
      function f(p) {
        typeof p.children == "string" && p.type !== hl ? c += p.children : Array.isArray(p.children) && p.children.forEach((g) => f(g));
      }
      return (v = i.value) == null || v.forEach((p) => f(p)), c;
    }), d = B(() => {
      const { ariaLabel: c, ...f } = e;
      return f;
    });
    return le(() => {
      He(window, "scroll", (c) => {
        const f = c.target;
        f != null && f.contains(l.trigger.value) && l.onClose();
      }), He(window, vr, l.onClose);
    }), (c, f) => (b(), S(o(Ct), {
      "as-child": "",
      "disable-outside-pointer-events": !1,
      onEscapeKeyDown: f[0] || (f[0] = (v) => n("escapeKeyDown", v)),
      onPointerDownOutside: f[1] || (f[1] = (v) => {
        var p;
        o(l).disableClosingTrigger.value && ((p = o(l).trigger.value) != null && p.contains(v.target)) && v.preventDefault(), n("pointerDownOutside", v);
      }),
      onFocusOutside: f[2] || (f[2] = ue(() => {
      }, ["prevent"])),
      onDismiss: f[3] || (f[3] = (v) => o(l).onClose())
    }, {
      default: y(() => [
        q(o(It), k({
          ref: o(s),
          "data-state": o(l).stateAttribute.value
        }, { ...c.$attrs, ...d.value }, { style: {
          "--radix-tooltip-content-transform-origin": "var(--radix-popper-transform-origin)",
          "--radix-tooltip-content-available-width": "var(--radix-popper-available-width)",
          "--radix-tooltip-content-available-height": "var(--radix-popper-available-height)",
          "--radix-tooltip-trigger-width": "var(--radix-popper-anchor-width)",
          "--radix-tooltip-trigger-height": "var(--radix-popper-anchor-height)"
        } }), {
          default: y(() => [
            w(c.$slots, "default"),
            q(o(Jt), {
              id: o(l).contentId,
              role: "tooltip"
            }, {
              default: y(() => [
                ye(De(u.value), 1)
              ]),
              _: 1
            }, 8, ["id"])
          ]),
          _: 3
        }, 16, ["data-state"])
      ]),
      _: 3
    }));
  }
}), vv = /* @__PURE__ */ x({
  __name: "TooltipContentHoverable",
  props: {
    ariaLabel: {},
    asChild: { type: Boolean },
    as: {},
    side: {},
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean }
  },
  setup(a) {
    const e = Ot(a), { forwardRef: n, currentElement: l } = R(), { trigger: s, onClose: r } = yn(), i = Mo(), { isPointerInTransit: u, onPointerExit: d } = Fl(s, l);
    return i.isPointerInTransitRef = u, d(() => {
      r();
    }), (c, f) => (b(), S(mr, k({ ref: o(n) }, o(e)), {
      default: y(() => [
        w(c.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), Ug = /* @__PURE__ */ x({
  __name: "TooltipContent",
  props: {
    forceMount: { type: Boolean },
    ariaLabel: {},
    asChild: { type: Boolean },
    as: {},
    side: { default: "top" },
    sideOffset: {},
    align: {},
    alignOffset: {},
    avoidCollisions: { type: Boolean },
    collisionBoundary: {},
    collisionPadding: {},
    arrowPadding: {},
    sticky: {},
    hideWhenDetached: { type: Boolean }
  },
  emits: ["escapeKeyDown", "pointerDownOutside"],
  setup(a, { emit: t }) {
    const e = a, n = t, l = yn(), s = Se(e, n), { forwardRef: r } = R();
    return (i, u) => (b(), S(o(Pe), {
      present: i.forceMount || o(l).open.value
    }, {
      default: y(() => [
        (b(), S(Xe(o(l).disableHoverableContent.value ? mr : vv), k({ ref: o(r) }, o(s)), {
          default: y(() => [
            w(i.$slots, "default")
          ]),
          _: 3
        }, 16))
      ]),
      _: 3
    }, 8, ["present"]));
  }
}), Gg = /* @__PURE__ */ x({
  __name: "TooltipArrow",
  props: {
    width: { default: 10 },
    height: { default: 5 },
    asChild: { type: Boolean },
    as: { default: "svg" }
  },
  setup(a) {
    const t = a;
    return R(), (e, n) => (b(), S(o(Zt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
}), qg = /* @__PURE__ */ x({
  __name: "TooltipPortal",
  props: {
    to: {},
    disabled: { type: Boolean },
    forceMount: { type: Boolean }
  },
  setup(a) {
    const t = a;
    return (e, n) => (b(), S(o(rt), W(U(t)), {
      default: y(() => [
        w(e.$slots, "default")
      ]),
      _: 3
    }, 16));
  }
});
function Vo(a) {
  return a.reduce((t, e) => (t.push(e), e.children && t.push(...Vo(e.children)), t), []);
}
const [hr, mv] = te("TreeRoot"), Yg = /* @__PURE__ */ x({
  __name: "TreeRoot",
  props: {
    modelValue: {},
    defaultValue: {},
    items: {},
    expanded: {},
    defaultExpanded: {},
    getKey: {},
    getChildren: { type: Function, default: (a) => a.children },
    selectionBehavior: { default: "toggle" },
    multiple: { type: Boolean },
    dir: {},
    disabled: { type: Boolean },
    propagateSelect: { type: Boolean },
    asChild: { type: Boolean },
    as: { default: "ul" }
  },
  emits: ["update:modelValue", "update:expanded"],
  setup(a, { emit: t }) {
    const e = a, n = t, { items: l, multiple: s, disabled: r, propagateSelect: i, dir: u } = ae(e), { handleTypeaheadSearch: d } = ba(), c = we(u), f = T(), v = T(!1), p = ua(), g = ne(e, "modelValue", n, {
      // @ts-expect-error idk
      defaultValue: e.defaultValue ?? (s.value ? [] : void 0),
      passive: e.modelValue === void 0,
      deep: !0
    }), m = ne(e, "expanded", n, {
      // @ts-expect-error idk
      defaultValue: e.defaultExpanded ?? [],
      passive: e.expanded === void 0,
      deep: !0
    }), { onSelectItem: _, handleMultipleReplace: C } = ji(g, e), $ = B(() => s.value && Array.isArray(g.value) ? g.value.map((I) => e.getKey(I)) : [e.getKey(g.value ?? {})]);
    function h(I, M = 1, V) {
      return I.reduce((A, F, j) => {
        const H = e.getKey(F), Q = e.getChildren(F), G = m.value.includes(H), J = {
          _id: H,
          value: F,
          index: j,
          level: M,
          parentItem: V,
          hasChildren: !!Q,
          bind: {
            value: F,
            level: M,
            "aria-setsize": I.length,
            "aria-posinset": j + 1
          }
        };
        return A.push(J), Q && G && A.push(...h(Q, M + 1, F)), A;
      }, []);
    }
    const E = B(() => {
      const I = e.items;
      return m.value.map((M) => M), h(I ?? []);
    });
    function P(I) {
      var M;
      if (v.value)
        p.trigger(I);
      else {
        const V = (M = f.value) == null ? void 0 : M.getItems().map((A) => A.ref);
        d(I.key, V);
      }
    }
    function D(I) {
      if (v.value)
        return;
      const M = en[I.key];
      oe(() => {
        var V;
        C(
          M,
          me(),
          (V = f.value) == null ? void 0 : V.getItems,
          E.value.map((A) => A.value)
        );
      });
    }
    return mv({
      modelValue: g,
      selectedKeys: $,
      onSelect: (I) => {
        var A;
        const M = (F) => e.getKey(F ?? {}) === e.getKey(I), V = e.multiple && Array.isArray(g.value) ? ((A = g.value) == null ? void 0 : A.findIndex(M)) !== -1 : void 0;
        if (_(I, M), e.propagateSelect && e.multiple && Array.isArray(g.value)) {
          const F = Vo(e.getChildren(I) ?? []);
          V ? g.value = [...g.value].filter((j) => !F.some((H) => e.getKey(j ?? {}) === e.getKey(H))) : g.value = [...g.value, ...F];
        }
      },
      expanded: m,
      onToggle(I) {
        if (!(I ? e.getChildren(I) : void 0))
          return;
        const V = e.getKey(I) ?? I;
        m.value.includes(V) ? m.value = m.value.filter((A) => A !== V) : m.value.push(V);
      },
      getKey: e.getKey,
      getChildren: e.getChildren,
      items: l,
      expandedItems: E,
      disabled: r,
      multiple: s,
      dir: c,
      propagateSelect: i,
      isVirtual: v,
      virtualKeydownHook: p,
      handleMultipleReplace: C
    }), (I, M) => (b(), S(o(Ft), {
      ref_key: "rovingFocusGroupRef",
      ref: f,
      "as-child": "",
      orientation: "vertical",
      dir: o(c)
    }, {
      default: y(() => [
        q(o(O), {
          role: "tree",
          as: I.as,
          "as-child": I.asChild,
          "aria-multiselectable": o(s) ? !0 : void 0,
          onKeydown: [
            P,
            ie(ue(D, ["shift"]), ["up", "down"])
          ]
        }, {
          default: y(() => [
            w(I.$slots, "default", {
              flattenItems: E.value,
              modelValue: o(g),
              expanded: o(m)
            })
          ]),
          _: 3
        }, 8, ["as", "as-child", "aria-multiselectable", "onKeydown"])
      ]),
      _: 3
    }, 8, ["dir"]));
  }
}), hv = "tree.select", yv = "tree.toggle", Xg = /* @__PURE__ */ x({
  inheritAttrs: !1,
  __name: "TreeItem",
  props: {
    value: {},
    level: {},
    asChild: { type: Boolean },
    as: { default: "li" }
  },
  emits: ["select", "toggle"],
  setup(a, { expose: t, emit: e }) {
    const n = a, l = e, s = hr(), { getItems: r } = ea(), i = B(() => !!s.getChildren(n.value)), u = B(() => {
      const C = s.getKey(n.value);
      return s.expanded.value.includes(C);
    }), d = B(() => {
      const C = s.getKey(n.value);
      return s.selectedKeys.value.includes(C);
    }), c = B(() => {
      if (s.propagateSelect.value && d.value && i.value && Array.isArray(s.modelValue.value))
        return !Vo(s.getChildren(n.value) || []).every(($) => s.modelValue.value.find((h) => s.getKey(h) === s.getKey($)));
    });
    function f(C) {
      if (i.value)
        if (u.value) {
          const $ = r().map((I) => I.ref), h = me(), E = $.indexOf(h), D = [...$].slice(E).find((I) => Number(I.getAttribute("data-indent")) === n.level + 1);
          D && D.focus();
        } else
          _(C);
    }
    function v(C) {
      if (u.value)
        _(C);
      else {
        const $ = r().map((I) => I.ref), h = me(), E = $.indexOf(h), D = [...$].slice(0, E).reverse().find((I) => Number(I.getAttribute("data-indent")) === n.level - 1);
        D && D.focus();
      }
    }
    async function p(C) {
      l("select", C), !(C != null && C.defaultPrevented) && s.onSelect(n.value);
    }
    async function g(C) {
      l("toggle", C), !(C != null && C.defaultPrevented) && s.onToggle(n.value);
    }
    async function m(C) {
      if (!C)
        return;
      const $ = { originalEvent: C, value: n.value, isExpanded: u.value, isSelected: d.value };
      jt(hv, p, $);
    }
    async function _(C) {
      if (!C)
        return;
      const $ = { originalEvent: C, value: n.value, isExpanded: u.value, isSelected: d.value };
      jt(yv, g, $);
    }
    return t({
      isExpanded: u,
      isSelected: d,
      isIndeterminate: c,
      handleToggle: () => s.onToggle(n.value),
      handleSelect: () => s.onSelect(n.value)
    }), (C, $) => (b(), S(o(Nt), {
      "as-child": "",
      value: C.value,
      "allow-shift-key": ""
    }, {
      default: y(() => [
        q(o(O), k(C.$attrs, {
          role: "treeitem",
          as: C.as,
          "as-child": C.asChild,
          "aria-selected": d.value,
          "aria-expanded": i.value ? u.value : void 0,
          "aria-level": C.level,
          "data-indent": C.level,
          "data-selected": d.value ? "" : void 0,
          "data-expanded": u.value ? "" : void 0,
          onKeydown: [
            ie(ue(m, ["self", "prevent"]), ["enter", "space"]),
            $[0] || ($[0] = ie(ue((h) => o(s).dir.value === "ltr" ? f(h) : v(h), ["prevent"]), ["right"])),
            $[1] || ($[1] = ie(ue((h) => o(s).dir.value === "ltr" ? v(h) : f(h), ["prevent"]), ["left"]))
          ],
          onClick: $[2] || ($[2] = ue((h) => {
            m(h), _(h);
          }, ["stop"]))
        }), {
          default: y(() => [
            w(C.$slots, "default", {
              isExpanded: u.value,
              isSelected: d.value,
              isIndeterminate: c.value,
              handleSelect: () => o(s).onSelect(C.value),
              handleToggle: () => o(s).onToggle(C.value)
            })
          ]),
          _: 3
        }, 16, ["as", "as-child", "aria-selected", "aria-expanded", "aria-level", "data-indent", "data-selected", "data-expanded", "onKeydown"])
      ]),
      _: 3
    }, 8, ["value"]));
  }
}), Zg = /* @__PURE__ */ x({
  __name: "TreeVirtualizer",
  props: {
    estimateSize: {},
    textContent: { type: Function }
  },
  setup(a) {
    const t = a, e = Ua(), n = hr(), l = kl(), { getItems: s } = ea(), r = Tt("", 1e3), i = B(() => {
      const v = (p) => t.textContent ? t.textContent(p) : p.toString().toLowerCase();
      return n.expandedItems.value.map((p, g) => ({
        index: g,
        textContent: v(p.value)
      }));
    });
    n.isVirtual.value = !0;
    const u = B(() => {
      const v = l.value;
      if (v) {
        const p = window.getComputedStyle(v);
        return {
          start: Number.parseFloat(p.paddingBlockStart || p.paddingTop),
          end: Number.parseFloat(p.paddingBlockEnd || p.paddingBottom)
        };
      } else
        return { start: 0, end: 0 };
    }), d = vs(
      {
        get scrollPaddingStart() {
          return u.value.start;
        },
        get scrollPaddingEnd() {
          return u.value.end;
        },
        get count() {
          return n.expandedItems.value.length ?? 0;
        },
        get horizontal() {
          return !1;
        },
        getItemKey(v) {
          return v + n.getKey(n.expandedItems.value[v].value);
        },
        estimateSize() {
          return t.estimateSize ?? 28;
        },
        getScrollElement() {
          return l.value;
        },
        overscan: 12
      }
    ), c = B(() => d.value.getVirtualItems().map((v) => ({
      item: v,
      is: Ln(e.default({
        item: n.expandedItems.value[v.index],
        virtualizer: d.value,
        virtualItem: v
      })[0], {
        "data-index": v.index,
        style: {
          position: "absolute",
          top: 0,
          left: 0,
          transform: `translateY(${v.start}px)`,
          overflowAnchor: "none"
        }
      })
    })));
    function f(v) {
      d.value.scrollToIndex(v, { align: "start" }), requestAnimationFrame(() => {
        const p = l.value.querySelector(`[data-index="${v}"]`);
        p instanceof HTMLElement && p.focus();
      });
    }
    return n.virtualKeydownHook.on((v) => {
      var _;
      const p = v.altKey || v.ctrlKey || v.metaKey;
      if (v.key === "Tab" && !p)
        return;
      const m = en[v.key];
      if (["first", "last"].includes(m)) {
        v.preventDefault();
        const C = m === "first" ? 0 : n.expandedItems.value.length - 1;
        d.value.scrollToIndex(C), requestAnimationFrame(() => {
          const $ = s();
          (m === "first" ? $[0] : $[$.length - 1]).ref.focus();
        });
      } else if (m === "prev" && v.key !== "ArrowUp") {
        const C = me(), $ = Number(C.getAttribute("data-index")), h = Number(C.getAttribute("data-indent")), P = n.expandedItems.value.slice(0, $).map((D, I) => ({ ...D, index: I })).reverse().find((D) => D.level === h - 1);
        P && f(P.index);
      } else if (!m && !p) {
        r.value += v.key;
        const C = Number((_ = me()) == null ? void 0 : _.getAttribute("data-index")), $ = i.value[C].textContent, h = i.value.map((D) => D.textContent), E = Zn(h, r.value, $), P = i.value.find((D) => D.textContent === E);
        P && f(P.index);
      }
      oe(() => {
        v.shiftKey && m && n.handleMultipleReplace(m, me(), s, n.expandedItems.value.map((C) => C.value));
      });
    }), (v, p) => (b(), ve("div", {
      "data-radix-vue-virtualizer": "",
      style: Me({
        position: "relative",
        width: "100%",
        height: `${o(d).getTotalSize()}px`
      })
    }, [
      (b(!0), ve(_e, null, ma(c.value, ({ is: g, item: m }) => (b(), S(Xe(g), {
        key: m.key
      }))), 128))
    ], 4));
  }
}), Jg = /* @__PURE__ */ x({
  __name: "Viewport",
  props: {
    nonce: {},
    asChild: { type: Boolean },
    as: {}
  },
  setup(a) {
    const t = a, { forwardRef: e } = R(), { nonce: n } = ae(t), l = Ja(n);
    return (s, r) => (b(), ve(_e, null, [
      q(o(O), k({ ...s.$attrs, ...t }, {
        ref: o(e),
        "data-radix-viewport": "",
        role: "presentation",
        style: {
          // we use position: 'relative' here on the `viewport` so that when we call
          // `selectedItem.offsetTop` in calculations, the offset is relative to the viewport
          // (independent of the scrollUpButton).
          position: "relative",
          flex: 1,
          overflow: "auto"
        }
      }), {
        default: y(() => [
          w(s.$slots, "default")
        ]),
        _: 3
      }, 16),
      q(o(O), {
        as: "style",
        nonce: o(l)
      }, {
        default: y(() => [
          ye(" /* Hide scrollbars cross-browser and enable momentum scroll for touch devices */ [data-radix-viewport] { scrollbar-width:none; -ms-overflow-style: none; -webkit-overflow-scrolling: touch; } [data-radix-viewport]::-webkit-scrollbar { display: none; } ")
        ]),
        _: 1
      }, 8, ["nonce"])
    ], 64));
  }
});
export {
  Dv as AccordionContent,
  $v as AccordionHeader,
  Pv as AccordionItem,
  Ev as AccordionRoot,
  Bv as AccordionTrigger,
  Nv as AlertDialogAction,
  Mv as AlertDialogCancel,
  Ov as AlertDialogContent,
  Fv as AlertDialogDescription,
  kv as AlertDialogOverlay,
  Av as AlertDialogPortal,
  Tv as AlertDialogRoot,
  Vv as AlertDialogTitle,
  Rv as AlertDialogTrigger,
  Lv as AspectRatio,
  Hv as AvatarFallback,
  Kv as AvatarImage,
  zv as AvatarRoot,
  Gu as CalendarCell,
  ed as CalendarCellTrigger,
  Uu as CalendarGrid,
  Ju as CalendarGridBody,
  Zu as CalendarGridHead,
  Qu as CalendarGridRow,
  qu as CalendarHeadCell,
  Wu as CalendarHeader,
  ju as CalendarHeading,
  Yu as CalendarNext,
  Xu as CalendarPrev,
  Hu as CalendarRoot,
  jv as CheckboxIndicator,
  Wv as CheckboxRoot,
  Zi as CollapsibleContent,
  qi as CollapsibleRoot,
  Yi as CollapsibleTrigger,
  qv as ComboboxAnchor,
  lm as ComboboxArrow,
  Xv as ComboboxCancel,
  Qv as ComboboxContent,
  em as ComboboxEmpty,
  Zv as ComboboxGroup,
  Gv as ComboboxInput,
  am as ComboboxItem,
  nm as ComboboxItemIndicator,
  Jv as ComboboxLabel,
  sm as ComboboxPortal,
  Uv as ComboboxRoot,
  om as ComboboxSeparator,
  Yv as ComboboxTrigger,
  tm as ComboboxViewport,
  xv as ConfigProvider,
  cm as ContextMenuArrow,
  mm as ContextMenuCheckboxItem,
  dm as ContextMenuContent,
  pm as ContextMenuGroup,
  fm as ContextMenuItem,
  hm as ContextMenuItemIndicator,
  ym as ContextMenuLabel,
  um as ContextMenuPortal,
  gm as ContextMenuRadioGroup,
  bm as ContextMenuRadioItem,
  rm as ContextMenuRoot,
  vm as ContextMenuSeparator,
  Cm as ContextMenuSub,
  wm as ContextMenuSubContent,
  _m as ContextMenuSubTrigger,
  im as ContextMenuTrigger,
  nc as DateFieldInput,
  jd as DateFieldRoot,
  Fm as DatePickerAnchor,
  Nm as DatePickerArrow,
  Mm as DatePickerCalendar,
  Pm as DatePickerCell,
  Am as DatePickerCellTrigger,
  Lm as DatePickerClose,
  Km as DatePickerContent,
  Vm as DatePickerField,
  Em as DatePickerGrid,
  Tm as DatePickerGridBody,
  Im as DatePickerGridHead,
  Rm as DatePickerGridRow,
  Dm as DatePickerHeadCell,
  xm as DatePickerHeader,
  Sm as DatePickerHeading,
  Om as DatePickerInput,
  $m as DatePickerNext,
  Bm as DatePickerPrev,
  km as DatePickerRoot,
  zm as DatePickerTrigger,
  dc as DateRangeFieldInput,
  uc as DateRangeFieldRoot,
  oh as DateRangePickerAnchor,
  lh as DateRangePickerArrow,
  ah as DateRangePickerCalendar,
  Um as DateRangePickerCell,
  Qm as DateRangePickerCellTrigger,
  sh as DateRangePickerClose,
  ih as DateRangePickerContent,
  nh as DateRangePickerField,
  jm as DateRangePickerGrid,
  Zm as DateRangePickerGridBody,
  Xm as DateRangePickerGridHead,
  Jm as DateRangePickerGridRow,
  Gm as DateRangePickerHeadCell,
  Hm as DateRangePickerHeader,
  Wm as DateRangePickerHeading,
  eh as DateRangePickerInput,
  qm as DateRangePickerNext,
  Ym as DateRangePickerPrev,
  th as DateRangePickerRoot,
  rh as DateRangePickerTrigger,
  Xl as DialogClose,
  Pu as DialogContent,
  Iu as DialogDescription,
  $u as DialogOverlay,
  Iv as DialogPortal,
  nu as DialogRoot,
  Bu as DialogTitle,
  ou as DialogTrigger,
  ph as DropdownMenuArrow,
  yh as DropdownMenuCheckboxItem,
  fh as DropdownMenuContent,
  mh as DropdownMenuGroup,
  vh as DropdownMenuItem,
  gh as DropdownMenuItemIndicator,
  bh as DropdownMenuLabel,
  ch as DropdownMenuPortal,
  Ch as DropdownMenuRadioGroup,
  wh as DropdownMenuRadioItem,
  uh as DropdownMenuRoot,
  hh as DropdownMenuSeparator,
  _h as DropdownMenuSub,
  xh as DropdownMenuSubContent,
  Sh as DropdownMenuSubTrigger,
  dh as DropdownMenuTrigger,
  Ph as EditableArea,
  Ih as EditableCancelTrigger,
  Th as EditableEditTrigger,
  Dh as EditableInput,
  $h as EditablePreview,
  Eh as EditableRoot,
  Bh as EditableSubmitTrigger,
  Za as FocusScope,
  Mh as HoverCardArrow,
  kh as HoverCardContent,
  Oh as HoverCardPortal,
  Rh as HoverCardRoot,
  Ah as HoverCardTrigger,
  Vh as Label,
  Nh as ListboxContent,
  Lh as ListboxFilter,
  Wh as ListboxGroup,
  jh as ListboxGroupLabel,
  zh as ListboxItem,
  Kh as ListboxItemIndicator,
  Fh as ListboxRoot,
  Hh as ListboxVirtualizer,
  Zh as MenubarArrow,
  ty as MenubarCheckboxItem,
  Xh as MenubarContent,
  Qh as MenubarGroup,
  Jh as MenubarItem,
  ay as MenubarItemIndicator,
  ny as MenubarLabel,
  Gh as MenubarMenu,
  Yh as MenubarPortal,
  oy as MenubarRadioGroup,
  ly as MenubarRadioItem,
  Uh as MenubarRoot,
  ey as MenubarSeparator,
  sy as MenubarSub,
  ry as MenubarSubContent,
  iy as MenubarSubTrigger,
  qh as MenubarTrigger,
  cy as NavigationMenuContent,
  fy as NavigationMenuIndicator,
  dy as NavigationMenuItem,
  py as NavigationMenuLink,
  vy as NavigationMenuList,
  uy as NavigationMenuRoot,
  my as NavigationMenuSub,
  hy as NavigationMenuTrigger,
  yy as NavigationMenuViewport,
  wy as NumberFieldDecrement,
  Cy as NumberFieldIncrement,
  by as NumberFieldInput,
  gy as NumberFieldRoot,
  xy as PaginationEllipsis,
  Sy as PaginationFirst,
  Ey as PaginationLast,
  Py as PaginationList,
  Dy as PaginationListItem,
  $y as PaginationNext,
  By as PaginationPrev,
  _y as PaginationRoot,
  Ty as PinInputInput,
  Iy as PinInputRoot,
  Ds as PopoverAnchor,
  Es as PopoverArrow,
  Ps as PopoverClose,
  Ss as PopoverContent,
  _s as PopoverPortal,
  Cs as PopoverRoot,
  ws as PopoverTrigger,
  O as Primitive,
  Ay as ProgressIndicator,
  Ry as ProgressRoot,
  My as RadioGroupIndicator,
  ky as RadioGroupItem,
  Oy as RadioGroupRoot,
  wf as RangeCalendarCell,
  $f as RangeCalendarCellTrigger,
  Cf as RangeCalendarGrid,
  Pf as RangeCalendarGridBody,
  Ef as RangeCalendarGridHead,
  Df as RangeCalendarGridRow,
  _f as RangeCalendarHeadCell,
  gf as RangeCalendarHeader,
  bf as RangeCalendarHeading,
  xf as RangeCalendarNext,
  Sf as RangeCalendarPrev,
  yf as RangeCalendarRoot,
  zy as ScrollAreaCorner,
  Vy as ScrollAreaRoot,
  Ny as ScrollAreaScrollbar,
  Ly as ScrollAreaThumb,
  Fy as ScrollAreaViewport,
  Uy as SelectArrow,
  jy as SelectContent,
  Xy as SelectGroup,
  ng as SelectIcon,
  qy as SelectItem,
  Yy as SelectItemIndicator,
  Jy as SelectItemText,
  Zy as SelectLabel,
  Wy as SelectPortal,
  Ky as SelectRoot,
  tg as SelectScrollDownButton,
  eg as SelectScrollUpButton,
  Gy as SelectSeparator,
  Hy as SelectTrigger,
  ag as SelectValue,
  Qy as SelectViewport,
  ap as Separator,
  rg as SliderRange,
  og as SliderRoot,
  lg as SliderThumb,
  sg as SliderTrack,
  Jn as Slot,
  ig as SplitterGroup,
  ug as SplitterPanel,
  dg as SplitterResizeHandle,
  vg as StepperDescription,
  hg as StepperIndicator,
  fg as StepperItem,
  cg as StepperRoot,
  yg as StepperSeparator,
  mg as StepperTitle,
  pg as StepperTrigger,
  gg as SwitchRoot,
  bg as SwitchThumb,
  _g as TabsContent,
  Sg as TabsIndicator,
  wg as TabsList,
  Cg as TabsRoot,
  xg as TabsTrigger,
  Ig as TagsInputClear,
  Pg as TagsInputInput,
  Dg as TagsInputItem,
  Bg as TagsInputItemDelete,
  $g as TagsInputItemText,
  Eg as TagsInputRoot,
  Og as ToastAction,
  ov as ToastClose,
  Vg as ToastDescription,
  Ag as ToastPortal,
  Tg as ToastProvider,
  Rg as ToastRoot,
  Mg as ToastTitle,
  kg as ToastViewport,
  lv as Toggle,
  uv as ToggleGroupItem,
  iv as ToggleGroupRoot,
  cv as ToolbarButton,
  Ng as ToolbarLink,
  Fg as ToolbarRoot,
  Kg as ToolbarSeparator,
  Lg as ToolbarToggleGroup,
  zg as ToolbarToggleItem,
  Gg as TooltipArrow,
  Ug as TooltipContent,
  qg as TooltipPortal,
  Hg as TooltipProvider,
  Wg as TooltipRoot,
  jg as TooltipTrigger,
  Xg as TreeItem,
  Yg as TreeRoot,
  Zg as TreeVirtualizer,
  Jg as Viewport,
  Jt as VisuallyHidden,
  te as createContext,
  ya as useBodyScrollLock,
  qn as useDateFormatter,
  Te as useEmitAsProps,
  R as useForwardExpose,
  Ot as useForwardProps,
  Se as useForwardPropsEmits,
  ge as useId,
  zl as useStateMachine,
  Sv as withDefault
};
