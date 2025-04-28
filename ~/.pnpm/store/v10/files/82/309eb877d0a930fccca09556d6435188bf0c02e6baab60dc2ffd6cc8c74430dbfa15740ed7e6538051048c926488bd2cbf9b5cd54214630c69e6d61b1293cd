import { parseZonedDateTime as Y, parseDateTime as _, parseDate as S, toCalendar as Z, getLocalTimeZone as F, CalendarDateTime as L, ZonedDateTime as j, getDayOfWeek as O, startOfMonth as d, endOfMonth as M, startOfYear as h, endOfYear as E } from "@internationalized/date";
function N(t, n) {
  const e = [];
  for (let r = 0; r < t.length; r += n)
    e.push(t.slice(r, r + n));
  return e;
}
function X(t, n) {
  let e;
  return m(n) ? e = Y(t) : w(n) ? e = _(t) : e = S(t), e.calendar !== n.calendar ? Z(e, n.calendar) : e;
}
function $(t, n = F()) {
  return m(t) ? t.toDate() : t.toDate(n);
}
function w(t) {
  return t instanceof L;
}
function m(t) {
  return t instanceof j;
}
function z(t) {
  return w(t) || m(t);
}
function R(t) {
  if (t instanceof Date) {
    const n = t.getFullYear(), e = t.getMonth() + 1;
    return new Date(n, e, 0).getDate();
  } else
    return t.set({ day: 100 }).day;
}
function q(t, n) {
  return t.compare(n) < 0;
}
function P(t, n) {
  return t.compare(n) > 0;
}
function W(t, n) {
  return t.compare(n) <= 0;
}
function G(t, n) {
  return t.compare(n) >= 0;
}
function V(t, n, e) {
  return G(t, n) && W(t, e);
}
function v(t, n, e) {
  return P(t, n) && q(t, e);
}
function H(t, n, e) {
  const r = O(t, e);
  return n > r ? t.subtract({ days: r + 7 - n }) : n === r ? t : t.subtract({ days: r - n });
}
function J(t, n, e) {
  const r = O(t, e), a = n === 0 ? 6 : n - 1;
  return r === a ? t : r > a ? t.add({ days: 7 - r + a }) : t.add({ days: a - r });
}
function b(t, n, e, r) {
  if (e === void 0 && r === void 0)
    return !0;
  let a = t.add({ days: 1 });
  if (r != null && r(a) || e != null && e(a))
    return !1;
  const s = n;
  for (; a.compare(s) < 0; )
    if (a = a.add({ days: 1 }), r != null && r(a) || e != null && e(a))
      return !1;
  return !0;
}
function A(t, n) {
  const e = [];
  let r = t.add({ days: 1 });
  const a = n;
  for (; r.compare(a) < 0; )
    e.push(r), r = r.add({ days: 1 });
  return e;
}
function y(t) {
  const { dateObj: n, weekStartsOn: e, fixedWeeks: r, locale: a } = t, s = R(n), o = Array.from({ length: s }, (D, u) => n.set({ day: u + 1 })), f = d(n), i = M(n), x = H(f, e, a), T = J(i, e, a), l = A(x.subtract({ days: 1 }), f), c = A(i, T.add({ days: 1 })), g = l.length + o.length + c.length;
  if (r && g < 42) {
    const D = 42 - g;
    let u = c[c.length - 1];
    u || (u = M(n));
    const k = Array.from({ length: D }, (K, C) => {
      const I = C + 1;
      return u.add({ days: I });
    });
    c.push(...k);
  }
  const p = l.concat(o, c), B = N(p, 7);
  return {
    value: n,
    cells: p,
    rows: B
  };
}
function U(t) {
  return h(t.subtract({ years: t.year - Math.floor(t.year / 10) * 10 }).set({ day: 1, month: 1 }));
}
function tt(t) {
  return E(t.add({ years: Math.ceil((t.year + 1) / 10) * 10 - t.year - 1 }).set({ day: 35, month: 12 }));
}
function nt(t) {
  const { dateObj: n, startIndex: e, endIndex: r } = t, a = Array.from({ length: Math.abs(e ?? 0) + r }, (s, o) => o <= Math.abs(e ?? 0) ? n.subtract({ years: o }).set({ day: 1, month: 1 }) : n.add({ years: o - r }).set({ day: 1, month: 1 }));
  return a.sort((s, o) => s.year - o.year), a;
}
function et(t) {
  const { dateObj: n, numberOfMonths: e = 1, pagedNavigation: r = !1 } = t;
  return e && r ? Array.from({ length: Math.floor(12 / e) }, (o, f) => d(n.set({ month: f * e + 1 }))) : Array.from({ length: 12 }, (s, o) => d(n.set({ month: o + 1 })));
}
function rt(t) {
  const { numberOfMonths: n, dateObj: e, ...r } = t, a = [];
  if (!n || n === 1)
    return a.push(
      y({
        ...r,
        dateObj: e
      })
    ), a;
  a.push(
    y({
      ...r,
      dateObj: e
    })
  );
  for (let s = 1; s < n; s++) {
    const o = e.add({ months: s });
    a.push(
      y({
        ...r,
        dateObj: o
      })
    );
  }
  return a;
}
function at({ start: t, end: n }) {
  const e = [];
  if (!t || !n)
    return e;
  let r = h(t);
  for (; r.compare(n) <= 0; )
    e.push(r), r = h(r.add({ years: 1 }));
  return e;
}
function ot({ start: t, end: n }) {
  const e = [];
  if (!t || !n)
    return e;
  let r = t;
  for (; r.compare(n) <= 0; )
    e.push(r), r = r.add({ days: 1 });
  return e;
}
export {
  nt as a,
  et as b,
  y as c,
  rt as d,
  tt as e,
  at as f,
  A as g,
  ot as h,
  w as i,
  m as j,
  z as k,
  R as l,
  q as m,
  P as n,
  W as o,
  X as p,
  G as q,
  V as r,
  U as s,
  $ as t,
  v as u,
  H as v,
  J as w,
  b as x
};
