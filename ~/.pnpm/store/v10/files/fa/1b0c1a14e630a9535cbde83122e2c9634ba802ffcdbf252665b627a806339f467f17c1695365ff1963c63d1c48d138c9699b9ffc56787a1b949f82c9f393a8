function c(f, o) {
  for (const [e, n] of Object.entries(f))
    n !== null && typeof n == "object" ? (o[e] ?? (o[e] = new n.__proto__.constructor()), c(n, o[e])) : typeof n < "u" && (o[e] = n);
  return o;
}
export {
  c as deepMerge
};
