const n = (t, o = 2) => {
  if (!+t) return "0 Bytes";
  const i = 1024, e = o < 0 ? 0 : o, B = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"], r = Math.floor(Math.log(t) / Math.log(i));
  return `${parseFloat((t / Math.pow(i, r)).toFixed(e))}${B[r]}`;
}, s = (t, o = 2) => t > 1e3 ? (t / 1e3).toFixed(o) + "s" : t + "ms";
export {
  n as formatBytes,
  s as formatMs
};
