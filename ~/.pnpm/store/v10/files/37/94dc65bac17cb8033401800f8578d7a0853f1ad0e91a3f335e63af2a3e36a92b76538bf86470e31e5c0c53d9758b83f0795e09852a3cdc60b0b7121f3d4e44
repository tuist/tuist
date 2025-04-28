function t(r) {
  return Array.isArray(r) ? `[${r.map((n) => typeof n == "string" ? `"${n.toString().trim()}"` : typeof n == "object" ? JSON.stringify(n) : n === void 0 ? "undefined" : n === null ? "null" : n).join(", ")}]` : typeof r == "object" ? JSON.stringify(r) : r === null ? "null" : r === void 0 ? "undefined" : typeof r == "string" ? r.trim() : r.toString().trim();
}
export {
  t as formatExample
};
