// src/index.ts
var ID = "__live-region__";
function createLiveRegion(opts = {}) {
  const { level = "polite", document: doc = document, root, delay: _delay = 0 } = opts;
  const win = doc.defaultView ?? window;
  const parent = root ?? doc.body;
  function announce(message, delay) {
    const oldRegion = doc.getElementById(ID);
    oldRegion?.remove();
    delay = delay ?? _delay;
    const region = doc.createElement("span");
    region.id = ID;
    region.dataset.liveAnnouncer = "true";
    const role = level !== "assertive" ? "status" : "alert";
    region.setAttribute("aria-live", level);
    region.setAttribute("role", role);
    Object.assign(region.style, {
      border: "0",
      clip: "rect(0 0 0 0)",
      height: "1px",
      margin: "-1px",
      overflow: "hidden",
      padding: "0",
      position: "absolute",
      width: "1px",
      whiteSpace: "nowrap",
      wordWrap: "normal"
    });
    parent.appendChild(region);
    win.setTimeout(() => {
      region.textContent = message;
    }, delay);
  }
  function destroy() {
    const oldRegion = doc.getElementById(ID);
    oldRegion?.remove();
  }
  return {
    announce,
    destroy,
    toJSON() {
      return ID;
    }
  };
}

export { createLiveRegion };
