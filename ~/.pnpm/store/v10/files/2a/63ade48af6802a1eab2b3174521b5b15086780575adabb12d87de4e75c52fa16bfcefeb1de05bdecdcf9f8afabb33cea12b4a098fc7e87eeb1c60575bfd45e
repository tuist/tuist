function s(u) {
  return u.flatMap((e) => {
    if (e.key === "value")
      try {
        const r = JSON.parse(e.value);
        return Object.keys(r).map((t) => ({
          key: t,
          value: r[t],
          source: e.source
        }));
      } catch {
      }
    return [e];
  });
}
export {
  s as parseEnvVariables
};
