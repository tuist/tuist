const beamCopies = [...document.querySelectorAll("[data-beam-copy]")];
const supportsHover = window.matchMedia("(hover: hover) and (pointer: fine)").matches;

if (beamCopies.length > 0 && supportsHover) {
  for (const node of beamCopies) {
    node.addEventListener("pointerenter", () => {
      node.dataset.beamActive = "true";
    });
    node.addEventListener("pointerleave", () => {
      node.dataset.beamActive = "false";
    });
  }
}
