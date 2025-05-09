const l = () => {
  const e = document.getElementById("headlessui-portal-root");
  if (e)
    e.classList.add("scalar-app"), e.classList.add("scalar-client");
  else {
    const a = new MutationObserver((t) => {
      const d = t.find(
        (s) => Array.from(s.addedNodes).find(
          (o) => o.id === "headlessui-portal-root"
        )
      );
      if (d) {
        const s = d.addedNodes[0];
        s.classList.add("scalar-app"), s.classList.add("scalar-client"), a.disconnect();
      }
    });
    a.observe(document.body, { childList: !0 });
  }
};
export {
  l as addScalarClassesToHeadless
};
